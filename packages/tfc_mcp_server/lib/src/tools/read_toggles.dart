import 'dart:convert';

import 'package:tfc_dart/core/preferences.dart' show PreferencesApi;

import 'tool_toggles.dart';

/// Reads the current [McpConfig] from preferences.
///
/// On first load, migrates any legacy individual keys
/// (`mcp_server_enabled`, `mcp_chat_enabled`, `mcp_server_port`,
/// `mcp_tools_*_enabled`) into the consolidated [McpConfig.kPrefKey] JSON
/// blob. After migration the legacy keys remain in the database but are
/// no longer read.
///
/// Returns [McpConfig.defaults] when no config exists yet.
Future<McpConfig> readMcpConfigFromPreferences(PreferencesApi prefs) async {
  final json = await prefs.getString(McpConfig.kPrefKey);

  if (json != null) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return McpConfig.fromJson(map);
    } catch (_) {
      // Corrupted JSON -- fall through to migration / defaults.
    }
  }

  // No consolidated config yet -- attempt migration from legacy keys.
  return _migrateFromLegacyKeys(prefs);
}

/// Writes [config] to the single [McpConfig.kPrefKey] preference.
Future<void> writeMcpConfigToPreferences(
  PreferencesApi prefs,
  McpConfig config,
) async {
  final json = jsonEncode(config.toJson());
  await prefs.setString(McpConfig.kPrefKey, json);
}

/// Reads the [McpToolToggles] portion from preferences.
///
/// Convenience wrapper that reads the full [McpConfig] and returns
/// just the toggles. Backwards-compatible signature for callers that
/// only need toggles (e.g. MCP server startup).
Future<McpToolToggles> readTogglesFromPreferences(PreferencesApi prefs) async {
  final config = await readMcpConfigFromPreferences(prefs);
  return config.toggles;
}

/// Migrates legacy individual preference keys into a consolidated
/// [McpConfig] JSON blob.
///
/// Reads each legacy key, constructs the config, writes the consolidated
/// blob, and returns the result. If no legacy keys exist either, returns
/// [McpConfig.defaults].
Future<McpConfig> _migrateFromLegacyKeys(PreferencesApi prefs) async {
  // Read legacy server/chat/port keys.
  final serverEnabled = await prefs.getBool('mcp_server_enabled') ?? false;
  final chatEnabled = await prefs.getBool('mcp_chat_enabled') ?? false;
  final port = await prefs.getInt('mcp_server_port') ?? McpConfig.defaultPort;

  // Read legacy toggle keys.
  final toggles = McpToolToggles(
    tagsEnabled: await prefs.getBool(McpToolToggles.kTagsEnabled) ?? true,
    alarmsEnabled: await prefs.getBool(McpToolToggles.kAlarmsEnabled) ?? true,
    configEnabled: await prefs.getBool(McpToolToggles.kConfigEnabled) ?? true,
    drawingsEnabled:
        await prefs.getBool(McpToolToggles.kDrawingsEnabled) ?? true,
    trendsEnabled: await prefs.getBool(McpToolToggles.kTrendsEnabled) ?? true,
    plcCodeEnabled:
        await prefs.getBool(McpToolToggles.kPlcCodeEnabled) ?? true,
    proposalsEnabled:
        await prefs.getBool(McpToolToggles.kProposalsEnabled) ?? true,
    techDocsEnabled:
        await prefs.getBool(McpToolToggles.kTechDocsEnabled) ?? true,
  );

  final config = McpConfig(
    serverEnabled: serverEnabled,
    chatEnabled: chatEnabled,
    port: port,
    toggles: toggles,
  );

  // Persist the consolidated config so future reads use the fast path.
  await writeMcpConfigToPreferences(prefs, config);

  return config;
}
