import 'dart:async';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:test/test.dart';

void main() {
  late M2400StubServer stub;

  setUp(() {
    stub = M2400StubServer();
  });

  tearDown(() async {
    await stub.shutdown();
  });

  // ---------------------------------------------------------------------------
  // Binding
  // ---------------------------------------------------------------------------
  group('binding', () {
    test('start() returns valid port', () async {
      final port = await stub.start();
      expect(port, greaterThan(0));
    });

    test('clientCount tracks connections', () async {
      final port = await stub.start();
      expect(stub.clientCount, equals(0));

      final socket = MSocket('localhost', port);
      socket.connect();
      await stub.waitForClient();
      // Small delay for client registration
      await Future.delayed(const Duration(milliseconds: 50));

      expect(stub.clientCount, greaterThanOrEqualTo(1));

      socket.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Auto-INTRO
  // ---------------------------------------------------------------------------
  group('auto-INTRO', () {
    test('client receives recIntro on connect', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final gotIntro = Completer<M2400Record>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((record) {
        if (!gotIntro.isCompleted) gotIntro.complete(record);
      });

      socket.connect();
      final record =
          await gotIntro.future.timeout(const Duration(seconds: 5));

      expect(record.type, equals(M2400RecordType.recIntro));

      socket.dispose();
    });

    test('second client also receives INTRO', () async {
      final port = await stub.start();

      // First client
      final socket1 = MSocket('localhost', port);
      final got1 = Completer<M2400Record>();
      socket1.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (!got1.isCompleted) got1.complete(r);
      });
      socket1.connect();
      await got1.future.timeout(const Duration(seconds: 5));

      // Second client
      final socket2 = MSocket('localhost', port);
      final got2 = Completer<M2400Record>();
      socket2.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (!got2.isCompleted) got2.complete(r);
      });
      socket2.connect();
      final record2 =
          await got2.future.timeout(const Duration(seconds: 5));

      expect(record2.type, equals(M2400RecordType.recIntro));

      socket1.dispose();
      socket2.dispose();
    });

    test('first client does NOT receive duplicate INTRO when second connects',
        () async {
      final port = await stub.start();

      // First client -- collect all records
      final socket1 = MSocket('localhost', port);
      final records1 = <M2400Record>[];
      socket1.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen(records1.add);
      socket1.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // Second client connects
      final socket2 = MSocket('localhost', port);
      final got2 = Completer<void>();
      socket2.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (!got2.isCompleted) got2.complete();
      });
      socket2.connect();
      await got2.future.timeout(const Duration(seconds: 5));

      // Give time for any stray data
      await Future.delayed(const Duration(milliseconds: 200));

      // First client should have received exactly 1 INTRO
      final introCount =
          records1.where((r) => r.type == M2400RecordType.recIntro).length;
      expect(introCount, equals(1),
          reason: 'First client should NOT get duplicate INTRO');

      socket1.dispose();
      socket2.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // On-demand push
  // ---------------------------------------------------------------------------
  group('on-demand push', () {
    test('pushWeightRecord sends valid weight record', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final records = <M2400Record>[];
      final gotWeight = Completer<void>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        records.add(r);
        // Skip the auto-INTRO, wait for weight
        if (r.type == M2400RecordType.recBatch && !gotWeight.isCompleted) {
          gotWeight.complete();
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushWeightRecord(weight: '55.0', unit: 'lb', status: '2');
      await gotWeight.future.timeout(const Duration(seconds: 5));

      final wgt = records.lastWhere((r) => r.type == M2400RecordType.recBatch);
      expect(wgt.type, equals(M2400RecordType.recBatch));
      // Weight fields should contain weight/unit/status
      expect(wgt.fields.values, contains('55.0'));
      expect(wgt.fields.values, contains('lb'));
      expect(wgt.fields.values, contains('2'));

      socket.dispose();
    });

    test('pushStatRecord sends valid stat record', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final gotStat = Completer<M2400Record>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (r.type == M2400RecordType.recStat && !gotStat.isCompleted) {
          gotStat.complete(r);
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushStatRecord(status: '3');
      final stat =
          await gotStat.future.timeout(const Duration(seconds: 5));

      expect(stat.type, equals(M2400RecordType.recStat));

      socket.dispose();
    });

    test('pushIntroRecord sends valid intro record', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final intros = <M2400Record>[];
      final gotTwo = Completer<void>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (r.type == M2400RecordType.recIntro) {
          intros.add(r);
          // First is auto, second is manual push
          if (intros.length == 2 && !gotTwo.isCompleted) {
            gotTwo.complete();
          }
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushIntroRecord(devId: '42', firmware: 'V2.0');
      await gotTwo.future.timeout(const Duration(seconds: 5));

      // Second intro is the manually pushed one
      expect(intros[1].type, equals(M2400RecordType.recIntro));

      socket.dispose();
    });

    test('pushLuaRecord sends valid LUA record', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final gotLua = Completer<M2400Record>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (r.type == M2400RecordType.recLua && !gotLua.isCompleted) {
          gotLua.complete(r);
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushLuaRecord(extra: {'myKey': 'myVal'});
      final lua =
          await gotLua.future.timeout(const Duration(seconds: 5));

      expect(lua.type, equals(M2400RecordType.recLua));
      expect(lua.fields['myKey'], equals('myVal'));

      socket.dispose();
    });

    test('pushRecord sends arbitrary record from recordType + fields', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final gotCustom = Completer<M2400Record>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (r.type == M2400RecordType.recBatch && !gotCustom.isCompleted) {
          gotCustom.complete(r);
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushRecord(M2400RecordType.recBatch.id, {
        'custom': 'data',
      });
      final rec =
          await gotCustom.future.timeout(const Duration(seconds: 5));

      expect(rec.fields['custom'], equals('data'));

      socket.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Record history
  // ---------------------------------------------------------------------------
  group('record history', () {
    test('sentRecords tracks all sent records including auto-INTRO', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushWeightRecord();
      stub.pushStatRecord();

      // Auto-INTRO + weight + stat = 3
      expect(stub.sentRecords.length, equals(3));

      // First should be INTRO
      expect(stub.sentRecords[0].recordType,
          equals(M2400RecordType.recIntro.id));

      socket.dispose();
    });

    test('clearHistory clears sentRecords', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(stub.sentRecords, isNotEmpty); // auto-INTRO
      stub.clearHistory();
      expect(stub.sentRecords, isEmpty);

      socket.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // buildM2400Frame round-trip
  // ---------------------------------------------------------------------------
  group('buildM2400Frame', () {
    test('produces bytes parseable by M2400FrameParser + parseM2400Frame',
        () async {
      final frameBytes = buildM2400Frame(M2400RecordType.recBatch.id, {
        '100': 'test_weight',
      });

      // Feed through the parser pipeline
      final controller = StreamController<Uint8List>();
      final frames = <Uint8List>[];
      final sub = controller.stream
          .transform(M2400FrameParser())
          .listen(frames.add);

      controller.add(Uint8List.fromList(frameBytes));
      await controller.close();
      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(frames, hasLength(1));
      final record = parseM2400Frame(frames[0]);
      expect(record, isNotNull);
      expect(record!.type, equals(M2400RecordType.recBatch));
      expect(record.fields['100'], equals('test_weight'));
    });
  });

  // ---------------------------------------------------------------------------
  // Malformed data helpers
  // ---------------------------------------------------------------------------
  group('malformed data', () {
    test('sendRawGarbage sends raw bytes without framing', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final allData = <Uint8List>[];
      final gotTwo = Completer<void>();

      // Listen on raw data stream (not parsed) -- first chunk is auto-INTRO
      socket.dataStream.listen((data) {
        allData.add(data);
        if (allData.length >= 2 && !gotTwo.isCompleted) {
          gotTwo.complete();
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.sendRawGarbage([0xFF, 0xFE, 0xFD]);
      await gotTwo.future.timeout(const Duration(seconds: 5));

      // Second chunk should be the raw garbage bytes
      expect(allData[1], equals([0xFF, 0xFE, 0xFD]));

      socket.dispose();
    });

    test('sendMalformedRecord sends valid frame with garbled content',
        () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final frames = <Uint8List>[];
      final gotTwo = Completer<void>();

      socket.dataStream.transform(M2400FrameParser()).listen((frame) {
        frames.add(frame);
        // First frame is auto-INTRO, second is malformed
        if (frames.length == 2 && !gotTwo.isCompleted) {
          gotTwo.complete();
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.sendMalformedRecord();
      await gotTwo.future.timeout(const Duration(seconds: 5));

      // The malformed frame should parse without crashing
      final record = parseM2400Frame(frames[1]);
      // It should return a record (possibly with unknown type or weird fields)
      // but NOT crash
      expect(record, isNotNull);

      socket.dispose();
    });

    test('sendUnknownRecordType sends frame with unrecognized record type',
        () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final gotUnknown = Completer<M2400Record>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (r.type == M2400RecordType.unknown &&
            !gotUnknown.isCompleted) {
          gotUnknown.complete(r);
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.sendUnknownRecordType(typeId: 777);
      final record =
          await gotUnknown.future.timeout(const Duration(seconds: 5));

      expect(record.type, equals(M2400RecordType.unknown));
      // The fields should still be present
      expect(record.fields['data'], equals('test'));

      socket.dispose();
    });

    test('sendRecordWithoutType sends frame missing ( prefix', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final records = <M2400Record>[];
      final gotTwo = Completer<void>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        records.add(r);
        if (records.length == 2 && !gotTwo.isCompleted) {
          gotTwo.complete();
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.sendRecordWithoutType();
      await gotTwo.future.timeout(const Duration(seconds: 5));

      // Second record (after auto-INTRO) should have unknown type
      // because "someKey" is not a valid numeric record type
      final noType = records[1];
      expect(noType.type, equals(M2400RecordType.unknown));

      socket.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Push scheduling
  // ---------------------------------------------------------------------------
  group('push scheduling', () {
    test('pushBurst sends multiple records rapidly, all received', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final records = <M2400Record>[];
      final gotAll = Completer<void>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        records.add(r);
        // 1 auto-INTRO + 5 burst records = 6
        if (records.length >= 6 && !gotAll.isCompleted) {
          gotAll.complete();
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.pushBurst(5);
      await gotAll.future.timeout(const Duration(seconds: 5));

      // Should have 1 INTRO + 5 weight records
      final weightRecords =
          records.where((r) => r.type == M2400RecordType.recBatch).toList();
      expect(weightRecords.length, equals(5));

      socket.dispose();
    });

    test('startPeriodicPush pushes records at interval', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);
      final records = <M2400Record>[];
      final gotThree = Completer<void>();

      socket.dataStream
          .transform(M2400FrameParser())
          .map(parseM2400Frame)
          .where((r) => r != null)
          .cast<M2400Record>()
          .listen((r) {
        if (r.type == M2400RecordType.recBatch) {
          records.add(r);
          if (records.length >= 3 && !gotThree.isCompleted) {
            gotThree.complete();
          }
        }
      });

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.startPeriodicPush(
          const Duration(milliseconds: 100),
          () => (recordType: M2400RecordType.recBatch.id, fields: makeWeightFields()));
      await gotThree.future.timeout(const Duration(seconds: 5));
      stub.stopPeriodicPush();

      expect(records.length, greaterThanOrEqualTo(3));

      socket.dispose();
    });

    test('stopPeriodicPush cancels periodic timer', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // Start and immediately stop
      stub.startPeriodicPush(
          const Duration(milliseconds: 50),
          () => (recordType: M2400RecordType.recBatch.id, fields: makeWeightFields()));
      stub.stopPeriodicPush();

      final countBefore = stub.sentRecords.length;
      await Future.delayed(const Duration(milliseconds: 300));
      final countAfter = stub.sentRecords.length;

      // No new records should have been sent after stop
      expect(countAfter, equals(countBefore));

      socket.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  group('lifecycle', () {
    test('shutdown cleans up server resources', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      await stub.shutdown();

      // Server should no longer accept connections -- this verifies cleanup.
      // We just verify it completes without error.
      socket.dispose();
    });

    test('no timers fire after shutdown', () async {
      final port = await stub.start();
      final socket = MSocket('localhost', port);

      socket.connect();
      await stub.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      stub.startPeriodicPush(
          const Duration(milliseconds: 50),
          () => (recordType: M2400RecordType.recBatch.id, fields: makeWeightFields()));
      await stub.shutdown();

      final countAfterShutdown = stub.sentRecords.length;
      await Future.delayed(const Duration(milliseconds: 300));

      expect(stub.sentRecords.length, equals(countAfterShutdown),
          reason: 'No records should be added after shutdown');

      socket.dispose();
    });
  });
}
