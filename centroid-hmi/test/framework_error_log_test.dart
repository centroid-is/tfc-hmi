/// What a framework error looks like once it reaches the log file.
///
/// A layout overflow's stack trace is the paint stack — every frame belongs to
/// the framework, none of them name the asset that overflowed. The widget is
/// only ever in the error details' information collector, so the log line has
/// to reach in and pull it out. Without that, `run-hmi.ps1` leaves a log
/// saying "A RenderFlex overflowed by 23 pixels on the right" and nothing at
/// all about which one.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:centroidx/main.dart';

/// Error details carrying [information], the way the framework attaches the
/// error-causing widget and the offending RenderFlex.
FlutterErrorDetails _details(
  String exception, {
  List<DiagnosticsNode> information = const [],
  StackTrace? stack,
}) =>
    FlutterErrorDetails(
      exception: exception,
      stack: stack,
      informationCollector: information.isEmpty ? null : () => information,
    );

/// A stack trace built from [frames], the way `StackTrace.toString()` renders
/// one: numbered frames, one per line.
StackTrace _trace(List<String> frames) => StackTrace.fromString([
      for (var i = 0; i < frames.length; i++) '#${i.toString().padRight(6)}${frames[i]}',
    ].join('\n'));

const _frameworkFrame =
    'ChangeNotifier.notifyListeners (package:flutter/src/foundation/change_notifier.dart:432:24)';
const _assetFrame =
    'AirCab.build (package:tfc/page_creator/assets/aircab.dart:133:5)';
const _appFrame = 'MyApp.build (package:centroidx/main.dart:600:12)';

void main() {
  group('describeFrameworkError', () {
    test('carries the exception itself', () {
      final line = describeFrameworkError(
          _details('A RenderFlex overflowed by 23 pixels on the right.'));

      expect(line, contains('A RenderFlex overflowed by 23 pixels'));
      expect(line, startsWith('Flutter framework error:'));
    });

    test('names the error-causing widget when the details carry one', () {
      final line = describeFrameworkError(_details(
        'setState() called during build',
        information: [
          DiagnosticsNode.message(
              'The relevant error-causing widget was: AirCab '
              'lib/page_creator/assets/aircab.dart:128'),
        ],
      ));

      expect(line, contains('AirCab'),
          reason: 'the asset name is the whole point of the extra line');
      expect(line, contains('aircab.dart:128'));
    });

    test('keeps the creator chain of an overflowing RenderFlex', () {
      final line = describeFrameworkError(_details(
        'A RenderFlex overflowed by 23 pixels on the right.',
        information: [
          DiagnosticsNode.message('The specific RenderFlex in question is: '
              'RenderFlex#a1b2 relayoutBoundary=up3 OVERFLOWING\n'
              '  creator: Row <- Padding <- ListActiveAlarms'),
        ],
      ));

      expect(line, contains('creator: Row <- Padding <- ListActiveAlarms'));
    });

    test('drops the collector lines that name nothing', () {
      final line = describeFrameworkError(_details(
        'A RenderFlex overflowed by 23 pixels on the right.',
        information: [
          DiagnosticsNode.message(
              'The overflowing RenderFlex has an orientation of Axis.horizontal.'),
          DiagnosticsNode.message('Consider applying a flex factor.'),
        ],
      ));

      expect(line, isNot(contains('Consider applying a flex factor')),
          reason: 'boilerplate advice is what buried the useful line before');
      expect(line, isNot(contains('Axis.horizontal')));
      expect(line.trim(), endsWith('on the right.'),
          reason: 'with nothing to add, the line is the message and no more');
    });

    test('an unadorned error gets no trailing newline', () {
      final line = describeFrameworkError(_details('boom'));

      expect(line, 'Flutter framework error: boom');
    });

    test('trims a creator chain that runs to the root', () {
      // The real chain reaches the root: Row <- Padding <- ... <- MyApp. Kept
      // whole it is thousands of characters per error, per frame while the
      // overflow persists.
      final long = 'creator: ${List.filled(200, 'Padding').join(' <- ')}';
      final line = describeFrameworkError(_details(
        'A RenderFlex overflowed.',
        information: [DiagnosticsNode.message(long)],
      ));

      expect(long.length, greaterThan(kCulpritLineLimit),
          reason: 'the fixture has to be long enough to be worth trimming');
      expect(line, contains('...'), reason: 'trimming is marked, not silent');
      expect(line.length, lessThan(long.length),
          reason: 'the whole chain must not reach the log');
      expect(line, contains('creator: Padding'),
          reason: 'the head of the chain is the part that names the asset');
    });
  });

  group('appFramesOf', () {
    test('keeps the app\'s frames and drops the framework\'s', () {
      final frames = appFramesOf(_trace([
        _frameworkFrame,
        _frameworkFrame,
        _assetFrame,
        _frameworkFrame,
      ]));

      expect(frames, contains('aircab.dart:133'),
          reason: 'the asset frame is the one worth printing');
      expect(frames, isNot(contains('change_notifier.dart')),
          reason: 'the logger already prints eight of these and they are '
              'what buried the useful frame');
      expect(frames.split('\n'), hasLength(1));
    });

    test('recognises both of the app\'s packages', () {
      final frames = appFramesOf(_trace([_assetFrame, _appFrame]));

      expect(frames, contains('package:tfc/'));
      expect(frames, contains('package:centroidx/'));
    });

    test('keeps the frames in the order the trace had them', () {
      final frames =
          appFramesOf(_trace([_assetFrame, _frameworkFrame, _appFrame]));

      expect(frames.indexOf('aircab.dart'), lessThan(frames.indexOf('main.dart')),
          reason: 'the innermost frame names the asset; reversing it buries '
              'the answer under the app shell again');
    });

    test('stops at ten', () {
      final frames = appFramesOf(_trace([
        for (var i = 0; i < 40; i++) 'F$i (package:tfc/a.dart:$i:1)',
      ]));

      expect(frames.split('\n'), hasLength(kAppFrameLimit));
      expect(frames, contains('package:tfc/a.dart:0:'),
          reason: 'the cap keeps the innermost frames, not the outermost');
      expect(frames, isNot(contains('package:tfc/a.dart:39:')));
    });

    test('a framework-only trace yields nothing', () {
      expect(appFramesOf(_trace([_frameworkFrame, _frameworkFrame])), isEmpty);
    });

    test('a null stack yields nothing', () {
      expect(appFramesOf(null), isEmpty);
    });
  });

  group('describeFrameworkError with a stack', () {
    test('appends the app frames under their own heading', () {
      final line = describeFrameworkError(_details(
        'setState() called during build',
        stack: _trace([_frameworkFrame, _assetFrame]),
      ));

      expect(line, contains('app frames:'));
      expect(line, contains('aircab.dart:133'));
      expect(line.indexOf('setState()'), lessThan(line.indexOf('app frames:')),
          reason: 'the exception still leads the line');
    });

    test('no app frames means no empty heading', () {
      final line = describeFrameworkError(_details(
        'boom',
        stack: _trace([_frameworkFrame]),
      ));

      expect(line, isNot(contains('app frames:')),
          reason: 'a heading over nothing is noise in a log being read under '
              'pressure');
      expect(line, 'Flutter framework error: boom');
    });
  });
}
