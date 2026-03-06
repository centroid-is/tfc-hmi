import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:synchronized/synchronized.dart';

/// The Modbus TCP client class.
class ModbusClientTcp extends ModbusClient {
  final String serverAddress;
  final int serverPort;
  final Duration connectionTimeout;
  final Duration? delayAfterConnect;

  /// Interval for TCP keep-alive probes. Set to [Duration.zero] to disable.
  final Duration keepAliveInterval;

  /// Number of unacknowledged keep-alive probes before the connection is
  /// considered dead.
  final int keepAliveCount;

  @override
  bool get isConnected => _socket != null;

  int _lastTransactionId = 0;

  int _getNextTransactionId() {
    // UInt16 rollover handling
    _lastTransactionId++;
    if (_lastTransactionId > 65535) {
      _lastTransactionId = 0;
    }
    return _lastTransactionId;
  }

  Socket? _socket;
  final Lock _lock = Lock();
  _TcpResponse? _currentResponse;

  ModbusClientTcp(this.serverAddress,
      {this.serverPort = 502,
      super.connectionMode = ModbusConnectionMode.autoConnectAndKeepConnected,
      this.connectionTimeout = const Duration(seconds: 3),
      super.responseTimeout = const Duration(seconds: 3),
      this.delayAfterConnect,
      this.keepAliveInterval = const Duration(seconds: 10),
      this.keepAliveCount = 3,
      super.unitId});

  /// This is an easy server address discovery.
  ///
  /// The discovery starts from the fourth digit of the [startIpAddress] and
  /// only checks address of fourth digit.
  /// Example:
  /// ```dart
  /// // This checks addresses from '192.168.0.10' to '192.168.0.255'
  /// var serverAddress = await ModbusClientTcp.discover("192.168.0.10");
  /// ```
  static Future<String?> discover(String startIpAddress,
      {int serverPort = 502,
      Duration connectionTimeout = const Duration(milliseconds: 10)}) async {
    var serverAddress = InternetAddress.tryParse(startIpAddress);
    if (serverAddress == null) {
      throw ModbusException(
          context: "ModbusClientTcp.discover",
          msg: "[$startIpAddress] Invalid address!");
    }
    for (var i = serverAddress.rawAddress[3]; i < 256; i++) {
      var ip = serverAddress!.rawAddress;
      ip[3] = i;
      serverAddress = InternetAddress.fromRawAddress(ip);
      try {
        var socket = await Socket.connect(serverAddress, serverPort,
            timeout: connectionTimeout);
        socket.destroy();
        ModbusAppLogger.finest(
            "[${serverAddress.address}] Modbus server found!");
        return serverAddress.address;
      } catch (_) {}
    }
    ModbusAppLogger.finest("[$startIpAddress] Modbus server not found!");
    return null;
  }

  @override
  Future<ModbusResponseCode> send(ModbusRequest request) async {
    var res = await _lock.synchronized(() async {
      // Connect if needed
      try {
        if (connectionMode != ModbusConnectionMode.doNotConnect) {
          await connect();
        }
        if (!isConnected) {
          return ModbusResponseCode.connectionFailed;
        }
      } catch (ex) {
        ModbusAppLogger.severe(
            "Unexpected exception in sending TCP message", ex);
        return ModbusResponseCode.connectionFailed;
      }

      // Flushes any old pending data
      await _socket!.flush();

      // Create the new response handler
      var transactionId = _getNextTransactionId();
      _currentResponse = _TcpResponse(request,
          transactionId: transactionId, timeout: getResponseTimeout(request));

      // Reset this request in case it was already used before
      request.reset();

      // Create request data
      int pduLen = request.protocolDataUnit.length;
      var header = Uint8List(pduLen + 7);
      ByteData.view(header.buffer)
        ..setUint16(0, transactionId) // Transaction ID
        ..setUint16(2, 0) // Protocol ID = 0
        ..setUint16(4, pduLen + 1) // PDU Length + Unit ID byte
        ..setUint8(6, getUnitId(request)); // Unit ID
      header.setAll(7, request.protocolDataUnit);

      // Send the request data
      _socket!.add(header);
      ModbusAppLogger.finest("Sent data: ${ModbusAppLogger.toHex(header)}");

      // Wait for the response code
      return await request.responseCode;
    });
    // Need to disconnect?
    if (connectionMode == ModbusConnectionMode.autoConnectAndDisconnect) {
      await disconnect();
    }
    return res;
  }

  /// Connect the socket if not already done or disconnected
  @override
  Future<bool> connect() async {
    if (isConnected) {
      return true;
    }
    ModbusAppLogger.fine("Connecting TCP socket...");
    // New connection
    try {
      _socket = await Socket.connect(serverAddress, serverPort,
          timeout: connectionTimeout);
      _enableKeepAlive(_socket!);
      // listen to the received data event stream
      _socket!.listen((Uint8List data) {
        _onSocketData(data);
      },
          onError: (error) => _onSocketError(error),
          onDone: () => disconnect(),
          cancelOnError: true);
    } catch (ex) {
      ModbusAppLogger.warning(
          "Connection to $serverAddress:$serverPort failed!", ex);
      _socket = null;
      return false;
    }
    // Is a delay requested?
    if (delayAfterConnect != null) {
      await Future.delayed(delayAfterConnect!);
    }
    ModbusAppLogger.fine("TCP socket connected");
    return true;
  }

