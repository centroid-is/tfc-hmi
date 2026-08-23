// The operator-visible half of starting an update.
//
// Launching the manager is fire-and-forget: main() wraps it in `unawaited`
// and the success path never returns, because the manager needs this process
// gone before it can replace the install. That shape meant a failure had
// nowhere to go — the closure had no catch, so the error went to the zone
// handler and the only trace was a stderr line. The operator pressed Update
// and the app sat there.
//
// Which is the worst of the three outcomes. A successful update is obvious
// (the app exits), and a crash is obvious. "Nothing happened" reads as a
// misclick, so it gets pressed again.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/update_channel.dart';
import 'package:tfc/core/update_launch.dart';

void main() {
  group('startManagerUpdate', () {
    late List<String> logged;
    late List<String> shown;
    late List<({String? version, String channel})> launched;
    late int handedOff;

    setUp(() {
      logged = [];
      shown = [];
      launched = [];
      handedOff = 0;
    });

    Future<void> run({
      required Future<String> Function() readChannel,
      required Future<void> Function(String?, String) launch,
      String targetVersion = '2026.8.23',
    }) =>
        startManagerUpdate(
          targetVersion: targetVersion,
          readChannel: readChannel,
          launch: launch,
          log: logged.add,
          show: shown.add,
          onHandedOff: () => handedOff++,
        );

    Future<void> launchOk(String? v, String c) async =>
        launched.add((version: v, channel: c));

    test('hands off to the manager once it is running', () async {
      await run(
        readChannel: () async => updateChannelStable,
        launch: launchOk,
      );

      expect(launched, hasLength(1));
      expect(launched.single.channel, equals(updateChannelStable));
      expect(launched.single.version, equals('2026.8.23'));
      expect(handedOff, equals(1), reason: 'the app must exit for the manager');
      expect(shown, isEmpty, reason: 'nothing to say when it worked');
    });

    test('omits the version on the latest channel', () async {
      await run(
        readChannel: () async => updateChannelLatest,
        launch: launchOk,
      );

      expect(launched.single.version, isNull,
          reason: 'the manager resolves the channel head itself');
    });

    // The bug. Every one of these three assertions was false before.
    test('a launch failure is logged AND shown, and does not hand off',
        () async {
      await run(
        readChannel: () async => updateChannelStable,
        launch: (_, __) async => throw StateError('APPDATA is not set'),
      );

      expect(logged, isNotEmpty, reason: 'the detail belongs in the log');
      expect(logged.single, contains('APPDATA is not set'));
      expect(shown, hasLength(1), reason: 'the operator must be told');
      expect(handedOff, isZero,
          reason: 'never exit when the manager did not start');
    });

    test('a failure reading the channel is reported the same way', () async {
      await run(
        readChannel: () async => throw StateError('prefs unavailable'),
        launch: launchOk,
      );

      expect(launched, isEmpty);
      expect(logged.single, contains('prefs unavailable'));
      expect(shown, hasLength(1));
      expect(handedOff, isZero);
    });

    // "Update failed" tells an operator nothing they did not already know.
    // The message has to name the next move, because the person reading it is
    // standing on a plant floor and not going to open a log.
    test('what it shows names a next step, not just the failure', () async {
      await run(
        readChannel: () async => updateChannelStable,
        launch: (_, __) async => throw StateError('boom'),
      );

      final message = shown.single;
      expect(message.toLowerCase(), contains('update'));
      expect(message, contains('again'),
          reason: 'retrying is the first thing to try');
      expect(message.toLowerCase(), contains('restart'),
          reason: 'and the fallback when retrying does not help');
    });

    test('the shown message stays free of raw exception text', () async {
      await run(
        readChannel: () async => updateChannelStable,
        launch: (_, __) async =>
            throw const FileSystemException('cannot open', r'C:\x\y.exe'),
      );

      expect(shown.single, isNot(contains('FileSystemException')),
          reason: 'a class name is noise to an operator; it goes in the log');
      expect(logged.single, contains('FileSystemException'),
          reason: 'and it must not be lost — the log is where it lives');
    });
  });
}
