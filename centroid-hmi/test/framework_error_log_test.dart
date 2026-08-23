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
}) =>
    FlutterErrorDetails(
      exception: exception,
      informationCollector: information.isEmpty ? null : () => information,
    );

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
}
