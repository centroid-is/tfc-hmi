import 'dart:convert';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

void main() {
  Map<String, Object?> roundTrip(WriteResult r) =>
      jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>;

  group('WriteResult', () {
    test('applied round-trips with readback and timestamp', () {
      final r = WriteResult.fromJson(roundTrip(const WriteApplied(
        '01J8XW3K9P',
        readback: 1500,
        at: 1786000000456,
      )));
      final applied = r as WriteApplied;
      expect(applied.cmd, '01J8XW3K9P');
      expect(applied.readback, 1500);
      expect(applied.at, 1786000000456);
    });

    test('rejected carries the device reason — it is a result, not an error',
        () {
      final r = WriteResult.fromJson(roundTrip(const WriteRejected(
        'cmd1',
        WriteReason('interlocked',
            message: 'guard door open', status: 'Bad_NotWritable'),
      )));
      final rejected = r as WriteRejected;
      expect(rejected.reason.kind, 'interlocked');
      expect(rejected.reason.status, 'Bad_NotWritable');
    });

    test('unknown round-trips', () {
      final r = WriteResult.fromJson(roundTrip(const WriteUnknown(
        'cmd2',
        WriteReason('plc_timeout', message: 'no response from ST101'),
      )));
      expect((r as WriteUnknown).reason.kind, 'plc_timeout');
    });

    test('not_received round-trips', () {
      final r = WriteResult.fromJson(roundTrip(const WriteNotReceived('cmd3')));
      expect(r, isA<WriteNotReceived>());
    });

    test('an unrecognized outcome degrades to unknown, never throws', () {
      // Forward compatibility on the safety path: a newer server's outcome
      // this client doesn't know is not proof of application.
      final r = WriteResult.fromJson({
        'cmd': 'cmd4',
        'outcome': 'partially_applied',
      });
      final unknown = r as WriteUnknown;
      expect(unknown.reason.kind, contains('partially_applied'));
    });

    test('the sealed switch is exhaustive — every state must be handled', () {
      // This test exists so removing/adding a state breaks compilation
      // here first, in a file whose comments explain the safety rules.
      String describe(WriteResult r) => switch (r) {
            WriteApplied() => 'applied',
            WriteRejected() => 'rejected',
            WriteUnknown() => 'unknown — verify, never auto-retry',
            WriteNotReceived() => 'not received — operator may re-send',
          };
      expect(describe(const WriteNotReceived('x')), contains('re-send'));
      expect(describe(const WriteUnknown('x', WriteReason('link_lost'))),
          contains('never auto-retry'));
    });
  });
}