  /// Handle received data from the socket
  void _onSocketData(Uint8List data) {
    // Could receive buffered data before setting up the response object
    // (https://github.com/cabbi/modbus_client_tcp/issues/6)
    _currentResponse?.addResponseData(data);
  }

  /// Handle an error from the socket
  void _onSocketError(dynamic error) {
    ModbusAppLogger.severe("Unexpected error from TCP socket", error);
    disconnect();
  }

  /// Enable TCP keep-alive on the socket with platform-specific options.
  void _enableKeepAlive(Socket socket) {
    if (keepAliveInterval == Duration.zero) return;

    final intervalSeconds = keepAliveInterval.inSeconds;
    final count = keepAliveCount;

    // SO_KEEPALIVE: Linux/Android=0x0009, macOS/iOS/Windows=0x0008
    final soKeepAlive =
        Platform.isLinux || Platform.isAndroid ? 0x0009 : 0x0008;
    socket.setRawOption(
      RawSocketOption.fromBool(RawSocketOption.levelSocket, soKeepAlive, true),
    );

    if (Platform.isWindows) {
      // Windows 10 1709+ supports TCP_KEEPIDLE(3), TCP_KEEPCNT(16),
      // TCP_KEEPINTVL(17). Older versions only support SO_KEEPALIVE.
      try {
        socket.setRawOption(
          RawSocketOption.fromInt(
              RawSocketOption.levelTcp, 3, intervalSeconds),
        );
        socket.setRawOption(
          RawSocketOption.fromInt(
              RawSocketOption.levelTcp, 17, intervalSeconds),
        );
        socket.setRawOption(
          RawSocketOption.fromInt(RawSocketOption.levelTcp, 16, count),
        );
      } on SocketException {
        // Older Windows versions don't support fine-grained keepalive
        // options. SO_KEEPALIVE is still enabled with OS defaults.
      }
    } else {
      final isMac = Platform.isMacOS || Platform.isIOS;

      // TCP_KEEPIDLE (Linux=4) / TCP_KEEPALIVE (macOS=0x10)
      // Reuse the interval as the initial idle time.
      socket.setRawOption(
        RawSocketOption.fromInt(
          RawSocketOption.levelTcp,
          isMac ? 0x10 : 4,
          intervalSeconds,
        ),
      );

      // TCP_KEEPINTVL: Linux=5, macOS=0x101
      socket.setRawOption(
        RawSocketOption.fromInt(
          RawSocketOption.levelTcp,
          isMac ? 0x101 : 5,
          intervalSeconds,
        ),
      );

      // TCP_KEEPCNT: Linux=6, macOS=0x102
      socket.setRawOption(
        RawSocketOption.fromInt(
          RawSocketOption.levelTcp,
          isMac ? 0x102 : 6,
          count,
        ),
      );
    }
  }

  /// Handle socket being closed
  @override
  Future<void> disconnect() async {
    ModbusAppLogger.fine("Disconnecting TCP socket...");
    if (_socket != null) {
      _socket!.destroy();
      _socket = null;
    }
  }
}

class _TcpResponse {
  final ModbusRequest request;
  final int transactionId;
  final Duration timeout;

  final Completer _timeout = Completer();
  List<int> _data = Uint8List(0);
  int? _resDataLen;

  _TcpResponse(this.request,
      {required this.timeout, required this.transactionId}) {
    _timeout.future.timeout(timeout, onTimeout: () {
      request.setResponseCode(ModbusResponseCode.requestTimeout);
    });
  }

  void addResponseData(Uint8List data) {
    // Timeout expired?
    if (_timeout.isCompleted) {
      // No more data needed, we've already set the response code
      return;
    }
    _data += data;
    ModbusAppLogger.finest("Incoming data: ${ModbusAppLogger.toHex(data)}");
    // Still need the TCP header?
    if (_resDataLen == null && _data.length >= 6) {
      var resView = ByteData.view(Uint8List.fromList(_data).buffer, 0, 6);
      if (transactionId != resView.getUint16(0)) {
        ModbusAppLogger.warning("Invalid TCP transaction id",
            "$transactionId != ${resView.getUint16(0)}");
        _timeout.complete();
        request.setResponseCode(ModbusResponseCode.requestRxFailed);
        return;
      }
      if (0 != resView.getUint16(2)) {
        ModbusAppLogger.warning(
            "Invalid TCP protocol id", "${resView.getUint16(2)} != 0");
        _timeout.complete();
        request.setResponseCode(ModbusResponseCode.requestRxFailed);
        return;
      }
      _resDataLen = resView.getUint16(4);
    }
    // Got all data
    if (_resDataLen != null && _data.length >= _resDataLen!) {
      _timeout.complete();
      request.setFromPduResponse(Uint8List.fromList(_data.sublist(7)));
    }
  }
}
