import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jbtm/src/m2400.dart';
import 'package:jbtm/src/test_tcp_server.dart';

// Field ID constants for stub factories (internal).
const String _kWeight = '100';
const String _kStatus = '101';
const String _kDevId = '102';
const String _kFirmware = '103';
const String _kUnit = '104';

/// Build a complete STX-framed M2400 record from a record type and field pairs.
///
/// Produces the real M2400 wire format:
/// `[STX, ...utf8("(REC_TYPE\tFLD_ID\tVALUE\tFLD_ID\tVALUE..."), ETX]`
///
/// Uses [utf8.encode] (not [String.codeUnits]) for correctness with non-ASCII.
List<int> buildM2400Frame(int recordType, Map<String, String> fields) {
  final parts = <String>['($recordType'];
  for (final entry in fields.entries) {
    parts.add(entry.key);
    parts.add(entry.value);
  }
  final content = parts.join('\t');
  return [0x02, ...utf8.encode(content), 0x03];
}

/// A sent record entry tracking record type and fields for history.
class SentRecord {
  final int recordType;
  final Map<String, String> fields;

  const SentRecord({required this.recordType, required this.fields});
}

/// Create weight record fields with sensible defaults.
Map<String, String> makeWeightFields({
  String weight = '12.500',
  String unit = 'kg',
  String status = '1',
  String? devId,
}) {
  return {
    _kWeight: weight,
    _kUnit: unit,
    _kStatus: status,
    if (devId != null) _kDevId: devId,
  };
}

/// Create intro record fields with sensible defaults.
Map<String, String> makeIntroFields({
  String devId = '1',
  String firmware = 'V1.0',
}) {
  return {
    _kDevId: devId,
    _kFirmware: firmware,
  };
}

/// Create stat record fields with sensible defaults.
Map<String, String> makeStatFields({String status = '1'}) {
  return {
    _kStatus: status,
  };
}

/// Create LUA record fields with optional extra key-value pairs.
Map<String, String> makeLuaFields({Map<String, String> extra = const {}}) {
  return {
    ...extra,
  };
}

/// A protocol-aware M2400 stub server for TDD.
///
/// Wraps [TestTcpServer] and adds M2400-specific behavior:
/// - Auto-sends INTRO record to each new client on connect
/// - On-demand push of weight, stat, intro, LUA records
/// - Malformed data helpers for error-path testing
/// - Periodic push and burst mode for scheduling tests
/// - Sent record history tracking
class M2400StubServer {
  TestTcpServer? _server;

  /// History of all sent records, including auto-INTRO.
  final List<SentRecord> sentRecords = [];

  Timer? _periodicTimer;

  /// Start the stub server. Returns the OS-assigned port number.
  Future<int> start() async {
    _server = TestTcpServer(onConnect: _onClientConnect);
    return _server!.start();
  }

  /// The port the server is listening on.
  int get port => _server!.port;

  /// Number of currently connected clients.
  int get clientCount => _server!.clientCount;

  /// Called by TestTcpServer when a new client connects.
  /// Sends INTRO record directly to the connecting socket (not broadcast).
  void _onClientConnect(Socket client) {
    final fields = makeIntroFields();
    _sendToSocket(client, M2400RecordType.recIntro.id, fields);
  }

  /// Push a weight record to all connected clients.
  void pushWeightRecord({
    String weight = '12.500',
    String unit = 'kg',
    String status = '1',
    String? devId,
  }) {
    _send(M2400RecordType.recBatch.id,
        makeWeightFields(weight: weight, unit: unit, status: status, devId: devId));
  }

  /// Push a stat record to all connected clients.
  void pushStatRecord({String status = '1'}) {
    _send(M2400RecordType.recStat.id, makeStatFields(status: status));
  }

  /// Push an intro record to all connected clients.
  void pushIntroRecord({String devId = '1', String firmware = 'V1.0'}) {
    _send(M2400RecordType.recIntro.id,
        makeIntroFields(devId: devId, firmware: firmware));
  }

  /// Push a LUA record to all connected clients.
  void pushLuaRecord({Map<String, String> extra = const {}}) {
    _send(M2400RecordType.recLua.id, makeLuaFields(extra: extra));
  }

  /// Push an arbitrary record to all connected clients.
  void pushRecord(int recordType, Map<String, String> fields) {
    _send(recordType, fields);
  }

  /// Send raw bytes directly to all clients without M2400 framing.
  void sendRawGarbage(List<int> bytes) {
    _server!.sendToAll(bytes);
  }

  /// Send a valid STX/ETX frame with garbled (non-tab-separated) content.
  void sendMalformedRecord() {
    final garbled = utf8.encode('this_is_garbled_not_tab_separated');
    _server!.sendToAll([0x02, ...garbled, 0x03]);
  }

  /// Send a valid frame with an unrecognized record type ID.
  void sendUnknownRecordType({int typeId = 999}) {
    _server!.sendToAll(buildM2400Frame(typeId, {'data': 'test'}));
  }

  /// Send a valid frame with fields but no proper record type prefix.
  ///
  /// Produces a frame whose content lacks the `(` prefix, so the parser
  /// will not find a valid record type.
  void sendRecordWithoutType() {
    // Build raw frame content without the ( prefix — just key-value pairs
    final content = 'someKey\tsomeVal\tanotherKey\tanotherVal';
    _server!.sendToAll([0x02, ...utf8.encode(content), 0x03]);
  }

  /// Start pushing records at a fixed interval.
  void startPeriodicPush(
      Duration interval, ({int recordType, Map<String, String> fields}) Function() recordBuilder) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      final rec = recordBuilder();
      _send(rec.recordType, rec.fields);
    });
  }

  /// Stop periodic push timer.
  void stopPeriodicPush() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Send [count] records as fast as possible.
  ///
  /// Default builder creates weight records with incrementing weights.
  void pushBurst(int count,
      {({int recordType, Map<String, String> fields}) Function(int index)? recordBuilder}) {
    final builder = recordBuilder ??
        (i) => (recordType: M2400RecordType.recBatch.id, fields: makeWeightFields(weight: '${i + 1}.000'));
    for (var i = 0; i < count; i++) {
      final rec = builder(i);
      _send(rec.recordType, rec.fields);
    }
  }

  /// Clear the sent record history.
  void clearHistory() => sentRecords.clear();

  /// Wait for the next client connection.
  Future<void> waitForClient() => _server!.waitForClient();

  /// Disconnect all clients.
  void disconnectAll() => _server!.disconnectAll();

  /// Shut down the stub server. Cancels periodic timers and closes the server.
  ///
  /// Safe to call even if [start] was never called.
  Future<void> shutdown() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    await _server?.shutdown();
  }

  /// Send a record to all connected clients and record in history.
  void _send(int recordType, Map<String, String> fields) {
    sentRecords.add(SentRecord(recordType: recordType, fields: fields));
    _server!.sendToAll(buildM2400Frame(recordType, fields));
  }

  /// Send a record to a specific socket and record in history.
  void _sendToSocket(Socket client, int recordType, Map<String, String> fields) {
    sentRecords.add(SentRecord(recordType: recordType, fields: fields));
    try {
      client.add(buildM2400Frame(recordType, fields));
    } catch (_) {
      // Client may already be destroyed
    }
  }
}
