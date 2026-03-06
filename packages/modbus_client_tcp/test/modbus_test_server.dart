import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A mock Modbus TCP server for unit testing.
///
/// Binds to loopback on an OS-assigned port. Tracks connected clients,
/// allows sending raw bytes to all or specific clients, and supports
/// programmatic disconnect to simulate device failures.
///
/// Modelled on TestTcpServer from jbtm but specialized for Modbus TCP
/// with MBAP frame construction helpers.
class ModbusTestServer {
  /// Optional callback invoked when a new client connects.
  final void Function(Socket client)? onConnect;

  /// Optional callback invoked when data is received from a client.
  /// Allows tests to inspect incoming requests and craft responses.
  final void Function(Socket client, Uint8List data)? onData;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  Completer<void>? _clientCompleter;

  ModbusTestServer({this.onConnect, this.onData});

  /// Starts the server. Returns the OS-assigned port number.
  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      _clients.add(socket);
      // Catch errors on the done future to prevent unhandled async errors
      // when the client destroys the connection (RST).
      socket.done.catchError((_) {}).whenComplete(() {
        _clients.remove(socket);
      });
      socket.listen(
        (data) => onData?.call(socket, Uint8List.fromList(data)),
        onError: (_) {},
      );
      onConnect?.call(socket);
      _clientCompleter?.complete();
      _clientCompleter = null;
    });
    return _server!.port;
  }

  /// The port the server is listening on.
  int get port => _server!.port;

  /// Number of currently connected clients.
  int get clientCount => _clients.length;

  /// Send raw bytes to all connected clients.
  void sendToAll(List<int> data) {
    for (final client in List.of(_clients)) {
      try {
        client.add(data);
      } catch (_) {
        // Client may already be destroyed
      }
    }
  }

  /// Send raw bytes to a specific client socket.
  void sendToClient(Socket client, List<int> data) {
    try {
      client.add(data);
    } catch (_) {
      // Client may already be destroyed
    }
  }

  /// Wait for the next client connection.
  ///
  /// Completes immediately if a client is already connected, or waits
  /// until one does.
  Future<void> waitForClient() {
    if (_clients.isNotEmpty) return Future.value();
    _clientCompleter ??= Completer<void>();
    return _clientCompleter!.future;
  }

  /// Disconnect all clients (simulates device failure).
  void disconnectAll() {
    for (final client in List.of(_clients)) {
      client.destroy();
    }
    _clients.clear();
  }

  /// Fully shut down the server. Safe to call even if [start] was never called.
  Future<void> shutdown() async {
    disconnectAll();
    await _server?.close();
  }

  /// Build a complete MBAP response frame from components.
  ///
  /// The MBAP header is 7 bytes:
  /// - Bytes 0-1: Transaction ID (2 bytes)
  /// - Bytes 2-3: Protocol ID (2 bytes, always 0x0000)
  /// - Bytes 4-5: Length field (unit ID byte + PDU length)
  /// - Byte 6: Unit ID
  ///
  /// [transactionId] - the transaction ID to echo back (from request)
  /// [unitId] - the unit ID (typically 1)
  /// [pdu] - the Protocol Data Unit (function code + data)
  static Uint8List buildResponse(int transactionId, int unitId, Uint8List pdu) {
    final length = pdu.length + 1; // PDU + unit ID byte
    final frame = Uint8List(7 + pdu.length);
    ByteData.view(frame.buffer)
      ..setUint16(0, transactionId) // Transaction ID
      ..setUint16(2, 0) // Protocol ID = 0
      ..setUint16(4, length) // Length (unit ID + PDU)
      ..setUint8(6, unitId); // Unit ID
    frame.setAll(7, pdu);
    return frame;
  }

  /// Build a raw MBAP frame with an explicit length field value.
  ///
  /// Unlike [buildResponse], this allows setting an arbitrary length field
  /// for testing validation of malformed responses.
  ///
  /// [transactionId] - the transaction ID
  /// [lengthField] - the raw value for the MBAP length field (bytes 4-5)
  /// [unitId] - the unit ID
  /// [pdu] - the Protocol Data Unit (can be empty for malformed frames)
  static Uint8List buildRawFrame(
      int transactionId, int lengthField, int unitId, Uint8List pdu) {
    final frame = Uint8List(7 + pdu.length);
    ByteData.view(frame.buffer)
      ..setUint16(0, transactionId) // Transaction ID
      ..setUint16(2, 0) // Protocol ID = 0
      ..setUint16(4, lengthField) // Raw length field
      ..setUint8(6, unitId); // Unit ID
    frame.setAll(7, pdu);
    return frame;
  }
}
