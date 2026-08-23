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

  /// Time before the first keep-alive probe is sent on an idle connection.
  /// Set to [Duration.zero] (along with [keepAliveInterval]) to disable.
  final Duration keepAliveIdle;

  /// Interval between keep-alive probes after the initial [keepAliveIdle].
  /// Set to [Duration.zero] (along with [keepAliveIdle]) to disable.
  final Duration keepAliveInterval;

  /// Number of unacknowledged keep-alive probes before the connection is
  /// considered dead.
  final int keepAliveCount;

  @override
  bool get isConnected => _socket != null;

  /// The local TCP port the client socket is bound to, or null when
  /// disconnected. Exposes the source port for per-connection diagnostics.
  int? get localPort => _socket?.port;

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

  /// TCPFIX-02: Map of pending responses keyed by transaction ID.
  /// Replaces the single `_currentResponse` to support concurrent requests.
  final Map<int, _TcpResponse> _pendingResponses = {};

  /// Buffer for incoming TCP data that may contain partial or concatenated
  /// MBAP frames. Parsed by [_processIncomingBuffer].
  final BytesBuilder _incomingBuffer = BytesBuilder(copy: false);

  ModbusClientTcp(this.serverAddress,
      {this.serverPort = 502,
      super.connectionMode = ModbusConnectionMode.autoConnectAndKeepConnected,
      this.connectionTimeout = const Duration(seconds: 3),
      super.responseTimeout = const Duration(seconds: 3),
      this.delayAfterConnect,
      this.keepAliveIdle = const Duration(seconds: 5),
      this.keepAliveInterval = const Duration(seconds: 2),
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
    // TCPFIX-02: Lock only protects connection and socket write.
    // Response wait happens OUTSIDE the lock to allow concurrent requests.
    int transactionId;
    transactionId = await _lock.synchronized(() async {
      // Connect if needed
      try {
        if (connectionMode != ModbusConnectionMode.doNotConnect) {
          await connect();
        }
        if (!isConnected) {
          return -1; // Signal connection failure
        }
      } catch (ex) {
        ModbusAppLogger.severe(
            "Unexpected exception in sending TCP message", ex);
        return -1;
      }

      // Flushes any old pending data
      await _socket!.flush();

      // Create the new response handler
      var tid = _getNextTransactionId();
      var response = _TcpResponse(request,
          transactionId: tid,
          timeout: getResponseTimeout(request),
          unitId: getUnitId(request));
      _pendingResponses[tid] = response;

      // Reset this request in case it was already used before
      request.reset();

      // Create request data
      int pduLen = request.protocolDataUnit.length;
      var header = Uint8List(pduLen + 7);
      ByteData.view(header.buffer)
        ..setUint16(0, tid) // Transaction ID
        ..setUint16(2, 0) // Protocol ID = 0
        ..setUint16(4, pduLen + 1) // PDU Length + Unit ID byte
        ..setUint8(6, getUnitId(request)); // Unit ID
      header.setAll(7, request.protocolDataUnit);

      // Send the request data
      _socket!.add(header);
      ModbusAppLogger.finest("Sent data: ${ModbusAppLogger.toHex(header)}");

      return tid;
    });

    // Connection failed?
    if (transactionId == -1) {
      return ModbusResponseCode.connectionFailed;
    }

    // Wait for response OUTSIDE the lock (enables concurrency)
    var res = await request.responseCode;
    _pendingResponses.remove(transactionId);

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
      _socket!.setOption(SocketOption.tcpNoDelay, true);
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

  /// Handle received data from the socket.
  ///
  /// TCPFIX-02: Routes incoming data by transaction ID from the MBAP header.
  /// Handles concatenated responses (multiple frames in one TCP segment) and
  /// partial responses (frame split across segments) via [_incomingBuffer].
  void _onSocketData(Uint8List data) {
    _incomingBuffer.add(data);
    _processIncomingBuffer();
  }

  /// Process buffered incoming data, extracting complete MBAP frames and
  /// routing each to its corresponding [_TcpResponse] by transaction ID.
  void _processIncomingBuffer() {
    while (_incomingBuffer.length >= 6) {
      // Take a snapshot of the buffer for header parsing
      final bufferBytes = _incomingBuffer.toBytes();

      // Read MBAP header fields
      var headerView = ByteData.view(bufferBytes.buffer, 0, 6);
      var transactionId = headerView.getUint16(0);
      var lengthField = headerView.getUint16(4);

      // TCPFIX-03: Validate MBAP length field range (defense-in-depth).
      // Standard Modbus limits MBAP length to 1-254, but UMAS (FC90/0x5A)
      // responses can be much larger (data dictionary 500-5000 bytes).
      final functionCode = bufferBytes.length > 7 ? bufferBytes[7] : 0;
      final maxLength = (functionCode == 0x5A) ? 65535 : 254;
      if (lengthField < 1 || lengthField > maxLength) {
        ModbusAppLogger.warning("Invalid MBAP length field in router",
            "$lengthField not in range 1-$maxLength, discarding buffer");
        // Signal failure to the pending response if one exists
        var pendingResponse = _pendingResponses[transactionId];
        if (pendingResponse != null) {
          pendingResponse.request.setResponseCode(
              ModbusResponseCode.requestRxFailed);
        }
        _incomingBuffer.clear();
        return;
      }

      // Total frame size = 6-byte header prefix + length field value
      var totalFrameSize = lengthField + 6;

      // Wait for more data if frame is incomplete
      if (bufferBytes.length < totalFrameSize) {
        break;
      }

      // Extract the complete frame
      var frameBytes =
          Uint8List.fromList(bufferBytes.sublist(0, totalFrameSize));

      // Rebuild the buffer from remaining bytes
      _incomingBuffer.clear();
      if (bufferBytes.length > totalFrameSize) {
        _incomingBuffer.add(bufferBytes.sublist(totalFrameSize));
      }

      // Route to the correct pending response
      var pendingResponse = _pendingResponses[transactionId];
      if (pendingResponse != null) {
        pendingResponse.addResponseData(frameBytes);
      } else {
        ModbusAppLogger.warning(
            "Response for unknown transaction ID $transactionId, discarding");
      }
    }
  }

  /// Handle an error from the socket
  void _onSocketError(dynamic error) {
    ModbusAppLogger.severe("Unexpected error from TCP socket", error);
    disconnect();
  }

  /// Enable TCP keep-alive on the socket with platform-specific options.
  ///
  /// Uses [keepAliveIdle] for the initial idle time before the first probe,
  /// [keepAliveInterval] for the interval between subsequent probes, and
  /// [keepAliveCount] for the number of unanswered probes before declaring
  /// the connection dead.
  ///
  /// Default values match MSocket: 5s idle, 2s interval, 3 probes (~11s).
  void _enableKeepAlive(Socket socket) {
    if (keepAliveIdle == Duration.zero &&
        keepAliveInterval == Duration.zero) {
      return;
    }

    // Best effort, every option, on every platform.
    //
    // This is tuning: it shortens how long a dead peer goes unnoticed. It is
    // never a reason to fail a connection, and it used to be exactly that.
    // The call sits inside connect()'s try, and the only guard here caught
    // `SocketException` on the Windows branch alone -- so a Windows build
    // where TCP_KEEPIDLE and friends are rejected with anything else, or a
    // Linux/macOS kernel that refuses one of its own constants, lost the
    // whole connection and logged "failed to connect". On a plant floor that
    // is a PLC that never comes up, for the sake of a keepalive timer.
    //
    // Each option is applied independently so one unsupported constant does
    // not skip the ones after it. SO_KEEPALIVE alone still gives OS-default
    // probing, which is the behaviour before any of this was tuned.
    for (final option in keepAliveOptions(
      isWindows: Platform.isWindows,
      isLinuxOrAndroid: Platform.isLinux || Platform.isAndroid,
      isMac: Platform.isMacOS || Platform.isIOS,
      idleSeconds: keepAliveIdle.inSeconds,
      intervalSeconds: keepAliveInterval.inSeconds,
      count: keepAliveCount,
    )) {
      try {
        socket.setRawOption(option);
      } catch (e) {
        // Older Windows (pre-10 1709) has no TCP_KEEPIDLE/CNT/INTVL, and the
        // failure is not reliably a SocketException.
        ModbusAppLogger.fine('keepalive option not applied: $e');
      }
    }
  }

  /// The socket options that implement this client's keepalive settings, in
  /// the order they should be applied.
  ///
  /// Pure and platform-injected so the constants can be tested off the
  /// platform they belong to -- the Windows numbers in particular, which are
  /// the ones no developer on macOS or Linux ever exercises. Public for that
  /// reason rather than because callers outside this class need it.
  ///
  /// SO_KEEPALIVE differs by platform (Linux/Android 0x0009, everything else
  /// 0x0008) and comes first: it is what actually turns keepalive on, and the
  /// rest only tune it.
  static List<RawSocketOption> keepAliveOptions({
    required bool isWindows,
    required bool isLinuxOrAndroid,
    required bool isMac,
    required int idleSeconds,
    required int intervalSeconds,
    required int count,
  }) {
    final soKeepAlive = isLinuxOrAndroid ? 0x0009 : 0x0008;
    return [
      RawSocketOption.fromBool(
          RawSocketOption.levelSocket, soKeepAlive, true),
      if (isWindows) ...[
        // Windows 10 1709+: TCP_KEEPIDLE(3), TCP_KEEPCNT(16),
        // TCP_KEEPINTVL(17). Older versions only support SO_KEEPALIVE.
        RawSocketOption.fromInt(RawSocketOption.levelTcp, 3, idleSeconds),
        RawSocketOption.fromInt(RawSocketOption.levelTcp, 17, intervalSeconds),
        RawSocketOption.fromInt(RawSocketOption.levelTcp, 16, count),
      ] else ...[
        // TCP_KEEPIDLE (Linux=4) / TCP_KEEPALIVE (macOS=0x10)
        RawSocketOption.fromInt(
            RawSocketOption.levelTcp, isMac ? 0x10 : 4, idleSeconds),
        // TCP_KEEPINTVL: Linux=5, macOS=0x101
        RawSocketOption.fromInt(
            RawSocketOption.levelTcp, isMac ? 0x101 : 5, intervalSeconds),
        // TCP_KEEPCNT: Linux=6, macOS=0x102
        RawSocketOption.fromInt(
            RawSocketOption.levelTcp, isMac ? 0x102 : 6, count),
      ],
    ];
  }

  /// Handle socket being closed
  @override
  Future<void> disconnect() async {
    ModbusAppLogger.fine("Disconnecting TCP socket...");
    if (_socket != null) {
      _socket!.destroy();
      _socket = null;
    }
    _pendingResponses.clear();
    _incomingBuffer.clear();
  }
}

class _TcpResponse {
  final ModbusRequest request;
  final int transactionId;
  final int unitId;
  final Duration timeout;

  final Completer _timeout = Completer();
  List<int> _data = Uint8List(0);
  int? _resDataLen;

  _TcpResponse(this.request,
      {required this.timeout,
      required this.transactionId,
      required this.unitId}) {
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
      // TCPFIX-03: Validate MBAP length field range.
      // Standard Modbus: 1-254 (1 unit ID + 253 max PDU).
      // UMAS FC90 (0x5A): up to 65535 for large data dictionary responses.
      final maxLen = (request.functionCode.code == 0x5A) ? 65535 : 254;
      if (_resDataLen! < 1 || _resDataLen! > maxLen) {
        ModbusAppLogger.warning(
            "Invalid MBAP length field", "$_resDataLen not in range 1-$maxLen");
        _timeout.complete();
        request.setResponseCode(ModbusResponseCode.requestRxFailed);
        return;
      }
      // BUG-03: Validate unit ID in MBAP response header (byte 6).
      // Must match the unit ID sent in the request.
      if (_data.length >= 7) {
        final responseUnitId = _data[6];
        if (responseUnitId != unitId) {
          ModbusAppLogger.warning("Response unit ID mismatch",
              "expected $unitId, got $responseUnitId");
          _timeout.complete();
          request.setResponseCode(ModbusResponseCode.requestRxFailed);
          return;
        }
      }
    }
    // Got all data
    // TCPFIX-01: Account for the 6-byte MBAP header prefix (transaction ID 2 +
    // protocol ID 2 + length field 2) that is NOT included in the length value.
    if (_resDataLen != null && _data.length >= _resDataLen! + 6) {
      _timeout.complete();
      request.setFromPduResponse(Uint8List.fromList(_data.sublist(7)));
    }
  }
}
