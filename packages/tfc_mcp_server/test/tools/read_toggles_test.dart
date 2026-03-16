import 'dart:convert';

import 'package:test/test.dart';
import 'package:tfc_dart/core/preferences.dart' show InMemoryPreferences;
import 'package:tfc_mcp_server/src/tools/read_toggles.dart';
import 'package:tfc_mcp_server/src/tools/tool_toggles.dart';

void main() {
  group('readMcpConfigFromPreferences', () {
    test('returns defaults when no key exists and no legacy keys', () async {
      final prefs = InMemoryPreferences();
      final config = await readMcpConfigFromPreferences(prefs);

      expect(config.serverEnabled, isFalse);
      expect(config.chatEnabled, isFalse);
      expect(config.port, McpConfig.defaultPort);
      expect(config.toggles.tagsEnabled, isTrue);
      expect(config.toggles.alarmsEnabled, isTrue);
      expect(config.toggles.configEnabled, isTrue);
      expect(config.toggles.drawingsEnabled, isTrue);
      expect(config.toggles.trendsEnabled, isTrue);
      expect(config.toggles.plcCodeEnabled, isTrue);
      expect(config.toggles.proposalsEnabled, isTrue);
      expect(config.toggles.techDocsEnabled, isTrue);
    });

    test('reads from consolidated JSON key', () async {
      final prefs = InMemoryPreferences();
      final config = McpConfig(
        serverEnabled: true,
        chatEnabled: true,
        port: 9999,
        toggles: const McpToolToggles(tagsEnabled: false, trendsEnabled: false),
      );
      await prefs.setString(McpConfig.kPrefKey, jsonEncode(config.toJson()));

      final result = await readMcpConfigFromPreferences(prefs);

      expect(result.serverEnabled, isTrue);
      expect(result.chatEnabled, isTrue);
      expect(result.port, 9999);
      expect(result.toggles.tagsEnabled, isFalse);
      expect(result.toggles.trendsEnabled, isFalse);
      expect(result.toggles.alarmsEnabled, isTrue);
    });

    test('migrates legacy individual keys into consolidated config', () async {
      final prefs = InMemoryPreferences();

      // Set legacy keys as if they were from an older version.
      await prefs.setBool('mcp_server_enabled', true);
      await prefs.setBool('mcp_chat_enabled', true);
      await prefs.setInt('mcp_server_port', 7777);
      await prefs.setBool(McpToolToggles.kTagsEnabled, false);
      await prefs.setBool(McpToolToggles.kTrendsEnabled, false);
      await prefs.setBool(McpToolToggles.kTechDocsEnabled, false);

      final config = await readMcpConfigFromPreferences(prefs);

      expect(config.serverEnabled, isTrue);
      expect(config.chatEnabled, isTrue);
      expect(config.port, 7777);
      expect(config.toggles.tagsEnabled, isFalse);
      expect(config.toggles.alarmsEnabled, isTrue);
      expect(config.toggles.trendsEnabled, isFalse);
      expect(config.toggles.techDocsEnabled, isFalse);
      expect(config.toggles.plcCodeEnabled, isTrue);

      // Verify the consolidated key was written (migration persists).
      final raw = await prefs.getString(McpConfig.kPrefKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['serverEnabled'], isTrue);
    });

    test('second read uses consolidated key (no re-migration)', () async {
      final prefs = InMemoryPreferences();

      // Simulate migration already happened.
      final config = const McpConfig(
        serverEnabled: true,
        chatEnabled: false,
        port: 5555,
      );
      await prefs.setString(McpConfig.kPrefKey, jsonEncode(config.toJson()));

      // Even if legacy keys exist with different values, consolidated wins.
      await prefs.setBool('mcp_server_enabled', false);

      final result = await readMcpConfigFromPreferences(prefs);
      expect(result.serverEnabled, isTrue,
          reason: 'Should read from consolidated key, not legacy');
    });
  });

  group('readTogglesFromPreferences (backwards-compatible)', () {
    test('returns all-enabled when no keys are set', () async {
      final prefs = InMemoryPreferences();
      final toggles = await readTogglesFromPreferences(prefs);

      expect(toggles.tagsEnabled, isTrue);
      expect(toggles.alarmsEnabled, isTrue);
      expect(toggles.configEnabled, isTrue);
      expect(toggles.drawingsEnabled, isTrue);
      expect(toggles.trendsEnabled, isTrue);
      expect(toggles.plcCodeEnabled, isTrue);
      expect(toggles.proposalsEnabled, isTrue);
      expect(toggles.techDocsEnabled, isTrue);
    });

    test('respects individually disabled toggles via legacy keys', () async {
      final prefs = InMemoryPreferences();
      await prefs.setBool(McpToolToggles.kTagsEnabled, false);
      await prefs.setBool(McpToolToggles.kTrendsEnabled, false);
      await prefs.setBool(McpToolToggles.kTechDocsEnabled, false);

      final toggles = await readTogglesFromPreferences(prefs);

      expect(toggles.tagsEnabled, isFalse);
      expect(toggles.alarmsEnabled, isTrue);
      expect(toggles.configEnabled, isTrue);
      expect(toggles.drawingsEnabled, isTrue);
      expect(toggles.trendsEnabled, isFalse);
      expect(toggles.plcCodeEnabled, isTrue);
      expect(toggles.proposalsEnabled, isTrue);
      expect(toggles.techDocsEnabled, isFalse);
    });

    test('reads from consolidated config when available', () async {
      final prefs = InMemoryPreferences();
      final config = const McpConfig(
        toggles: McpToolToggles(plcCodeEnabled: false),
      );
      await prefs.setString(McpConfig.kPrefKey, jsonEncode(config.toJson()));

      final toggles = await readTogglesFromPreferences(prefs);
      expect(toggles.plcCodeEnabled, isFalse);
      expect(toggles.tagsEnabled, isTrue);
    });
  });

  group('writeMcpConfigToPreferences', () {
    test('writes and reads back correctly', () async {
      final prefs = InMemoryPreferences();
      final config = const McpConfig(
        serverEnabled: true,
        chatEnabled: true,
        port: 1234,
        toggles: McpToolToggles(
          alarmsEnabled: false,
          drawingsEnabled: false,
        ),
      );

      await writeMcpConfigToPreferences(prefs, config);
      final result = await readMcpConfigFromPreferences(prefs);

      expect(result.serverEnabled, isTrue);
      expect(result.chatEnabled, isTrue);
      expect(result.port, 1234);
      expect(result.toggles.alarmsEnabled, isFalse);
      expect(result.toggles.drawingsEnabled, isFalse);
      expect(result.toggles.tagsEnabled, isTrue);
    });
  });
}
