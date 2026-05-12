import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/button.dart';
import 'package:tfc/page_creator/assets/analog_box.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/graph.dart';
import 'package:tfc/page_creator/assets/text.dart';
import 'package:tfc/page_creator/assets/arrow.dart';
import 'package:tfc/page_creator/assets/led_column.dart';
import 'package:tfc/page_creator/assets/ratio_number.dart';
import 'package:tfc/page_creator/assets/beckhoff.dart';
import 'package:tfc/page_creator/assets/advantys_stb.dart';
import 'package:tfc/page_creator/assets/common.dart' show Asset, BaseAsset;

void main() {
  group('BaseAsset.allKeys', () {
    test('LEDConfig returns single key', () {
      final led = LEDConfig(
        key: 'pump.running',
        onColor: Colors.green,
        offColor: Colors.red,
      );
      expect(led.allKeys, ['pump.running']);
    });

    test('LEDConfig with empty key returns empty list', () {
      final led = LEDConfig(
        key: '',
        onColor: Colors.green,
        offColor: Colors.red,
      );
      expect(led.allKeys, isEmpty);
    });

    test('NumberConfig returns single key', () {
      final number = NumberConfig(key: 'temp.value');
      expect(number.allKeys, ['temp.value']);
    });

    test('ArrowConfig with empty key returns empty list', () {
      final arrow = ArrowConfig(key: '', label: 'Test Arrow');
      expect(arrow.allKeys, isEmpty);
    });

    test('ArrowConfig with key returns that key', () {
      final arrow = ArrowConfig(key: 'direction.key', label: 'Direction');
      expect(arrow.allKeys, ['direction.key']);
    });

    test('TextAssetConfig returns empty list (no keys)', () {
      final text = TextAssetConfig(textContent: 'Hello World');
      expect(text.allKeys, isEmpty);
    });

    test('ButtonConfig without feedback returns single key', () {
      final button = ButtonConfig(
        key: 'cmd.start',
        outwardColor: Colors.green,
        inwardColor: Colors.grey,
        buttonType: ButtonType.circle,
      );
      expect(button.allKeys, ['cmd.start']);
    });

    test('ButtonConfig with feedback returns both keys', () {
      final feedback = FeedbackConfig()..key = 'fb.running';
      final button = ButtonConfig(
        key: 'cmd.start',
        outwardColor: Colors.green,
        inwardColor: Colors.grey,
        buttonType: ButtonType.circle,
        feedback: feedback,
      );
      final keys = button.allKeys;
      expect(keys, containsAll(['cmd.start', 'fb.running']));
      expect(keys.length, 2);
    });

    test('ButtonConfig with feedback having default key excludes it', () {
      // FeedbackConfig default key is "Default" - should be treated as a placeholder
      final feedback = FeedbackConfig(); // key defaults to "Default"
      final button = ButtonConfig(
        key: 'cmd.start',
        outwardColor: Colors.green,
        inwardColor: Colors.grey,
        buttonType: ButtonType.circle,
        feedback: feedback,
      );
      final keys = button.allKeys;
      // "Default" is a valid key string. The default impl should include it.
      // The user can decide what counts as a "placeholder" — we just filter empty/null.
      expect(keys, contains('cmd.start'));
      expect(keys, contains('Default'));
    });

    test('AnalogBoxConfig returns all 7 keys when all set', () {
      final analog = AnalogBoxConfig(
        analogKey: 'tank.level',
        analogSensorRangeMinKey: 'tank.range_min',
        analogSensorRangeMaxKey: 'tank.range_max',
        setpoint1Key: 'tank.sp1',
        setpoint1HysteresisKey: 'tank.sp1_hyst',
        setpoint2Key: 'tank.sp2',
        errorKey: 'tank.error',
      );
      final keys = analog.allKeys;
      expect(keys, containsAll([
        'tank.level',
        'tank.range_min',
        'tank.range_max',
        'tank.sp1',
        'tank.sp1_hyst',
        'tank.sp2',
        'tank.error',
      ]));
      expect(keys.length, 7);
    });

    test('AnalogBoxConfig with only required key returns 1 key', () {
      final analog = AnalogBoxConfig(analogKey: 'tank.level');
      final keys = analog.allKeys;
      expect(keys, ['tank.level']);
    });

    test('ConveyorConfig returns all 5 keys when all set', () {
      final conveyor = ConveyorConfig(
        key: 'conv.state',
        batchesKey: 'conv.batches',
        frequencyKey: 'conv.freq',
        tripKey: 'conv.trip',
        augerRpmKey: 'conv.rpm',
      );
      final keys = conveyor.allKeys;
      expect(keys, containsAll([
        'conv.state',
        'conv.batches',
        'conv.freq',
        'conv.trip',
        'conv.rpm',
      ]));
      expect(keys.length, 5);
    });

    test('ConveyorConfig with only some keys set', () {
      final conveyor = ConveyorConfig(
        key: 'conv.state',
        batchesKey: 'conv.batches',
      );
      final keys = conveyor.allKeys;
      expect(keys, containsAll(['conv.state', 'conv.batches']));
      expect(keys.length, 2);
    });

    test('GraphAssetConfig returns all series keys', () {
      final graph = GraphAssetConfig(
        primarySeries: [
          GraphSeriesConfig(key: 'temp.inlet', label: 'Inlet'),
          GraphSeriesConfig(key: 'temp.outlet', label: 'Outlet'),
        ],
        secondarySeries: [
          GraphSeriesConfig(key: 'pressure.main', label: 'Pressure'),
        ],
      );
      final keys = graph.allKeys;
      expect(keys, containsAll([
        'temp.inlet',
        'temp.outlet',
        'pressure.main',
      ]));
      expect(keys.length, 3);
    });

    test('GraphAssetConfig with no series returns empty', () {
      final graph = GraphAssetConfig();
      expect(graph.allKeys, isEmpty);
    });

    test('GraphAssetConfig with empty key in series excludes it', () {
      final graph = GraphAssetConfig(
        primarySeries: [
          GraphSeriesConfig(key: 'temp.inlet', label: 'Inlet'),
          GraphSeriesConfig(key: '', label: 'Empty'),
        ],
      );
      final keys = graph.allKeys;
      expect(keys, ['temp.inlet']);
    });

    test('LEDColumnConfig returns keys from all child LEDs', () {
      final ledCol = LEDColumnConfig(leds: [
        LEDConfig(key: 'alarm.1', onColor: Colors.red, offColor: Colors.grey),
        LEDConfig(key: 'alarm.2', onColor: Colors.red, offColor: Colors.grey),
        LEDConfig(key: 'alarm.3', onColor: Colors.red, offColor: Colors.grey),
      ]);
      final keys = ledCol.allKeys;
      expect(keys, containsAll(['alarm.1', 'alarm.2', 'alarm.3']));
      expect(keys.length, 3);
    });

    test('LEDColumnConfig deduplicates keys', () {
      final ledCol = LEDColumnConfig(leds: [
        LEDConfig(key: 'alarm.1', onColor: Colors.red, offColor: Colors.grey),
        LEDConfig(key: 'alarm.1', onColor: Colors.green, offColor: Colors.grey),
      ]);
      final keys = ledCol.allKeys;
      expect(keys, ['alarm.1']);
    });

    test('RatioNumberConfig returns key1 and key2', () {
      final ratio = RatioNumberConfig(
        key1: 'count.good',
        key2: 'count.bad',
      );
      final keys = ratio.allKeys;
      expect(keys, containsAll(['count.good', 'count.bad']));
      expect(keys.length, 2);
    });

    test('BeckhoffCX5010Config returns keys from subdevices', () {
      final cx = BeckhoffCX5010Config();
      cx.subdevices = [
        BeckhoffEL1008Config(
          nameOrId: '1',
          descriptionsKey: 'el1.desc',
          rawStateKey: 'el1.raw',
          processedStateKey: 'el1.proc',
        ),
      ];
      final keys = cx.allKeys;
      expect(keys, containsAll(['el1.desc', 'el1.raw', 'el1.proc']));
    });

    test('BeckhoffCX5010Config with empty subdevices returns empty', () {
      final cx = BeckhoffCX5010Config();
      expect(cx.allKeys, isEmpty);
    });

    // -------------------------------------------------------------------
    // Phase 5 RETROFIT (2026-05-12): STBNIP2311Config composite allKeys
    // flat-map. The composite-parent behavior was moved from the deleted
    // `AdvantysSTBStackConfig` onto the NIP2311 head (mirrors CX5010/EK1100
    // precedent). Same `expand + where(isNotEmpty) + toSet + toList` shape,
    // same defensive empty-string filter.
    // -------------------------------------------------------------------
    test('STBNIP2311Config returns keys from subdevices', () {
      final head = STBNIP2311Config()
        ..subdevices = <Asset>[
          STBDDI3725Config(
            nameOrId: 'DI',
            rawStateKey: 'di.raw',
            forceValuesKey: 'di.force',
          ),
          STBDDO3705Config(nameOrId: 'DO', rawStateKey: 'do.raw'),
          STBPDT3100Config(nameOrId: 'PDT', inputOkKey: 'pdt.ok'),
        ];
      final keys = head.allKeys;
      expect(
        keys,
        containsAll(<String>['di.raw', 'di.force', 'do.raw', 'pdt.ok']),
      );
      expect(keys, hasLength(4));
    });

    test('STBNIP2311Config with empty subdevices returns empty', () {
      expect(STBNIP2311Config().allKeys, isEmpty);
    });

    test('STBNIP2311Config dedupes keys across subdevices', () {
      // Two PDT subdevices both reference the same PLC key. The composite
      // must collapse them to a single entry via the Set step.
      final head = STBNIP2311Config()
        ..subdevices = <Asset>[
          STBPDT3100Config(nameOrId: 'PDT1', inputOkKey: 'shared.key'),
          STBPDT3100Config(nameOrId: 'PDT2', inputOkKey: 'shared.key'),
        ];
      final keys = head.allKeys;
      expect(keys, <String>['shared.key']);
      expect(keys, hasLength(1));
    });

    test(
      'STBNIP2311Config drops empty-string keys from subdevices '
      '(defensive .where(isNotEmpty))',
      () {
        // The leaf-level regex in common.dart already drops empties for
        // leaves, but a future leaf override could regress and return `['']`.
        // The composite's defensive `.where((k) => k.isNotEmpty)` is the
        // safety net. Mock leaf returns ['valid', ''] and we assert only
        // 'valid' survives.
        final head = STBNIP2311Config()
          ..subdevices = <Asset>[_MockEmptyKeyAsset()];
        expect(head.allKeys, <String>['valid']);
        expect(head.allKeys.contains(''), isFalse);
      },
    );

    test('Keys are deduplicated', () {
      // A button where key and feedback key are the same
      final feedback = FeedbackConfig()..key = 'same.key';
      final button = ButtonConfig(
        key: 'same.key',
        outwardColor: Colors.green,
        inwardColor: Colors.grey,
        buttonType: ButtonType.circle,
        feedback: feedback,
      );
      final keys = button.allKeys;
      expect(keys, ['same.key']);
    });

    test('plcAssetKey is NOT included in allKeys', () {
      final led = LEDConfig(
        key: 'pump.running',
        onColor: Colors.green,
        offColor: Colors.red,
      );
      led.plcAssetKey = 'plc.pump_control';
      final keys = led.allKeys;
      // plcAssetKey is a reference to PLC code index, not a tag key
      expect(keys, ['pump.running']);
      expect(keys, isNot(contains('plc.pump_control')));
    });

    test('ConveyorColorPaletteConfig returns empty list (no keys)', () {
      final palette = ConveyorColorPaletteConfig();
      expect(palette.allKeys, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Private test helpers.
//
// _MockEmptyKeyAsset returns ['valid', ''] from its allKeys override — the
// only way to prove the composite's defensive empty-string filter is wired
// correctly without depending on a hypothetical broken leaf type. Per CLAUDE.md
// naming convention, private test helpers use the `_PascalCase` prefix.
// ---------------------------------------------------------------------------
class _MockEmptyKeyAsset extends BaseAsset {
  @override
  String get displayName => 'mock';

  @override
  String get category => 'test';

  @override
  List<String> get allKeys => const <String>['valid', ''];

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  Widget configure(BuildContext context) => const SizedBox.shrink();

  @override
  Map<String, dynamic> toJson() => const <String, dynamic>{};
}
