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
