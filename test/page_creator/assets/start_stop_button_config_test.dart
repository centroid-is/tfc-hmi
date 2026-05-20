import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/start_stop_button.dart';

/// JSON-level tests for the manual peer-mode fields added to
/// `StartStopPillButtonConfig`.
///
/// Design contract: manual is a peer mode alongside run / clean / stop —
/// same shape as those existing modes (a state BOOL key for "is the
/// system currently in manual mode" + a command BOOL key pulsed to ask
/// the PLC to switch into manual mode). NOT a lockout / disable gate.
///
/// Backwards-compat contract: existing persisted JSON predating these
/// fields MUST still load, with all three new fields defaulting to
/// `null` (which means "no manual segment is rendered").
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

  group('StartStopPillButtonConfig defaults (manual peer-mode)', () {
    test('default manualStateKey is null', () {
      final config = StartStopPillButtonConfig.preview();
      expect(config.manualStateKey, isNull);
    });

    test('default manualCommandKey is null', () {
      final config = StartStopPillButtonConfig.preview();
      expect(config.manualCommandKey, isNull);
    });

    test('default manualLabel is null', () {
      final config = StartStopPillButtonConfig.preview();
      expect(config.manualLabel, isNull);
    });
  });

  group('StartStopPillButtonConfig JSON round-trip (manual peer-mode)', () {
    test('legacy JSON (no manual_* fields) loads with all defaults null', () {
      final legacyJson = baseJson();
      final config = StartStopPillButtonConfig.fromJson(legacyJson);
      expect(config.manualStateKey, isNull,
          reason: 'missing manual_state_key must default to null');
      expect(config.manualCommandKey, isNull,
          reason: 'missing manual_command_key must default to null');
      expect(config.manualLabel, isNull,
          reason: 'missing manual_label must default to null');
    });

    test('round-trips with manualStateKey + manualCommandKey set', () {
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )
        ..manualStateKey = 'fb/manual'
        ..manualCommandKey = 'cmd/manual'
        ..manualLabel = 'Hand Mode';

      final raw = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;

      expect(raw.containsKey('manual_state_key'), isTrue,
          reason: 'wire key "manual_state_key" must be present');
      expect(raw.containsKey('manual_command_key'), isTrue,
          reason: 'wire key "manual_command_key" must be present');
      expect(raw.containsKey('manual_label'), isTrue,
          reason: 'wire key "manual_label" must be present');

      final restored = StartStopPillButtonConfig.fromJson(raw);
      expect(restored.manualStateKey, 'fb/manual');
      expect(restored.manualCommandKey, 'cmd/manual');
      expect(restored.manualLabel, 'Hand Mode');
    });

    test('toJson on a default preview config does not throw', () {
      final config = StartStopPillButtonConfig.preview();
      final json = config.toJson();
      expect(json['manual_state_key'], isNull);
      expect(json['manual_command_key'], isNull);
      expect(json['manual_label'], isNull);
    });
  });

  group('StartStopPillButtonConfig.allKeys (manual peer-mode)', () {
    // BaseAsset.allKeys auto-extracts any field whose JSON name matches
    // `Key$` or `_key$` (mirrors the precedent that runKey / stopKey /
    // runningKey are ALL included). The peer-mode manual fields use the
    // wire names `manual_state_key` and `manual_command_key`, both of
    // which match the pattern and so MUST be picked up.
    test('manualStateKey is reported in allKeys when set', () {
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )..manualStateKey = 'fb/manual';
      expect(config.allKeys, contains('fb/manual'));
    });

    test('manualCommandKey is reported in allKeys when set', () {
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      )..manualCommandKey = 'cmd/manual';
      expect(config.allKeys, contains('cmd/manual'));
    });

    test('absent manual_* keys do not pollute allKeys', () {
      final config = StartStopPillButtonConfig(
        runKey: 'cmd/run',
        stopKey: 'cmd/stop',
        runningKey: 'fb/running',
        stoppedKey: 'fb/stopped',
      );
      expect(config.allKeys, isNot(contains('')));
      expect(config.allKeys, isNot(contains(null)));
    });
  });
}
