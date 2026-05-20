import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/start_stop_button.dart';

/// JSON-level tests for the manual-mode-key / polarity / inactive-color
/// fields added to `StartStopPillButtonConfig` in the v1.1 hardening sweep.
///
/// Mirrors the precedent set by `ButtonConfig` (commits 826ded65 / 6880c6e4):
/// the start/stop pill button gains a "manual mode" gate that disables BOTH
/// the Start and Stop segments when the system is NOT in manual mode. This
/// is conceptually the inverse of `disabledKey` — the live BOOL is the
/// "is operator allowed to drive this output?" signal, defaulting to
/// "manual when TRUE".
///
/// Backwards-compat contract: existing persisted StartStopPillButtonConfig
/// JSON predating these fields MUST still load, with sensible defaults
/// populated (manualModeKey=null → behaves exactly as before).
void main() {
  Map<String, dynamic> baseJson() => <String, dynamic>{
        'asset_name': 'StartStopPillButtonConfig',
        'coordinates': {'x': 0.0, 'y': 0.0},
        'size': {'width': 0.1, 'height': 0.1},
        'text': null,
        'textPos': 'right',
        'techDocId': null,
        'plcAssetKey': null,
        'runKey': 'cmd/run',
        'stopKey': 'cmd/stop',
        'cleanKey': null,
        'runningKey': 'fb/running',
        'stoppedKey': 'fb/stopped',
        'cleaningKey': null,
      };

  group('StartStopPillButtonConfig defaults (manual-mode-key / polarity / color)',
      () {
    test('default manualModeKey is null', () {
      final config = StartStopPillButtonConfig.preview();
      expect(config.manualModeKey, isNull);
    });

    test('default manualModePolarity is manualWhenTrue', () {
      final config = StartStopPillButtonConfig.preview();
      expect(config.manualModePolarity, ManualModePolarity.manualWhenTrue);
    });

    test('default inactiveColor is a sensible muted gray', () {
      final config = StartStopPillButtonConfig.preview();
      final c = config.inactiveColor;
      expect(c.a, 1.0);
      final r = c.r;
      final g = c.g;
      final b = c.b;
      // Near-equal channels → effectively gray.
      expect((r - g).abs() < 1.0 / 255.0, isTrue,
          reason: 'default inactiveColor channels must be near-equal (gray)');
      expect((g - b).abs() < 1.0 / 255.0, isTrue,
          reason: 'default inactiveColor channels must be near-equal (gray)');
    });
  });

  group('ManualModePolarity enum', () {
    test('has exactly two values', () {
      expect(ManualModePolarity.values.length, 2);
    });

    test('values are manualWhenTrue and manualWhenFalse', () {
      final names = ManualModePolarity.values.map((v) => v.name).toSet();
      expect(names, {'manualWhenTrue', 'manualWhenFalse'});
    });
  });

  group('StartStopPillButtonConfig JSON round-trip', () {
    test('legacy JSON (no manual-mode-* fields) loads with defaults', () {
      final legacyJson = baseJson();
      final config = StartStopPillButtonConfig.fromJson(legacyJson);

      expect(config.manualModeKey, isNull,
          reason: 'missing manualModeKey must default to null');
      expect(config.manualModePolarity, ManualModePolarity.manualWhenTrue,
          reason:
              'missing manualModePolarity must default to manualWhenTrue');
      // Color must be present and gray-ish.
      expect(config.inactiveColor.a, 1.0);
    });

    test('round-trips with all three new fields explicitly set', () {
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )
        ..manualModeKey = 'mode/manual'
        ..manualModePolarity = ManualModePolarity.manualWhenFalse
        ..inactiveColor = const Color(0xFF334455);

      // Mirror persistence path: encode + decode to plain Map.
      final raw = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;

      // Wire-format keys are stable — persisted to PostgreSQL via Preferences.
      expect(raw.containsKey('manual_mode_key'), isTrue,
          reason: 'wire key "manual_mode_key" must be present');
      expect(raw.containsKey('manual_mode_polarity'), isTrue,
          reason: 'wire key "manual_mode_polarity" must be present');
      expect(raw.containsKey('inactive_color'), isTrue,
          reason: 'wire key "inactive_color" must be present');

      final restored = StartStopPillButtonConfig.fromJson(raw);
      expect(restored.manualModeKey, 'mode/manual');
      expect(restored.manualModePolarity, ManualModePolarity.manualWhenFalse);
      expect((restored.inactiveColor.r * 255).round(),
          (config.inactiveColor.r * 255).round());
      expect((restored.inactiveColor.g * 255).round(),
          (config.inactiveColor.g * 255).round());
      expect((restored.inactiveColor.b * 255).round(),
          (config.inactiveColor.b * 255).round());
    });

    test('toJson on a default preview config does not throw', () {
      final config = StartStopPillButtonConfig.preview();
      final json = config.toJson();
      expect(json['manual_mode_key'], isNull);
    });
  });
}
