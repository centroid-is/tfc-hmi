/// Adversarial tests for [ModbusClientWrapper]: connection-loop lifetime and
/// the half-open ("TCP accepted, nothing ever answers") failure mode.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus;

/// Counts live clients: created by the factory, retired by disconnect().
class CountingClient extends ModbusClientTcp {
  CountingClient(this.registry)
      : super('mock',
            serverPort: 0, connectionMode: ModbusConnectionMode.doNotConnect) {
    registry.created.add(this);
  }

  final ClientRegistry registry;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    registry.disconnected.add(this);
  }

  @override
  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (!_connected) return ModbusResponseCode.connectionFailed;
    if (request is ModbusReadRequest) {
      request.element.setValueFromBytes(Uint8List(request.element.byteCount));
    }
    return ModbusResponseCode.requestSucceed;
  }
}

class ClientRegistry {
  final created = <CountingClient>[];
  final disconnected = <CountingClient>[];

  /// Clients that were created and are still holding their socket.
  Iterable<CountingClient> get live =>
      created.where((c) => !disconnected.contains(c));
}

/// A TCP server that accepts the connection and then never sends a single
/// byte back. The classic silent-firewall / wedged-gateway case.
class BlackHoleServer {
  ServerSocket? _server;
  final _sockets = <Socket>[];

  int get port => _server!.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((s) {
      _sockets.add(s);
      s.listen((_) {}, onError: (_) {}); // read and drop; never reply
    });
  }

  Future<void> stop() async {
    for (final s in _sockets) {
      s.destroy();
    }
    _sockets.clear();
    await _server?.close();
    _server = null;
  }
}

void main() {
  group('connection loop lifetime', () {
    test('connect() twice must not start a second connection loop', () async {
      final registry = ClientRegistry();
      final wrapper = ModbusClientWrapper('h', 502, 1,
          clientFactory: (h, p, u) => CountingClient(registry));
      addTearDown(wrapper.dispose);

      // Two connect() calls: the reconnect button pressed twice, or a widget
      // rebuild re-running its connect side effect.
      wrapper.connect();
      wrapper.connect();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(registry.live, hasLength(1),
          reason: 'connect() is fire-and-forget with no "loop already '
              'running" guard, so the second call spawns a second '
              '_connectionLoop. Both loops assign _client; the loser\'s '
              'socket is never disconnected and both keep polling forever.');
    });

    test('disconnect() then connect() must leave exactly one live client',
        () async {
      final registry = ClientRegistry();
      final wrapper = ModbusClientWrapper('h', 502, 1,
          clientFactory: (h, p, u) => CountingClient(registry));
      addTearDown(wrapper.dispose);

      wrapper.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // A server-config save does exactly this pair.
      wrapper.disconnect();
      wrapper.connect();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(registry.live, hasLength(1),
          reason: '_stopped is only observed at the loop\'s await points. '
              'Setting it back to false before the old loop notices leaves '
              'two loops running against the same wrapper — one socket per '
              'reconnect leaks for the life of the process.');
    });

    test('dispose() must stop the connection loop creating new clients',
        () async {
      final registry = ClientRegistry();
      final wrapper = ModbusClientWrapper('h', 502, 1,
          clientFactory: (h, p, u) => CountingClient(registry));

      wrapper.connect();
      wrapper.disconnect();
      wrapper.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      wrapper.dispose();

      final atDispose = registry.created.length;
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(registry.created.length, atDispose,
          reason: 'A duplicated connection loop keeps reconnecting after '
              'dispose() if it is inside a backoff delay when _stopped flips '
              '— it re-reads _client, not the disposed flag, on the way '
              'round.');
    });
  });

  group('half-open connection', () {
    late BlackHoleServer server;

    setUp(() async {
      server = BlackHoleServer();
      await server.start();
    });

    tearDown(() => server.stop());

    test(
        'a server that accepts TCP and never answers must not read as '
        'Connected forever', () async {
      final wrapper = ModbusClientWrapper('127.0.0.1', server.port, 1);
      addTearDown(wrapper.dispose);

      final seen = <ConnectionStatus>[];
      final statusSub = wrapper.connectionStream.listen(seen.add);
      addTearDown(statusSub.cancel);

      wrapper.addPollGroup('fast', const Duration(milliseconds: 200),
          responseTimeout: const Duration(milliseconds: 300));
      wrapper.subscribe(const ModbusRegisterSpec(
        key: 'r0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        pollGroup: 'fast',
      ));
      wrapper.connect();

      // Give it long enough for ~15 consecutive poll timeouts.
      await Future<void>.delayed(const Duration(seconds: 6));

      expect(
          seen.skip(1).where((s) => s == ConnectionStatus.disconnected),
          isNotEmpty,
          reason: 'Every poll in the last 6s timed out (lastError: '
              '"${wrapper.lastError}"), yet the wrapper never once left the '
              'Connected state: _awaitDisconnect polls only the socket\'s '
              'isConnected flag, so a peer that accepts TCP and answers '
              'nothing keeps a green Connected chip over stale values, '
              'forever, with no reconnect ever attempted. Status seen: '
              '${seen.map((s) => s.name).toList()}');
    });
  });

}
