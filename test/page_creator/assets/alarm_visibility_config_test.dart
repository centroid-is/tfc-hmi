import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/alarm_visibility.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

AlarmActive activeFx({
  String uid = 'a1',
  AlarmLevel level = AlarmLevel.error,
  DateTime? timestamp,
  String title = 'Alarm title',
  String description = 'Alarm description',
}) {
  final rule = AlarmRule(
    level: level,
    expression: ExpressionConfig(value: Expression(formula: 'x')),
    acknowledgeRequired: false,
  );
  return AlarmActive(
    alarm: Alarm(
      config: AlarmConfig(
        uid: uid,
        title: title,
        description: description,
        rules: [rule],
      ),
    ),
    notification: AlarmNotification(
      uid: uid,
      active: true,
      expression: 'x',
      rule: rule,
      timestamp: timestamp ?? DateTime(2026, 1, 1),
    ),
  );
}

void main() {
  group('AlarmVisibilityConfig', () {
    test('defaults', () {
      final config = AlarmVisibilityConfig();
      expect(config.alarmUids, isEmpty);
      expect(config.showWhenInactive, isFalse);
      // On by default: the beacon placement is the opt-in, the switch is the
      // per-beacon opt-out. This default is what makes the navigation pulse
      // work without a second, hidden setting.
      expect(config.announceInNavigation, isTrue);
      expect(config.isPreview, isFalse);
      expect(config.textPos, TextPos.below);
      expect(config.displayName, 'Alarm');
      expect(config.category, 'Visualization');
      expect(config.assetName, 'AlarmVisibilityConfig');
    });

    test('preview factory marks the instance and is never serialized', () {
      final config = AlarmVisibilityConfig.preview();
      expect(config.isPreview, isTrue);
      expect(config.toJson().containsKey('isPreview'), isFalse);
      expect(config.toJson().containsKey('is_preview'), isFalse);
    });

    test('JSON round trip preserves fields', () {
      final config = AlarmVisibilityConfig(
        alarmUids: ['uid-1', 'uid-2'],
        showWhenInactive: true,
        announceInNavigation: false,
      )
        ..text = 'Pump alarms'
        ..coordinates = Coordinates(x: 0.25, y: 0.5)
        ..size = const RelativeSize(width: 0.05, height: 0.05);

      final restored = AlarmVisibilityConfig.fromJson(config.toJson());
      expect(restored.alarmUids, ['uid-1', 'uid-2']);
      expect(restored.showWhenInactive, isTrue);
      expect(restored.announceInNavigation, isFalse,
          reason: 'an explicit opt-out must survive the round trip');
      expect(restored.text, 'Pump alarms');
      expect(restored.coordinates.x, 0.25);
      expect(restored.coordinates.y, 0.5);
      expect(restored.size.width, 0.05);
      expect(restored.isPreview, isFalse);
    });

    test('fromJson tolerates missing new fields (legacy pages)', () {
      final json = AlarmVisibilityConfig().toJson()
        ..remove('alarm_uids')
        ..remove('show_when_inactive')
        ..remove('announce_in_navigation');
      final restored = AlarmVisibilityConfig.fromJson(json);
      expect(restored.alarmUids, isEmpty);
      expect(restored.showWhenInactive, isFalse);
      // Every beacon already on a plant page predates the switch; defaulting
      // them on is the whole migration.
      expect(restored.announceInNavigation, isTrue);
    });

    test('AssetRegistry.parse finds it by asset_name', () {
      final config = AlarmVisibilityConfig(alarmUids: ['uid-1']);
      final parsed = AssetRegistry.parse({
        'assets': [config.toJson()],
      });
      expect(parsed, hasLength(1));
      final restored = parsed.single as AlarmVisibilityConfig;
      expect(restored.alarmUids, ['uid-1']);
    });

    test('createDefaultAsset serves the palette', () {
      final asset = AssetRegistry.createDefaultAsset(AlarmVisibilityConfig);
      expect(asset, isA<AlarmVisibilityConfig>());
      expect((asset as AlarmVisibilityConfig).isPreview, isTrue);
    });
  });

  group('matchingActiveAlarms', () {
    test('empty uid list matches every alarm', () {
      final active = [activeFx(uid: 'a'), activeFx(uid: 'b')];
      expect(matchingActiveAlarms(active, []), hasLength(2));
    });

    test('non-empty uid list filters to bound alarms only', () {
      final active = [activeFx(uid: 'a'), activeFx(uid: 'b')];
      final matched = matchingActiveAlarms(active, ['b']);
      expect(matched, hasLength(1));
      expect(matched.single.alarm.config.uid, 'b');
    });

    test('keeps only the highest level per uid', () {
      final active = [
        activeFx(uid: 'a', level: AlarmLevel.info),
        activeFx(uid: 'a', level: AlarmLevel.error),
        activeFx(uid: 'a', level: AlarmLevel.warning),
      ];
      final matched = matchingActiveAlarms(active, []);
      expect(matched, hasLength(1));
      expect(matched.single.notification.rule.level, AlarmLevel.error);
    });

    test('sorts by level descending, then timestamp descending', () {
      final active = [
        activeFx(uid: 'old-error', level: AlarmLevel.error,
            timestamp: DateTime(2026, 1, 1)),
        activeFx(uid: 'info', level: AlarmLevel.info),
        activeFx(uid: 'new-error', level: AlarmLevel.error,
            timestamp: DateTime(2026, 1, 2)),
        activeFx(uid: 'warning', level: AlarmLevel.warning),
      ];
      final matched = matchingActiveAlarms(active, []);
      expect(
        matched.map((a) => a.alarm.config.uid).toList(),
        ['new-error', 'old-error', 'warning', 'info'],
      );
    });
  });
}
