import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:meta/meta.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_dart/core/umas_var_in_out.dart';

/// A Modbus request carrying a UMAS (FC90) payload.
///
/// PDU structure: FC(0x5A) + PairingKey(1) + SubFunction(1) + Payload(N)
class UmasRequest extends ModbusRequest {
  final int umasSubFunction;
  final int pairingKey;
  final Uint8List umasPayload;

  /// Stores the raw response PDU after [internalSetFromPduResponse].
  Uint8List? responsePdu;

  // CRITICAL: All fields must be initialized via the initializer list
  // BEFORE super() runs, because ModbusRequest's constructor calls
  // protocolDataUnit getter during initialization.
  UmasRequest({
    required this.umasSubFunction,
    this.pairingKey = 0x00,
    Uint8List? payload,
    int? unitId,
    Duration? responseTimeout,
  })  : umasPayload = payload ?? Uint8List(0),
        super(unitId: unitId, responseTimeout: responseTimeout);

  @override
  FunctionCode get functionCode =>
      const ModbusFunctionCode(0x5A, FunctionType.custom);

  @override
  Uint8List get protocolDataUnit {
    final pdu = Uint8List(3 + umasPayload.length);
    pdu[0] = 0x5A; // Function code 90
    pdu[1] = pairingKey;
    pdu[2] = umasSubFunction;
    pdu.setAll(3, umasPayload);
    return pdu;
  }

  /// Variable length -- UMAS responses vary in size.
  @override
  int get responsePduLength => -1;

  @override
  ModbusResponseCode internalSetFromPduResponse(Uint8List pdu) {
    responsePdu = pdu;
    return ModbusResponseCode.requestSucceed;
  }
}

/// Client for UMAS protocol communication with Schneider PLCs via FC90.
///
/// Accepts a send function for dependency injection (use ModbusClientTcp.send
/// in production, or a mock in tests).
class UmasClient {
  /// Maximum allowed variable name length in bytes (defense against malformed responses).
  static const _maxNameLength = 1024;

  /// Maximum number of variables/data types parsed from a single response.
  static const _maxVariables = 10000;

  /// Maximum number of array elements expanded into per-element child nodes
  /// during browse(). Defensive cap against malformed or huge arrays.
  static const _maxArrayElements = 4096;
  final Future<ModbusResponseCode> Function(ModbusRequest request) sendFn;

  /// Optional Modbus unit ID for UMAS requests.
  /// Schneider PLCs typically use 255 (0xFF) or 254 (0xFE).
  final int? unitId;
  int _pairingKey = 0x00;

  /// Current UMAS session pairing key (assigned by the PLC during init/pair).
  /// Exposed for diagnostic/probe tooling that builds raw [UmasRequest]s.
  int get pairingKey => _pairingKey;

  int? maxFrameSize;

  /// Hardware ID from 0x02 (Read PLC Identification) response.
  int? _hardwareId;

  /// Memory block index from 0x02 response, used in 0x26 payloads.
  int? _index;

  /// Block CRC checksums from the last PlcStatus (0x04) response.
  /// Required by ReadVariable (0x22) and WriteVariable (0x23).
  List<int>? _blockCrcs;

  /// Project-level CRC computed from memory block 0x30 hashes
  /// (hash1 + hash2). Per PLC4X reference driver, ReadVariable (0x22) and
  /// WriteVariable (0x23) require this single project CRC, not a per-block
  /// CRC from PlcStatus. Populated by [_readProjectBlock]; null until the
  /// init sequence completes.
  int? _projectCrc;

  /// Project-level CRC for ReadVariable / WriteVariable. See [_projectCrc].
  int? get projectCrc => _projectCrc;

  /// CRCs from the previous successful PlcStatus poll, used for change detection.
  /// Null until the first successful readPlcStatus() call.
  List<int>? _previousCrcs;

  /// CRC checksums from the last PlcStatus (0x04) response.
  /// Null until [readPlcStatus] has been called successfully.
  List<int>? get blockCrcs => _blockCrcs;

  /// Maximum number of blocks accepted from PlcStatus response (T-03-02 mitigation).
  static const _maxBlocks = 256;

  /// Logger for session state transitions.
  static final _log = Logger(printer: SimplePrinter(), level: Level.info);

  /// Current session state backing field.
  UmasSessionState _stateValue = UmasSessionState.uninitialized;

  /// BehaviorSubject for reactive session state observation.
  final _stateSubject =
      BehaviorSubject<UmasSessionState>.seeded(UmasSessionState.uninitialized);

  /// Interval between keep-alive (0x12) messages when in PAIRED state.
  final Duration keepAliveInterval;

  /// F-8 (v1.1.x): interval between project-CRC re-reads. Each tick
  /// calls [refreshProjectMetadata], which re-reads memory block 0x30
  /// and emits on [projectCrcChanges] if [_projectCrc] moved. Default
  /// 30 seconds — operator-grade reprogram-while-running events are
  /// rare and a single extra TCP roundtrip every 30s is well below the
  /// noise floor of normal MonitorPlc polling.
  final Duration projectCrcCheckInterval;

  /// Periodic timer for sending keep-alive messages.
  Timer? _keepAliveTimer;

  /// F-8: periodic timer for re-checking the project CRC. Started in
  /// [startKeepAlive] (alongside the keep-alive timer), stopped in
  /// [stopKeepAlive] and [dispose].
  Timer? _projectCrcTimer;

  /// F-8: emits the new project CRC whenever [refreshProjectMetadata]
  /// observes a change. Subscribers (e.g.
  /// [ModbusDeviceClientAdapter]'s MonitorPlc batch) listen here to
  /// know they must rebuild downstream state (registered table,
  /// resolved symbol IDs) — the symbol cache itself is invalidated
  /// before the emit so a re-resolution sees the fresh data dictionary.
  ///
  /// Behaves like a broadcast stream — late subscribers do NOT receive
  /// past CRC values; they only get notified about future changes.
  final _projectCrcSubject = PublishSubject<int>();

  /// Public stream of project-CRC changes (F-8). See [_projectCrcSubject].
  Stream<int> get projectCrcChanges => _projectCrcSubject.stream;

  /// Maximum number of re-init retry attempts before propagating the error.
  static const _maxRetries = 3;

  /// Initial backoff delay for retry attempts.
  static const _initialBackoff = Duration(seconds: 1);

  /// Maximum backoff delay cap.
  static const _maxBackoff = Duration(seconds: 30);

  /// Multiplier for exponential backoff.
  static const _backoffMultiplier = 2.0;

  /// Injectable delay function for backoff (defaults to [Future.delayed]).
  final Future<void> Function(Duration) _delayFn;

  /// Whether the client has detected an M580 PLC (0xA1 error from 0x22)
  /// and should use MonitorPlc (0x50) for variable reads instead.
  ///
  /// TD-009 (v1.1.x): initial value is now constructor-injectable so the
  /// owning [ModbusDeviceClientAdapter] can carry the sticky M580-detected
  /// bit across UmasClient re-creates (each TCP reconnect spawns a fresh
  /// client). Without this, every reconnect re-probes via 0x22 → 0xA1 →
  /// 0x50 fallback, wasting one round-trip per reconnect.
  bool _useMonitorPlc;

  /// Whether this client is using the MonitorPlc (0x50) path for reads.
  /// True after detecting M580 via 0xA1 error from ReadVariable (0x22).
  bool get useMonitorPlc => _useMonitorPlc;

  /// MonitorPlc (0x50) registration table for tracking registered variables.
  final MonitorPlcRegistrationTable _monitorTable =
      MonitorPlcRegistrationTable();

  /// Expose the registration table for inspection/testing.
  MonitorPlcRegistrationTable get monitorRegistrations => _monitorTable;

  // ---------------------------------------------------------------------------
  // Symbol cache (B-3 v1.1.x) — read/write by UMAS variable name.
  // ---------------------------------------------------------------------------

  /// Resolved-symbol cache keyed by full dotted path (e.g.
  /// `B_F1_RC_01_Front` or `M_Elevator.speed`). Populated lazily on first
  /// [lookupSymbol] miss by issuing [browse], or eagerly by callers that
  /// invoke [browse] up front. Invalidated by [_handleSessionError] (PLC
  /// reboot) and by [invalidateSymbolCacheIfProjectChanged].
  final Map<String, ResolvedSymbol> _symbolCache = {};

  /// Cross-call caches re-used by [browse]'s struct/FB and array
  /// resolution. Hoisted to per-client lifetime so consecutive browses
  /// don't re-issue DD02 for the same custom type id (F-3 from v1.1
  /// Phase 2 SUMMARY).
  final Map<int, List<UmasVariable>> _persistentMemberCache = {};
  final Map<int, UmasArrayTypeDefinition?> _persistentArrayCache = {};

  /// Project CRC observed when the symbol cache was last populated. Used
  /// by [invalidateSymbolCacheIfProjectChanged] to flush the cache when
  /// the PLC project is reprogrammed.
  int? _symbolCacheProjectCrc;

  /// True once [browse] has populated the symbol cache for this session.
  bool _symbolCacheBuilt = false;

  /// Synchronous lock so concurrent first-time lookups share one browse.
  Completer<void>? _symbolCacheLock;

  /// Number of cached symbols (for testing / instrumentation).
  int get symbolCacheSize => _symbolCache.length;

  /// True if a symbol cache build has completed for the current session.
  bool get symbolCacheBuilt => _symbolCacheBuilt;

  /// Inject a [ResolvedSymbol] directly into the cache for tests that
  /// need to assert behavior of [readVariableByName] / [writeVariableByName]
  /// without standing up a full browse against the Python stub. Used
  /// e.g. to verify the F-7 VAR_IN_OUT write refusal path with a
  /// readable=false sentinel.
  @visibleForTesting
  void debugInjectSymbol(ResolvedSymbol sym) {
    _symbolCache[sym.path] = sym;
    _symbolCacheBuilt = true;
  }

  /// TD-004 (v1.1.x) test hook: force a session-state transition so
  /// the adapter's [EffectiveDeviceStatus] stream emits without
  /// having to drive a real handshake. Used by tests that need to
  /// verify the unhealthy / paired transitions without relying on
  /// the stub server's pairing flow.
  @visibleForTesting
  void debugSetSessionState(UmasSessionState newState) {
    _setState(newState);
  }

  UmasClient({
    required this.sendFn,
    this.unitId,
    this.keepAliveInterval = const Duration(seconds: 10),
    this.projectCrcCheckInterval = const Duration(seconds: 30),
    Future<void> Function(Duration)? backoffDelay,
    bool useMonitorPlc = false,
  })  : _delayFn = backoffDelay ?? ((d) => Future.delayed(d)),
        _useMonitorPlc = useMonitorPlc;

  /// Start periodic keep-alive timer. Cancels any existing timer first.
  ///
  /// The timer calls [sendKeepAlive] every [keepAliveInterval]. If the
  /// session is not in PAIRED state, the tick is skipped. If sendKeepAlive
  /// throws, the session is reset to uninitialized via [_handleSessionError].
  ///
  /// F-8 (v1.1.x): also starts the separate [_projectCrcTimer] that
  /// periodically re-reads memory block 0x30 to detect PLC reprograms
  /// without a session-level error.
  void startKeepAlive() {
    stopKeepAlive();
    _keepAliveTimer = Timer.periodic(keepAliveInterval, (_) async {
      if (_stateValue != UmasSessionState.paired) return;
      try {
        await sendKeepAlive();
      } on UmasException {
        _handleSessionError();
      } catch (_) {
        // Prevent unhandled exceptions in timer callback
        _handleSessionError();
      }
    });
    _projectCrcTimer = Timer.periodic(projectCrcCheckInterval, (_) async {
      if (_stateValue != UmasSessionState.paired) return;
      try {
        await refreshProjectMetadata();
      } catch (e) {
        // Best-effort: a single failed CRC read should NOT bring down
        // the session. The next tick will retry; if the underlying
        // session is genuinely broken, keep-alive will catch it.
        _log.w('UmasClient projectCrc tick failed: $e');
      }
    });
  }

  /// Stop the keep-alive timer (and the F-8 project-CRC timer).
  void stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _projectCrcTimer?.cancel();
    _projectCrcTimer = null;
  }

  /// Release resources (cancels keep-alive timer and closes the session state stream).
  void dispose() {
    stopKeepAlive();
    _stateSubject.close();
    if (!_projectCrcSubject.isClosed) {
      _projectCrcSubject.close();
    }
  }

  /// Current session state.
  UmasSessionState get sessionState => _stateValue;

  /// Stream of session state changes (seeded with current state).
  Stream<UmasSessionState> get sessionStream => _stateSubject.stream;

  /// Transition to a new session state with logging.
  void _setState(UmasSessionState newState) {
    if (_stateValue != newState) {
      _log.i('UmasClient: $_stateValue -> $newState');
      _stateValue = newState;
      if (!_stateSubject.isClosed) {
        _stateSubject.add(newState);
      }
    }
  }

  /// Lock to serialize concurrent session initialization.
  Completer<void>? _initLock;

  /// Ensures the UMAS session is fully initialized (paired) before running
  /// [operation]. Auto-runs readPlcId and/or init as needed. Concurrent
  /// callers wait on the same initialization via a Completer lock.
  ///
  /// If initialization fails, retries with exponential backoff up to
  /// [_maxRetries] times. On success, resets backoff counter and starts
  /// the keep-alive timer.
  Future<T> _withSession<T>(Future<T> Function() operation) async {
    if (_stateValue == UmasSessionState.paired) {
      return operation();
    }
    // Serialize initialization — concurrent callers wait on the same lock
    if (_initLock != null) {
      await _initLock!.future;
      return operation();
    }
    _initLock = Completer<void>();
    // Prevent unhandled async error if no concurrent caller is waiting
    _initLock!.future.ignore();
    try {
      await _initWithRetry();
      _initLock!.complete();
    } catch (e) {
      _initLock!.completeError(e);
      rethrow;
    } finally {
      _initLock = null;
    }
    return operation();
  }

  /// Run the init sequence (readPlcId + init + readProjectBlock) with exponential backoff retry.
  Future<void> _initWithRetry() async {
    Object? lastError;
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (_stateValue == UmasSessionState.uninitialized) {
          await readPlcId();
        }
        if (_stateValue == UmasSessionState.identified) {
          await init();
        }
        // Read the real hardwareId/index from memory block 0x30
        // (readPlcId returns PLC ident, NOT the project-level values
        // needed for Data Dictionary requests)
        await _readProjectBlock();
        // Success — start keep-alive
        startKeepAlive();
        return;
      } catch (e) {
        lastError = e;
        _handleSessionError(); // Reset state for clean retry
        if (attempt < _maxRetries) {
          final delay = _computeBackoff(attempt);
          await _delayFn(delay);
        }
      }
    }
    // All retries exhausted
    if (lastError is Exception) {
      throw lastError;
    }
    throw UmasException(
        errorCode: 0, message: 'Init failed after $_maxRetries retries');
  }

  /// Compute backoff delay for a given attempt number.
  Duration _computeBackoff(int attempt) {
    final delayMs = _initialBackoff.inMilliseconds *
        _pow(_backoffMultiplier, attempt);
    final cappedMs = delayMs.clamp(0, _maxBackoff.inMilliseconds);
    return Duration(milliseconds: cappedMs.toInt());
  }

  /// Integer-safe power for backoff multiplier.
  static double _pow(double base, int exp) {
    double result = 1.0;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  /// UMAS success status byte value.
  static const _statusSuccess = 0xFE;

  /// UMAS error status byte value (followed by error code byte).
  static const _statusError = 0xFD;

  /// Check UMAS response PDU and throw on error.
  ///
  /// Real Schneider PLC response format (3-byte header):
  ///   pdu[0] = FC (0x5A)
  ///   pdu[1] = PairingKey
  ///   pdu[2] = Status (0xFE=success, 0xFD=error, other=error code)
  ///   pdu[3+] = Payload (on success) or error code (on 0xFD error)
  ///
  /// SWEEP-03 (v1.1): always prefixes the [operation] token (e.g.
  /// `"writeVariable"`, `"readDD02(blockNo=0x...)"`) so operator log
  /// greps can isolate failures by sub-function. Every caller passes
  /// a stable operation name — the previous implementation did so
  /// inconsistently; this is now the contract.
  void _checkStatus(Uint8List pdu, String operation) {
    if (pdu.length < 3) {
      throw UmasException(
          errorCode: 0, message: 'UMAS $operation response too short');
    }
    final status = pdu[2];
    if (status == _statusError) {
      final errorCode = pdu.length > 3 ? pdu[3] : 0;
      throw UmasException(
          errorCode: errorCode,
          message: 'UMAS $operation error: '
              '0x${errorCode.toRadixString(16)}');
    }
    if (status != _statusSuccess) {
      throw UmasException(
          errorCode: status,
          message: 'UMAS $operation failed with status '
              '0x${status.toRadixString(16)}');
    }
  }

  /// Read PLC identification (sub-function 0x02).
  ///
  /// Extracts hardwareId and memory block index needed for 0x26 requests.
  /// Must be called before readVariableNames/readDataTypes/browse.
  Future<UmasPlcIdent> readPlcId() async {
    final request = UmasRequest(
      umasSubFunction: UmasSubFunction.readId.code,
      pairingKey: _pairingKey,
      unitId: unitId,
    );
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code,
          message: 'UMAS readPlcId failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 3) {
      throw UmasException(
          errorCode: 0, message: 'Empty UMAS readPlcId response');
    }

    _checkStatus(pdu, 'readPlcId');

    // Parse payload after the 3-byte header (FC + pairing + status)
    final payload = pdu.sublist(3);
    if (payload.length < 7) {
      throw UmasException(
          errorCode: 0,
          message: 'UMAS readPlcId response too short: ${payload.length}');
    }

    final pd = ByteData.sublistView(payload);
    // range(2) + ident/hardwareId(4 LE) + numberOfMemoryBanks(1) + memBlockEntries
    // Skip range (2 bytes), read hardwareId (4 bytes LE)
    final hardwareId = pd.getUint32(2, Endian.little);

    // numberOfMemoryBanks at offset 6
    final numberOfMemoryBanks = pd.getUint8(6);

    // First memory block entry starts at offset 7:
    //   address(2 LE) + blockType(1) + unknown(2) + memoryLength(4) = 9 bytes
    int index = 0;
    if (numberOfMemoryBanks > 0 && payload.length >= 9) {
      index = pd.getUint16(7, Endian.little);
    }

    _hardwareId = hardwareId;
    _index = index;
    _setState(UmasSessionState.identified);

    return UmasPlcIdent(
      hardwareId: hardwareId,
      index: index,
      numberOfMemoryBanks: numberOfMemoryBanks,
    );
  }

  /// Initialize UMAS communication (sub-function 0x01).
  /// Returns max frame size and optionally firmware version.
  ///
  /// Per PLC4X mspec UmasPDUInitCommsRequest, the request body is a single
  /// `subCode` byte (always 0x00 in the reference implementation). Without it
  /// the M580 rejects with status 0x83.
  Future<UmasInitResult> init() async {
    final request = UmasRequest(
        umasSubFunction: UmasSubFunction.init.code,
        pairingKey: _pairingKey,
        payload: Uint8List.fromList([0x00]),
        unitId: unitId);
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
          errorCode: code.code, message: 'UMAS init failed: ${code.name}');
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 3) {
      throw UmasException(errorCode: 0, message: 'Empty UMAS init response');
    }

    _checkStatus(pdu, 'init');

    // PDU: FC(0x5A) + pairingKey + status + payload
    final responsePairingKey = pdu[1];
    _pairingKey = responsePairingKey;

    // Parse payload after the 3-byte header (FC + pairing + status)
    if (pdu.length >= 5) {
      final payloadView = ByteData.sublistView(pdu, 3);
      maxFrameSize = payloadView.getUint16(0, Endian.little);
    }

    _setState(UmasSessionState.paired);

    return UmasInitResult(maxFrameSize: maxFrameSize ?? 240);
  }

  /// Read project-level hardwareId and index from memory block 0x30.
  ///
  /// PLC4X reads these values from memory — NOT from readPlcId (0x02).
  /// The readPlcId response contains PLC identification fields, but the
  /// hardwareId/index needed for Data Dictionary (0x26) requests come
  /// from the project memory block at address 0x30.
  ///
  /// Format (UmasMemoryBlockBasicInfo from PLC4X mspec):
  ///   range(2 LE) + notSure(2 LE) + index(1) + hardwareId(4 LE)
  Future<void> _readProjectBlock() async {
    final payload = ByteData(9);
    payload.setUint8(0, 0x00); // range
    payload.setUint16(1, 0x0030, Endian.little); // blockNumber
    payload.setUint16(3, 0x0000, Endian.little); // offset
    payload.setUint16(5, 0x0000, Endian.little); // unknownObject1
    payload.setUint16(7, 0x0021, Endian.little); // numberOfBytes (33)

    final request = UmasRequest(
      umasSubFunction: UmasSubFunction.readMemoryBlock.code,
      pairingKey: _pairingKey,
      payload: payload.buffer.asUint8List(),
      unitId: unitId,
    );
    final code = await sendFn(request);

    if (code != ModbusResponseCode.requestSucceed) {
      _log.w('ReadMemoryBlock(0x30) failed: ${code.name} '
          '— using readPlcId values for DD requests');
      return;
    }

    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 3) return;

    try {
      _checkStatus(pdu, 'readMemoryBlock(0x30)');
    } on UmasException catch (e) {
      _log.w('ReadMemoryBlock(0x30) error: ${e.message} '
          '— using readPlcId values for DD requests');
      return;
    }

    // Response: 3-byte header + range(1) + numberOfBytes(2 LE) + data
    final respPayload = pdu.sublist(3);
    if (respPayload.length < 12) return; // need at least header + 9 bytes

    final respView = ByteData.sublistView(respPayload);
    final numberOfBytes = respView.getUint16(1, Endian.little);
    if (numberOfBytes < 9) return;

    // Parse UmasMemoryBlockBasicInfo at offset 3 (after range + numberOfBytes)
    // range(2 LE) + notSure(2 LE) + index(1) + hardwareId(4 LE) = 9 bytes
    // followed by hash1(4 LE) + hash2(4 LE) (PLC4X discovery from packet
    // captures: projectCrc = (hash1 + hash2) & 0xFFFFFFFF)
    final blockData = ByteData.sublistView(respPayload, 3);
    final projectIndex = blockData.getUint8(4);
    final projectHardwareId = blockData.getUint32(5, Endian.little);

    int? projectCrc;
    if (blockData.lengthInBytes >= 17) {
      final hash1 = blockData.getUint32(9, Endian.little);
      final hash2 = blockData.getUint32(13, Endian.little);
      projectCrc = (hash1 + hash2) & 0xFFFFFFFF;
    }

    _log.i('Project block 0x30: index=$projectIndex, '
        'hardwareId=0x${projectHardwareId.toRadixString(16)}, '
        'projectCrc=${projectCrc == null ? 'n/a' : '0x${projectCrc.toRadixString(16)}'} '
        '(was: index=${_index}, hwId=0x${(_hardwareId ?? 0).toRadixString(16)})');

    _index = projectIndex;
    _hardwareId = projectHardwareId;
    _projectCrc = projectCrc;
  }

  /// Read project info (sub-function 0x03).
  ///
  /// Returns raw response bytes and a best-effort extracted project name.
  /// The [subcode] parameter selects the type of project info to retrieve
  /// (default 0x00).
  ///
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<ProjectInfoResult> readProjectInfo({int subcode = 0x00}) async {
    return _withSession(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readProjectInfo.code,
        pairingKey: _pairingKey,
        payload: Uint8List.fromList([subcode]),
        unitId: unitId,
      );
      final code = await sendFn(request);

      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'UMAS readProjectInfo failed: ${code.name}');
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty UMAS readProjectInfo response');
      }

      _checkStatus(pdu, 'readProjectInfo');

      // Raw data is everything after the 3-byte UMAS header
      final rawData = pdu.sublist(3);

      // Best-effort project name extraction: find the longest run of
      // printable ASCII bytes (0x20-0x7E).
      final projectName = _extractLongestAsciiRun(rawData);

      return ProjectInfoResult(rawData: rawData, projectName: projectName);
    });
  }

  /// Extract the longest contiguous run of printable ASCII characters
  /// from [data]. Returns null if no run of 2+ printable chars is found.
  static String? _extractLongestAsciiRun(Uint8List data) {
    String? longest;
    int longestLen = 0;
    int runStart = -1;

    for (int i = 0; i <= data.length; i++) {
      final isPrintable = i < data.length && data[i] >= 0x20 && data[i] <= 0x7E;
      if (isPrintable) {
        if (runStart < 0) runStart = i;
      } else {
        if (runStart >= 0) {
          final runLen = i - runStart;
          if (runLen > longestLen) {
            longestLen = runLen;
            longest = String.fromCharCodes(data, runStart, i);
          }
          runStart = -1;
        }
      }
    }

    // Require at least 2 printable chars to avoid false positives
    return longestLen >= 2 ? longest : null;
  }

  /// Build the full 13-byte payload for 0x26 (ReadDataDictionary) requests.
  ///
  /// Format per PLC4X mspec:
  ///   recordType(2 LE) + index(1) + hardwareId(4 LE) + blockNo(2 LE) +
  ///   offset(2 LE)
  /// DD02 also appends a 2-byte trailing blank field. DD03 does NOT —
  /// sending the extra 2 bytes makes the M580 return error 0xC0.
  Uint8List _build0x26Payload({
    required int recordType,
    required int blockNo,
    required int offset,
  }) {
    final includeBlank = recordType == 0xDD02;
    final bd = ByteData(includeBlank ? 13 : 11);
    bd.setUint16(0, recordType, Endian.little);
    bd.setUint8(2, _index ?? 0);
    bd.setUint32(3, _hardwareId ?? 0, Endian.little);
    bd.setUint16(7, blockNo, Endian.little);
    bd.setUint16(9, offset, Endian.little);
    if (includeBlank) {
      bd.setUint16(11, 0x0000, Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  /// Read variable names from the data dictionary (0x26 with record type 0xDD02).
  ///
  /// Auto-initializes the session if needed via [_withSession].
  /// Paginates: loops until nextAddress == 0 after first response.
  Future<List<UmasVariable>> readVariableNames() async {
    return _withSessionAndRecovery(_readVariableNamesInner);
  }

  Future<List<UmasVariable>> _readVariableNamesInner() async {
    return _readDD02Block(blockNo: 0xFFFF, isMemberLayout: false);
  }

  /// Read DD02 records for a given blockNo, paginating across nextAddress.
  ///
  /// blockNo=0xFFFF returns the top-level variable list (10-byte record
  /// header per entry). blockNo=<typeId> returns the member layout of
  /// that struct/FB type (8-byte record header per entry, since the
  /// flags+unknown4 bytes are absent for member records).
  ///
  /// [parentClassId] — when this block represents a member layout, the
  /// classIdentifier of the parent type (2=STRUCT/UDT, 7=FB). Direction
  /// classification only runs when parentClassId==7 (FB members). For
  /// non-FB UDTs the direction stays null so the UI renders members
  /// undecorated (F-1 v1.1: fixes the case where the byte-classifier
  /// fired on arbitrary UDT struct fields).
  Future<List<UmasVariable>> _readDD02Block({
    required int blockNo,
    required bool isMemberLayout,
    int? parentClassId,
  }) async {
    final all = <UmasVariable>[];
    int offset = 0x0000;
    bool first = true;

    while (offset != 0x0000 || first) {
      first = false;
      final payload = _build0x26Payload(
        recordType: 0xDD02,
        blockNo: blockNo,
        offset: offset,
      );
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readDataDictionary.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'Data Dictionary read failed: ${code.name}');
      }
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty data dictionary response');
      }
      _checkStatus(pdu, 'readDD02(blockNo=0x${blockNo.toRadixString(16)})');
      final (nextAddress, variables) = _parseVariableRecords(
        pdu.sublist(3),
        isMemberLayout: isMemberLayout,
        parentClassId: parentClassId,
      );
      all.addAll(variables);
      offset = nextAddress;
    }
    return all;
  }

  /// Read the member layout for a struct/FB data type.
  ///
  /// Returns the members; each [UmasVariable]'s `blockNo` is the byte offset
  /// of that member within the parent struct, and `dataTypeId` is the member's
  /// own type id (resolved against [readDataTypes]).
  ///
  /// [parentClassId] — the classIdentifier of the parent type (2 for
  /// STRUCT/UDT, 7 for FB). When omitted, direction classification is
  /// suppressed (safe default) — callers that know the parent is an FB
  /// should pass 7 to get per-member direction in the returned values.
  Future<List<UmasVariable>> readStructMembers(int typeId,
      {int? parentClassId}) async {
    return _withSessionAndRecovery(() => _readDD02Block(
        blockNo: typeId,
        isMemberLayout: true,
        parentClassId: parentClassId));
  }

  /// Read raw DD02 response bytes for [blockNo].
  ///
  /// Returns the response payload after the 3-byte UMAS header. For struct
  /// types this is the standard variable-record list; for array types this
  /// is a [UmasArrayTypeDefinition] (classId(1) + elementTypeId(2) +
  /// numberOfDimensions(1) + dimensions[]) followed by the dictionary
  /// header. Used by [_resolveArrayTypeDefinition] to extract per-element
  /// metadata for arrays.
  Future<Uint8List> readDD02Raw(int blockNo) async {
    return _withSessionAndRecovery(() async {
      final payload = _build0x26Payload(
        recordType: 0xDD02,
        blockNo: blockNo,
        offset: 0x0000,
      );
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readDataDictionary.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'DD02 raw read failed: ${code.name}');
      }
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty DD02 raw response');
      }
      _checkStatus(pdu, 'readDD02Raw(blockNo=0x${blockNo.toRadixString(16)})');
      return pdu.sublist(3);
    });
  }

  /// Parse variable name records from the 0xDD02 response payload.
  ///
  /// Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
  /// Per-record (variable-length header followed by null-terminated UTF-8 name):
  ///   dataType(2 LE) + block(2 LE) + offset(4 LE) + flags(1)
  ///   [+ extra(1) when flags != 0]
  ///   + name\0
  ///
  /// The `flags` byte is 0 for plain struct members and non-zero for
  /// top-level variables / FB members where an additional byte follows
  /// before the name.
  ///
  /// The same wire format serves both top-level variable lists and struct
  /// member lists. For struct members, `block` holds the member's byte
  /// offset within the parent struct instead of a memory block number.
  (int nextAddress, List<UmasVariable>) _parseVariableRecords(
    Uint8List data, {
    required bool isMemberLayout,
    int? parentClassId,
  }) {
    if (data.length < 7) return (0, []);

    final hd = ByteData.sublistView(data);
    final nextAddress = hd.getUint16(1, Endian.little);
    final noOfRecords = hd.getUint16(5, Endian.little);

    final variables = <UmasVariable>[];
    int pos = 7;

    // Top-level records have a 10-byte header (dataType + block + offset
    // + flags + unknown4) before the null-terminated name.
    // Member records have an 8-byte header (dataType + block + offset)
    // before the name; flags/unknown4 are absent.
    final headerSize = isMemberLayout ? 8 : 10;

    for (int i = 0; i < noOfRecords && pos + headerSize <= data.length; i++) {
      if (variables.length >= _maxVariables) break;

      final view = ByteData.sublistView(data, pos);
      final dataTypeId = view.getUint16(0, Endian.little);
      final blockNo = view.getUint16(2, Endian.little);
      final offset = view.getUint32(4, Endian.little);

      // Phase 3 / v1.1 calibration: for member-layout records, the two
      // uint16 LE values at bytes 4-5 and 6-7 are plc4j's `unknown5` and
      // `unknown4` fields (see UmasUDTDefinition mspec). Bytes 4-7 are
      // also re-read above as a uint32 `offset` — the two views coexist
      // because Dart's getUint32(LE) is identical to (getUint16(4,LE) |
      // getUint16(6,LE) << 16). Live-PLC calibration on the M580 at
      // 192.168.112.159 (see tools/umas_direction_calibration.dart)
      // showed that only `unknown4` carries direction; `unknown5` is
      // always zero. F-1: only classify when the parent is an FB
      // (classIdentifier==7); non-FB UDT struct members keep
      // direction=null so the UI renders them undecorated.
      UmasFbMemberDirection? direction;
      if (isMemberLayout && parentClassId == 7) {
        final unknown5 = view.getUint16(4, Endian.little);
        final unknown4 = view.getUint16(6, Endian.little);
        direction = classifyFbMemberDirection(unknown5, unknown4);
      }
      pos += headerSize;

      int end = pos;
      while (end < data.length && data[end] != 0x00) {
        end++;
      }
      if (end >= data.length || end - pos > _maxNameLength) {
        break;
      }
      final name = utf8.decode(data.sublist(pos, end), allowMalformed: true);
      pos = end + 1;

      if (name.isEmpty) continue;

      variables.add(UmasVariable(
        name: name,
        blockNo: blockNo,
        offset: offset,
        dataTypeId: dataTypeId,
        direction: direction,
      ));
    }

    return (nextAddress, variables);
  }

  /// Read data type references from the data dictionary (0x26 with record type 0xDD03).
  ///
  /// Auto-initializes the session if needed via [_withSession].
  /// Paginates: loops until nextAddress == 0 after first response.
  Future<List<UmasDataTypeRef>> readDataTypes() async {
    return _withSessionAndRecovery(_readDataTypesInner);
  }

  Future<List<UmasDataTypeRef>> _readDataTypesInner() async {
    final allTypes = <UmasDataTypeRef>[];
    int blockNo = 0x0000;
    bool firstMessage = true;

    while (blockNo != 0x0000 || firstMessage) {
      firstMessage = false;

      final payload = _build0x26Payload(
        recordType: 0xDD03,
        blockNo: blockNo,
        offset: 0x0000,
      );
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readDataDictionary.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
      );
      final code = await sendFn(request);

      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'Data Dictionary type read failed: ${code.name}');
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty data type response');
      }

      _checkStatus(pdu, 'readDataTypes');

      final (nextAddress, types) = _parseDataTypeRecords(pdu.sublist(3));
      allTypes.addAll(types);
      blockNo = nextAddress;
    }

    return allTypes;
  }

  /// Parse data type records from the 0xDD03 response payload.
  ///
  /// Per PLC4X UmasPDUReadDatatypeNamesResponse mspec:
  ///   Header: range(1) + unknown1(4) + noOfRecords(2 LE) = 7 bytes
  ///   Per record (UmasDatatypeReference):
  ///     dataSize(2 LE) + unknown1(2 LE) + classIdentifier(1) + dataType(1)
  ///     + reserved 0x00(1) + null-terminated UTF-8 name
  ///
  /// DD03 does not paginate — the entire type table arrives in a single
  /// response, so the returned nextAddress is always 0.
  (int nextAddress, List<UmasDataTypeRef>) _parseDataTypeRecords(
      Uint8List data) {
    if (data.length < 7) return (0, []);

    final hd = ByteData.sublistView(data);
    final noOfRecords = hd.getUint16(5, Endian.little);

    final types = <UmasDataTypeRef>[];
    int pos = 7;

    for (int i = 0; i < noOfRecords && pos + 7 <= data.length; i++) {
      if (types.length >= _maxVariables) break;

      final view = ByteData.sublistView(data, pos);
      final dataSize = view.getUint16(0, Endian.little);
      final classIdentifier = view.getUint8(4);
      final dataType = view.getUint8(5);
      pos += 7;

      int end = pos;
      while (end < data.length && data[end] != 0x00) {
        end++;
      }
      if (end >= data.length || end - pos > _maxNameLength) {
        break;
      }
      final name = utf8.decode(data.sublist(pos, end), allowMalformed: true);
      pos = end + 1;

      // Use the PLC-assigned `dataType` byte as the lookup id, so that a
      // variable whose DD02 record references dataTypeId=N resolves to the
      // DD03 record whose dataType=N. (Built-in types use the same scheme.)
      types.add(UmasDataTypeRef(
        id: dataType,
        name: name,
        byteSize: dataSize,
        classIdentifier: classIdentifier,
        dataType: dataType,
      ));
    }

    return (0, types);
  }

  /// Build a hierarchical variable tree from a flat list of variables.
  /// Variable names use dot-separated paths (e.g. "App.GVL.temp").
  List<UmasVariableTreeNode> buildVariableTree(
      List<UmasVariable> variables, List<UmasDataTypeRef> dataTypes) {
    // Use a nested map structure for efficient tree construction,
    // then convert to UmasVariableTreeNode at the end.
    final tree = _TreeBuilder();

    for (final v in variables) {
      tree.insert(v, dataTypes);
    }

    return tree.build();
  }

  /// Read PLC status (sub-function 0x04).
  ///
  /// Returns PLC run state and memory block CRC checksums needed for
  /// ReadVariable (0x22). CRCs are also stored on the client instance
  /// via [blockCrcs] for later use.
  ///
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<PlcStatusResult> readPlcStatus() async {
    return _withSession(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.plcStatus.code,
        pairingKey: _pairingKey,
        unitId: unitId,
      );
      final code = await sendFn(request);

      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'UMAS plcStatus failed: ${code.name}');
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty UMAS plcStatus response');
      }

      _checkStatus(pdu, 'plcStatus');

      // Parse payload after 3-byte UMAS header:
      //   pdu[3] = statusByte (1 byte)
      //   pdu[4..5] = notUsed2 (2 bytes, skip)
      //   pdu[6] = numberOfBlocks (1 byte)
      //   pdu[7..] = blocks array: numberOfBlocks * uint32 (4 bytes each, LE)
      //   remaining = additionalData
      if (pdu.length < 7) {
        throw UmasException(
            errorCode: 0,
            message: 'UMAS plcStatus response too short: ${pdu.length}');
      }

      final statusByte = pdu[3];
      var numberOfBlocks = pdu[6];

      // Cap numberOfBlocks to prevent memory exhaustion (T-03-02)
      if (numberOfBlocks > _maxBlocks) {
        numberOfBlocks = _maxBlocks;
      }

      final blockCrcs = <int>[];
      final blockDataStart = 7;
      final availableBlockBytes = pdu.length - blockDataStart;
      final actualBlocks =
          numberOfBlocks.clamp(0, availableBlockBytes ~/ 4);

      if (actualBlocks > 0) {
        final bd = ByteData.sublistView(pdu);
        for (int i = 0; i < actualBlocks; i++) {
          blockCrcs.add(bd.getUint32(blockDataStart + i * 4, Endian.little));
        }
      }

      final additionalDataStart = blockDataStart + actualBlocks * 4;
      final additionalData = additionalDataStart < pdu.length
          ? pdu.sublist(additionalDataStart)
          : Uint8List(0);

      _blockCrcs = List.unmodifiable(blockCrcs);

      // Detect CRC changes by comparing with previous poll (T-03-05: element-wise)
      bool crcChanged = false;
      if (_previousCrcs != null) {
        if (_previousCrcs!.length != blockCrcs.length) {
          crcChanged = true;
        } else {
          for (int i = 0; i < blockCrcs.length; i++) {
            if (_previousCrcs![i] != blockCrcs[i]) {
              crcChanged = true;
              break;
            }
          }
        }
      }
      _previousCrcs = List.from(blockCrcs);

      return PlcStatusResult(
        statusByte: statusByte,
        numberOfBlocks: numberOfBlocks,
        blockCrcs: blockCrcs,
        additionalData: additionalData,
        crcChanged: crcChanged,
      );
    });
  }

  /// Send a KeepAlive (0x12) to maintain the UMAS session.
  ///
  /// Uses [_withSession] to auto-initialize if not yet paired.
  /// Returns void on success; throws [UmasException] on error.
  Future<void> sendKeepAlive() async {
    return _withSession(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.keepAlive.code,
        pairingKey: _pairingKey,
        unitId: unitId,
      );
      final code = await sendFn(request);

      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'UMAS keepAlive failed: ${code.name}');
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty UMAS keepAlive response');
      }

      _checkStatus(pdu, 'keepAlive');
    });
  }

  /// Send an Echo/Repeat (0x0A) with [payload] and measure round-trip latency.
  ///
  /// Uses [_withSession] to auto-initialize if not yet paired.
  /// Returns [UmasEchoResult] with the echoed payload and latency duration.
  Future<UmasEchoResult> sendEcho(Uint8List payload) async {
    return _withSession(() async {
      final stopwatch = Stopwatch()..start();

      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.echo.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
      );
      final code = await sendFn(request);

      stopwatch.stop();

      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
            errorCode: code.code,
            message: 'UMAS echo failed: ${code.name}');
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
            errorCode: 0, message: 'Empty UMAS echo response');
      }

      _checkStatus(pdu, 'echo');

      // Extract echoed payload from response PDU after 3-byte header
      final echoedPayload = pdu.sublist(3);

      return UmasEchoResult(
        payload: echoedPayload,
        latency: stopwatch.elapsed,
      );
    });
  }

  /// Whether this client currently holds an exclusive PLC reservation.
  bool _hasReservation = false;

  /// Whether this client currently holds an exclusive PLC reservation.
  bool get hasReservation => _hasReservation;

  /// Acquire exclusive PLC write reservation (sub-function 0x10).
  ///
  /// Sets [hasReservation] to true on success.
  ///
  /// **Exception taxonomy (TD-014, v1.1.x):**
  /// - Transport-level errors (e.g. Modbus exception code, no PDU) →
  ///   plain [UmasException]. These are not reservation conflicts;
  ///   they're network / framing failures and callers should not
  ///   special-case them as "another client holds the lock."
  /// - PLC-side reservation conflict (UMAS status error byte with the
  ///   well-known 0x06 conflict error code, or any other non-success
  ///   status accompanied by a UMAS-error payload) → [UmasReservationException]
  ///   so the UI/operator workflow can present a graceful "wait for
  ///   the other client to release" affordance instead of a generic
  ///   "something failed" red banner.
  ///
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<void> takePlcReservation() async {
    return _withSession(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.takePlcReservation.code,
        pairingKey: _pairingKey,
        unitId: unitId,
      );
      final code = await sendFn(request);

      if (code != ModbusResponseCode.requestSucceed) {
        // TD-014: transport-level failure is NOT a reservation conflict.
        // Surface as plain UmasException so callers don't false-positive
        // on "another client holds the lock" UX when the network is just
        // down.
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS takePlcReservation transport error: ${code.name}',
        );
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS takePlcReservation response',
        );
      }

      // Check for UMAS-level error. The conflict-byte 0x06 ("another
      // client holds the reservation") is the only condition that
      // should be surfaced as UmasReservationException; other status
      // errors (e.g. 0x83 Data Dictionary disabled, 0xC0 access
      // denied) are real protocol errors that callers MUST NOT treat
      // as a transient reservation conflict.
      if (pdu[2] == _statusError || pdu[2] != _statusSuccess) {
        final errorCode = pdu.length > 3 ? pdu[3] : 0;
        if (errorCode == 0x06) {
          throw UmasReservationException(
            errorCode: errorCode,
            message: 'Another client holds the PLC reservation',
          );
        }
        throw UmasException(
          errorCode: errorCode,
          message: 'UMAS takePlcReservation failed: status=0x'
              '${pdu[2].toRadixString(16).padLeft(2, '0')} '
              'errorCode=0x${errorCode.toRadixString(16).padLeft(2, '0')}',
        );
      }

      _hasReservation = true;
    });
  }

  /// Release PLC write reservation (sub-function 0x11).
  ///
  /// Best-effort: sets [hasReservation] to false even on error,
  /// because a failed release should not leave stale local state.
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<void> releasePlcReservation() async {
    try {
      await _withSession(() async {
        final request = UmasRequest(
          umasSubFunction: UmasSubFunction.releasePlcReservation.code,
          pairingKey: _pairingKey,
          unitId: unitId,
        );
        final code = await sendFn(request);

        if (code != ModbusResponseCode.requestSucceed) {
          _log.w('UMAS releasePlcReservation transport error: ${code.name}');
          return;
        }

        final pdu = request.responsePdu;
        if (pdu != null && pdu.length >= 3 && pdu[2] != _statusSuccess) {
          _log.w('UMAS releasePlcReservation status error: '
              '0x${pdu[2].toRadixString(16)}');
        }
      });
    } catch (e) {
      _log.w('UMAS releasePlcReservation failed: $e');
    } finally {
      _hasReservation = false;
    }
  }

  /// Execute [operation] while holding an exclusive PLC reservation.
  ///
  /// Acquires reservation via [takePlcReservation], runs [operation],
  /// and releases via [releasePlcReservation] in a finally block to
  /// prevent orphaned reservations (T-06-02 mitigation).
  Future<T> withReservation<T>(Future<T> Function() operation) async {
    await takePlcReservation();
    try {
      return await operation();
    } finally {
      await releasePlcReservation();
    }
  }

  /// Reset all session state when UMAS session is invalidated.
  /// Called when error responses indicate the pairing key is no longer valid
  /// (PLC reboot, engineering tool connection, TCP reconnection).
  ///
  /// SWEEP-04 (v1.1): also clears [_projectCrc] so a PLC reboot
  /// mid-session does not carry a stale project CRC into the
  /// post-reboot session. Without this, after a PLC reprogramming
  /// reboot, the next 0x22 / 0x23 request would send the old
  /// project CRC and either silently match the wrong project or be
  /// rejected with a CRC-mismatch error attributed to the wrong
  /// cause.
  void _handleSessionError() {
    _log.i('UMAS session invalidated, resetting to uninitialized');
    _pairingKey = 0x00;
    _hardwareId = null;
    _index = null;
    maxFrameSize = null;
    _previousCrcs = null;
    _projectCrc = null; // SWEEP-04
    _hasReservation = false;
    // TD-009 (v1.1.x): do NOT reset _useMonitorPlc. The M580-detected
    // bit is a hardware fingerprint that does not change across PLC
    // reboots / session resets. Clearing it would cause the next read
    // to re-probe via 0x22 → 0xA1 → 0x50 fallback (one wasted RTT).
    // The adapter wraps this client and reseeds _useMonitorPlc across
    // client re-creates; we only reset when the underlying serverAlias
    // (and therefore the PLC identity) changes.
    _monitorTable.reset();
    // B-3: drop the symbol cache too — a session reset usually means the
    // PLC rebooted or the engineering tool reset the connection, and any
    // cached symbol→(blockNo, offset) mapping may now point at a moved
    // variable in a freshly-downloaded project. Force re-browse next time.
    _clearSymbolCache();
    _setState(UmasSessionState.uninitialized);
  }

  /// Clear the symbol cache + cross-call browse caches. Forces the next
  /// [lookupSymbol] (or [readVariableByName] / [writeVariableByName]) to
  /// re-browse the PLC.
  void _clearSymbolCache() {
    _symbolCache.clear();
    _persistentMemberCache.clear();
    _persistentArrayCache.clear();
    _symbolCacheBuilt = false;
    _symbolCacheProjectCrc = null;
  }

  /// Public hook for callers that detect a project change (e.g. a poll
  /// loop that calls [readPlcStatus] and observes `crcChanged=true`).
  /// Drops the symbol cache if the project CRC changed since the cache
  /// was built. Safe to call repeatedly — no-op when CRCs match.
  ///
  /// F-8 (v1.1.x): now invoked from the periodic [_projectCrcTimer]
  /// via [refreshProjectMetadata] so PLC reprograms are detected
  /// without waiting for a session-level error. On a CRC change this
  /// method clears the symbol cache AND emits on [projectCrcChanges];
  /// downstream consumers (the MonitorPlc batched poller in
  /// `ModbusDeviceClientAdapter`) listen on that stream so their own
  /// caches invalidate atomically with the symbol cache.
  void invalidateSymbolCacheIfProjectChanged() {
    if (!_symbolCacheBuilt) return;
    if (_projectCrc != _symbolCacheProjectCrc) {
      _log.i('UMAS symbolCache: project CRC changed '
          '(${_symbolCacheProjectCrc} -> $_projectCrc) — clearing');
      _clearSymbolCache();
    }
  }

  /// F-8: re-read memory block 0x30 to refresh [_projectCrc], then fire
  /// the invalidation chain. The CRC-watch timer drives this every
  /// [projectCrcCheckInterval]; tests can call it directly to assert
  /// deterministic invalidation behaviour.
  ///
  /// On a CRC change this method:
  ///   1. Drops the symbol cache (via [invalidateSymbolCacheIfProjectChanged]
  ///      — no-op if the cache wasn't built yet).
  ///   2. Emits the new CRC on [projectCrcChanges] so external caches
  ///      (e.g. the MonitorPlc batched table in `ModbusDeviceClientAdapter`)
  ///      can drop their state and rebuild against the fresh project.
  ///
  /// Returns true if the project CRC differed from the previous value
  /// (so the caller — typically a test — can assert the watched
  /// transition fired).
  Future<bool> refreshProjectMetadata() async {
    if (_stateValue != UmasSessionState.paired) return false;
    final before = _projectCrc;
    try {
      await _readProjectBlock();
    } catch (e) {
      _log.w('refreshProjectMetadata: _readProjectBlock failed: $e');
      return false;
    }
    final after = _projectCrc;
    if (before == after) return false;
    // Drop symbol cache (no-op if not yet built).
    invalidateSymbolCacheIfProjectChanged();
    // Always notify external listeners — the MonitorPlc table caches
    // `(blockNo, offset)` pairs that move under a fresh project even
    // if no symbol was ever looked up. Don't gate the stream on
    // `_symbolCacheBuilt`.
    if (after != null && !_projectCrcSubject.isClosed) {
      _projectCrcSubject.add(after);
    }
    return true;
  }

  /// Build the symbol cache from a full [browse]. Concurrent first-time
  /// callers wait on the same browse via [_symbolCacheLock] so multiple
  /// keys reading at startup don't fan out into N parallel browses.
  Future<void> _ensureSymbolCache() async {
    if (_symbolCacheBuilt) return;
    if (_symbolCacheLock != null) {
      await _symbolCacheLock!.future;
      return;
    }
    _symbolCacheLock = Completer<void>();
    // Avoid unhandled-async-error if no one awaits the lock.
    _symbolCacheLock!.future.ignore();
    try {
      final tree = await browse();
      _symbolCache.clear();
      void walk(UmasVariableTreeNode node) {
        if (node.variable != null && node.dataType != null) {
          _symbolCache[node.path] = ResolvedSymbol(
            path: node.path,
            variable: node.variable!,
            dataType: node.dataType!,
            readable: node.readable,
            unreadableReason: node.unreadableReason,
          );
        }
        for (final c in node.children) {
          walk(c);
        }
      }

      for (final root in tree) {
        walk(root);
      }
      _symbolCacheBuilt = true;
      _symbolCacheProjectCrc = _projectCrc;
      _log.i('UMAS symbolCache: built ${_symbolCache.length} entries '
          '(projectCrc=${_symbolCacheProjectCrc == null ? 'n/a' : '0x${_symbolCacheProjectCrc!.toRadixString(16)}'})');
      _symbolCacheLock!.complete();
    } catch (e) {
      _symbolCacheLock!.completeError(e);
      rethrow;
    } finally {
      _symbolCacheLock = null;
    }
  }

  /// Resolve a UMAS symbol path (e.g. `B_F1_RC_01_Front` or
  /// `M_Elevator.speed`) to its [ResolvedSymbol]. Triggers a one-time
  /// [browse] if the cache is empty; concurrent first-time callers share
  /// the same browse via [_ensureSymbolCache].
  ///
  /// **Case sensitivity (TD-013, v1.1.x):** Schneider M580 / M340 UMAS
  /// symbols are *case-sensitive on the wire*. Verified against live
  /// PLC at 192.168.112.159: the same byte-for-byte symbol path with
  /// different casing (`B_Elevator_F1_A` vs `b_elevator_f1_a`) returns
  /// "not found" for the lowercase variant. This is the inverse of IEC
  /// 61131-3 source-level case-insensitivity, which is enforced by the
  /// engineering tool (EcoStruxure) rather than the firmware.
  ///
  /// Operators (and LLMs generating symbol paths) frequently get the
  /// case wrong. We do a case-insensitive fallback scan on miss so the
  /// error names the correct casing instead of just "not found":
  ///
  ///   `UMAS symbol not found in data dictionary: "elevator.speed".
  ///    Did you mean "Elevator.speed"? (Schneider symbol paths are
  ///    case-sensitive on the wire.)`
  ///
  /// The fallback is O(N) in the cache size — acceptable because it
  /// only runs on the miss path. On the hit path, the existing O(1)
  /// hash lookup is unchanged.
  ///
  /// Throws [UmasException] when the symbol does not exist in the PLC's
  /// Data Dictionary (with the "did you mean" suggestion when a
  /// case-insensitive match exists).
  Future<ResolvedSymbol> lookupSymbol(String path) async {
    await _ensureSymbolCache();
    final hit = _symbolCache[path];
    if (hit != null) return hit;
    // TD-013: case-insensitive fallback — surface the correct casing
    // in the error message so the operator can fix the typo without
    // re-browsing the data dictionary manually.
    final lower = path.toLowerCase();
    String? caseSuggestion;
    for (final cachedPath in _symbolCache.keys) {
      if (cachedPath.toLowerCase() == lower) {
        caseSuggestion = cachedPath;
        break;
      }
    }
    final suffix = caseSuggestion == null
        ? ''
        : '. Did you mean "$caseSuggestion"? '
            '(Schneider symbol paths are case-sensitive on the wire.)';
    throw UmasException(
      errorCode: 0,
      message: 'UMAS symbol not found in data dictionary: "$path"$suffix',
    );
  }

  /// Read a single UMAS variable by name. Resolves via [lookupSymbol]
  /// then issues [readVariables] for one symbol. Returns the parsed
  /// typed value.
  Future<TypedVariableValue> readVariableByName(String path) async {
    final sym = await lookupSymbol(path);
    final values = await readVariables([(sym.variable, sym.dataType)]);
    if (values.isEmpty) {
      throw UmasException(
          errorCode: 0,
          message: 'UMAS readVariableByName($path) returned empty result');
    }
    return values.first;
  }

  /// Write a single UMAS variable by name. Resolves via [lookupSymbol]
  /// then issues [writeVariable] with the value encoded per the
  /// resolved data type. The [value] is encoded by [encodeVariableValue]
  /// (see umas_types.dart).
  ///
  /// F-7: refuses VAR_IN_OUT (and any other [ResolvedSymbol] with
  /// `readable == false`) client-side. The PLC would reject these with
  /// 0x94 anyway; surfacing the precise [ResolvedSymbol.unreadableReason]
  /// gives operators a clearer error than the raw protocol code, and
  /// avoids burning a round-trip on a guaranteed failure.
  Future<void> writeVariableByName(String path, dynamic value) async {
    final sym = await lookupSymbol(path);
    if (!sym.readable) {
      throw UmasException(
        errorCode: 0,
        message: 'Cannot write ${sym.path}: '
            '${sym.unreadableReason ?? "marked as not readable"}',
      );
    }
    final ref = VariableWriteRef.fromVariable(sym.variable, sym.dataType, value);
    await writeVariable([ref]);
  }

  /// Wraps [_withSession] with session recovery: on any [UmasException],
  /// resets session state so the next call re-initializes. Does NOT retry
  /// automatically — the caller must explicitly retry to avoid infinite loops.
  Future<T> _withSessionAndRecovery<T>(Future<T> Function() operation) async {
    try {
      return await _withSession(operation);
    } on UmasException {
      _handleSessionError();
      rethrow;
    }
  }

  /// Maximum number of variable references per ReadVariable request.
  /// The variableCount field is 1 byte, so max is 255 (T-05-02 mitigation).
  static const _maxReadVariableRefs = 255;

  /// Read variable values from the PLC (sub-function 0x22).
  ///
  /// Sends a ReadVariable request with the given [refs] and returns the
  /// raw concatenated response bytes. Typed parsing is the caller's
  /// responsibility (see Plan 02).
  ///
  /// Requires [readPlcStatus] to have been called first (for block CRCs).
  /// Uses [_withSessionAndRecovery] for automatic session management.
  Future<ReadVariableResult> readVariable(List<VariableReadRef> refs) async {
    return _withSessionAndRecovery(() async {
      if (_blockCrcs == null || _blockCrcs!.isEmpty) {
        throw UmasException(
          errorCode: 0,
          message: 'blockCrcs not available - call readPlcStatus() first',
        );
      }

      // Cap refs to max 255 (variableCount is 1 byte) -- T-05-02 DoS mitigation.
      // SWEEP-05 (v1.1): warn when truncation drops refs so callers see the
      // truncation in operator logs instead of only via a returned-shorter
      // ReadVariableResult.
      final cappedRefs = refs.length > _maxReadVariableRefs
          ? refs.sublist(0, _maxReadVariableRefs)
          : refs;
      if (refs.length > _maxReadVariableRefs) {
        _log.w('UMAS readVariable: truncated request from ${refs.length} to '
            '$_maxReadVariableRefs refs (cap is 1 byte). '
            '${refs.length - _maxReadVariableRefs} refs were NOT read.');
      }

      // Build payload: crc(4 LE) + count(1) + [ref.toBytes()]*
      // Per PLC4X reference driver, the CRC is the project-level CRC from
      // memory block 0x30 (hash1+hash2). Falls back to blockCrcs[0] for
      // legacy stub-server compatibility when the project CRC is absent.
      final buffer = BytesBuilder();
      final crcData = ByteData(4);
      crcData.setUint32(
          0, _projectCrc ?? _blockCrcs![0], Endian.little);
      buffer.add(crcData.buffer.asUint8List());
      buffer.addByte(cappedRefs.length);
      for (final ref in cappedRefs) {
        buffer.add(ref.toBytes());
      }

      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readVariable.code,
        pairingKey: _pairingKey,
        payload: Uint8List.fromList(buffer.toBytes()),
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS readVariable failed: ${code.name}',
        );
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS readVariable response',
        );
      }

      _checkStatus(pdu, 'readVariable');

      return ReadVariableResult(rawBytes: pdu.sublist(3));
    });
  }

  /// Read typed variable values from the PLC.
  ///
  /// Accepts pairs of ([UmasVariable], [UmasDataTypeRef]) from the data
  /// dictionary. Builds [VariableReadRef] instances, sends a single
  /// ReadVariable (0x22) request, and parses the raw response bytes into
  /// typed Dart values using [parseVariableValues].
  ///
  /// Returns a list of [TypedVariableValue] with correctly typed values
  /// (int, double, bool, String) matching the order of the input pairs.
  ///
  /// For array variables (classIdentifier == 4), the [VariableReadRef] is
  /// automatically constructed with isArray=true and the computed arrayLength.
  Future<List<TypedVariableValue>> readVariables(
      List<(UmasVariable, UmasDataTypeRef)> variables) async {
    // If M580 already detected, go directly to MonitorPlc (0x50).
    // Reset registrations first to avoid accumulating stale entries
    // from previous calls with different variable sets.
    if (_useMonitorPlc) {
      await monitorReset();
      return monitorRegisterAndRead(variables);
    }

    try {
      // M340 path: use ReadVariable (0x22)
      final refs = <VariableReadRef>[];
      final types = <UmasDataTypeRef>[];
      for (final (variable, dataType) in variables) {
        refs.add(VariableReadRef.fromVariable(variable, dataType));
        types.add(dataType);
      }
      final result = await readVariable(refs);
      return parseVariableValues(result.rawBytes, types);
    } on UmasException catch (e) {
      if (e.errorCode == 0xA1) {
        // M580 detected: 0x22 returns 0xA1A1 error
        _useMonitorPlc = true;
        return monitorRegisterAndRead(variables);
      }
      rethrow;
    }
  }

  /// Maximum number of variable references per WriteVariable request.
  /// The variableCount field is 1 byte, so max is 255 (T-06-05 mitigation).
  static const _maxWriteVariableRefs = 255;

  /// Write variable values to the PLC (sub-function 0x23).
  ///
  /// Sends a WriteVariable request with the given [refs]. Each ref contains
  /// the variable address and the data bytes to write.
  ///
  /// Requires [readPlcStatus] to have been called first (for block CRCs).
  /// Uses [_withSessionAndRecovery] for automatic session management.
  Future<void> writeVariable(List<VariableWriteRef> refs) async {
    return _withSessionAndRecovery(() async {
      if (_blockCrcs == null || _blockCrcs!.isEmpty) {
        throw UmasException(
          errorCode: 0,
          message: 'blockCrcs not available - call readPlcStatus() first',
        );
      }

      // Cap refs to max 255 (variableCount is 1 byte) -- T-06-05 DoS mitigation.
      // SWEEP-05 (v1.1): warn when truncation drops refs so callers see the
      // silent data loss in operator logs instead of treating the Future
      // resolution as success-for-all.
      final cappedRefs = refs.length > _maxWriteVariableRefs
          ? refs.sublist(0, _maxWriteVariableRefs)
          : refs;
      if (refs.length > _maxWriteVariableRefs) {
        _log.w('UMAS writeVariable: truncated request from ${refs.length} to '
            '$_maxWriteVariableRefs refs (cap is 1 byte). '
            '${refs.length - _maxWriteVariableRefs} refs were NOT written.');
      }

      // Build payload: crc(4 LE) + count(1) + [ref.toBytes()]*
      // See readVariable for projectCrc rationale.
      final buffer = BytesBuilder();
      final crcData = ByteData(4);
      crcData.setUint32(
          0, _projectCrc ?? _blockCrcs![0], Endian.little);
      buffer.add(crcData.buffer.asUint8List());
      buffer.addByte(cappedRefs.length);
      for (final ref in cappedRefs) {
        buffer.add(ref.toBytes());
      }

      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.writeVariable.code,
        pairingKey: _pairingKey,
        payload: Uint8List.fromList(buffer.toBytes()),
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS writeVariable failed: ${code.name}',
        );
      }

      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS writeVariable response',
        );
      }

      _checkStatus(pdu, 'writeVariable');
    });
  }

  /// Write typed variable values to the PLC.
  ///
  /// Accepts triples of ([UmasVariable], [UmasDataTypeRef], value) from the
  /// data dictionary. Builds [VariableWriteRef] instances and sends a single
  /// WriteVariable (0x23) request.
  Future<void> writeVariables(
      List<(UmasVariable, UmasDataTypeRef, dynamic)> variables) async {
    final refs = <VariableWriteRef>[];
    for (final (variable, dataType, value) in variables) {
      refs.add(VariableWriteRef.fromVariable(variable, dataType, value));
    }
    await writeVariable(refs);
  }

  // ---------------------------------------------------------------------------
  // ReadCoilsRegisters (0x24) / WriteCoilsRegisters (0x25)
  // ---------------------------------------------------------------------------

  /// Read coils or registers directly by address (sub-function 0x24).
  ///
  /// Provides direct %M/%MW/%S/%SW access without the data dictionary.
  /// NOTE: Wire format is best-effort (PLC4X marks as opaque bytes).
  /// If the assumed format is wrong, use [readCoilsRegistersRaw]
  /// with a manually constructed payload.
  Future<CoilsRegistersResult> readCoilsRegisters(RegisterAddress address) async {
    return _withSessionAndRecovery(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readCoilsRegisters.code,
        pairingKey: _pairingKey,
        payload: address.toBytes(),
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS readCoilsRegisters failed: ${code.name}',
        );
      }
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS readCoilsRegisters response',
        );
      }
      _checkStatus(pdu, 'readCoilsRegisters');
      return CoilsRegistersResult(rawBytes: pdu.sublist(3));
    });
  }

  /// Read coils/registers with a raw payload (sub-function 0x24).
  ///
  /// Use this if the assumed RegisterAddress format does not work
  /// with your PLC. Pass the raw UMAS payload bytes directly.
  Future<CoilsRegistersResult> readCoilsRegistersRaw(Uint8List payload) async {
    return _withSessionAndRecovery(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.readCoilsRegisters.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS readCoilsRegistersRaw failed: ${code.name}',
        );
      }
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS readCoilsRegistersRaw response',
        );
      }
      _checkStatus(pdu, 'readCoilsRegistersRaw');
      return CoilsRegistersResult(rawBytes: pdu.sublist(3));
    });
  }

  /// Write coils or registers directly by address (sub-function 0x25).
  ///
  /// IMPORTANT: Assumes write reservation (0x10) is required, same as 0x23.
  /// Call within [withReservation] to ensure proper reservation lifecycle.
  ///
  /// [data] must contain the correct number of bytes for the register
  /// type and quantity (see [RegisterAddress.expectedDataBytes]).
  ///
  /// NOTE: Wire format is best-effort (PLC4X marks as opaque bytes).
  Future<void> writeCoilsRegisters(RegisterAddress address, Uint8List data) async {
    return _withSessionAndRecovery(() async {
      final expectedLen = address.expectedDataBytes;
      if (data.length != expectedLen) {
        throw UmasException(
          errorCode: 0,
          message: 'writeCoilsRegisters: data length ${data.length} '
              'does not match expected $expectedLen bytes for '
              '${address.type.name} x${address.quantity}',
        );
      }
      final payloadBuilder = BytesBuilder();
      payloadBuilder.add(address.toBytes());
      payloadBuilder.add(data);

      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.writeCoilsRegisters.code,
        pairingKey: _pairingKey,
        payload: Uint8List.fromList(payloadBuilder.toBytes()),
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS writeCoilsRegisters failed: ${code.name}',
        );
      }
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS writeCoilsRegisters response',
        );
      }
      _checkStatus(pdu, 'writeCoilsRegisters');
    });
  }

  /// Write coils/registers with a raw payload (sub-function 0x25).
  Future<void> writeCoilsRegistersRaw(Uint8List payload) async {
    return _withSessionAndRecovery(() async {
      final request = UmasRequest(
        umasSubFunction: UmasSubFunction.writeCoilsRegisters.code,
        pairingKey: _pairingKey,
        payload: payload,
        unitId: unitId,
      );
      final code = await sendFn(request);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS writeCoilsRegistersRaw failed: ${code.name}',
        );
      }
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS writeCoilsRegistersRaw response',
        );
      }
      _checkStatus(pdu, 'writeCoilsRegistersRaw');
    });
  }

  // ---------------------------------------------------------------------------
  // MonitorPlc (0x50) sub-operations
  // ---------------------------------------------------------------------------

  /// Send a MonitorPlc (0x50) request with the given [payload].
  ///
  /// Returns the response payload bytes (after the 3-byte UMAS header).
  Future<Uint8List> _sendMonitorPlc(Uint8List payload) async {
    final request = UmasRequest(
      umasSubFunction: UmasSubFunction.monitorPlc.code,
      pairingKey: _pairingKey,
      payload: payload,
      unitId: unitId,
    );
    final code = await sendFn(request);
    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
        errorCode: code.code,
        message: 'UMAS monitorPlc failed: ${code.name}',
      );
    }
    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 3) {
      throw UmasException(
        errorCode: 0,
        message: 'Empty UMAS monitorPlc response',
      );
    }
    _checkStatus(pdu, 'monitorPlc');
    return pdu.sublist(3);
  }

  /// Register variables for monitoring via MonitorPlc Register (0x05).
  ///
  /// Assigns variable indices sequentially and registers each variable's
  /// data type in the local registration table for response parsing.
  /// Returns the assigned variable indices.
  Future<List<int>> monitorRegister(
      List<(UmasVariable, UmasDataTypeRef)> variables) async {
    return _withSessionAndRecovery(() async {
      final indices = <int>[];
      final buffer = BytesBuilder();
      buffer.addByte(0x05); // subCommand: Register
      buffer.addByte(0x00); // unknown
      buffer.addByte(variables.length & 0xFF); // numberOfSubOps

      for (final (variable, _) in variables) {
        final idx = _monitorTable.allocateIndex();
        indices.add(idx);
        final ref = MonitorPlcRef.fromVariable(idx, variable);
        buffer.add(ref.toRegisterBytes());
      }

      await _sendMonitorPlc(Uint8List.fromList(buffer.toBytes()));

      // On success, register types in local table
      for (int i = 0; i < variables.length; i++) {
        _monitorTable.register(indices[i], variables[i].$2);
      }

      return indices;
    });
  }

  /// Read all registered variable values via MonitorPlc ReadAll (0x07).
  ///
  /// Returns parsed typed values using the registration table.
  /// Returns empty list if no variables are registered.
  Future<List<TypedVariableValue>> monitorReadAll() async {
    return _withSessionAndRecovery(() async {
      if (_monitorTable.isEmpty) return [];

      final responseBytes =
          await _sendMonitorPlc(Uint8List.fromList([0x07]));
      return _monitorTable.parseReadAllResponse(responseBytes);
    });
  }

  /// Register variables and immediately read their values via
  /// MonitorPlc RegisterAndRead (0x09).
  ///
  /// Registers in the local table AND parses the response.
  Future<List<TypedVariableValue>> monitorRegisterAndRead(
      List<(UmasVariable, UmasDataTypeRef)> variables) async {
    return _withSessionAndRecovery(() async {
      final indices = <int>[];
      final types = <UmasDataTypeRef>[];
      final buffer = BytesBuilder();
      buffer.addByte(0x09); // subCommand: RegisterAndRead
      buffer.addByte(0x00); // unknown
      buffer.addByte(variables.length & 0xFF); // numberOfSubOps

      for (final (variable, dataType) in variables) {
        final idx = _monitorTable.allocateIndex();
        indices.add(idx);
        types.add(dataType);
        final ref = MonitorPlcRef.fromVariable(idx, variable);
        buffer.add(ref.toRegisterAndReadBytes());
      }

      final responseBytes =
          await _sendMonitorPlc(Uint8List.fromList(buffer.toBytes()));

      // Register types in local table on success
      for (int i = 0; i < variables.length; i++) {
        _monitorTable.register(indices[i], types[i]);
      }

      // Parse response using the just-registered types
      return _monitorTable.parseReadAllResponse(responseBytes);
    });
  }

  /// Reset all MonitorPlc registrations via MonitorPlc Reset (0x0B).
  ///
  /// Clears both server-side and local registration state.
  Future<void> monitorReset() async {
    return _withSessionAndRecovery(() async {
      await _sendMonitorPlc(Uint8List.fromList([0x0B]));
      _monitorTable.reset();
    });
  }

  // ---------------------------------------------------------------------------
  // Diagnostic sub-functions (0x06, 0x20, 0x39, 0x58, 0x70, 0x73)
  // ---------------------------------------------------------------------------

  /// Send a diagnostic request with no payload and return raw response bytes.
  ///
  /// Shared helper for simple diagnostic sub-functions that take no input
  /// and return opaque raw bytes (readCardInfo, readEthMasterData, checkPlc,
  /// getStatusModule, readIoObject).
  Future<Uint8List> _sendDiagnostic(UmasSubFunction subFunc) async {
    final request = UmasRequest(
      umasSubFunction: subFunc.code,
      pairingKey: _pairingKey,
      unitId: unitId,
    );
    final code = await sendFn(request);
    if (code != ModbusResponseCode.requestSucceed) {
      throw UmasException(
        errorCode: code.code,
        message: 'UMAS ${subFunc.name} failed: ${code.name}',
      );
    }
    final pdu = request.responsePdu;
    if (pdu == null || pdu.length < 3) {
      throw UmasException(
        errorCode: 0,
        message: 'Empty UMAS ${subFunc.name} response',
      );
    }
    _checkStatus(pdu, subFunc.name);
    return pdu.sublist(3);
  }

  /// Read SD card status (sub-function 0x06).
  ///
  /// Returns raw response bytes containing card presence, capacity, and free space.
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<CardInfoResult> readCardInfo() async {
    return _withSession(() async {
      final rawData = await _sendDiagnostic(UmasSubFunction.readCardInfo);
      return CardInfoResult(rawData: rawData);
    });
  }

  /// Read raw memory block (sub-function 0x20).
  ///
  /// Sends a structured [ReadMemoryBlockRequest] and returns a parsed
  /// [ReadMemoryBlockResult] with range, numberOfBytes, and data fields.
  /// Validates response numberOfBytes against available data (T-09-01).
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<ReadMemoryBlockResult> readMemoryBlock(
      ReadMemoryBlockRequest request) async {
    return _withSession(() async {
      final umasRequest = UmasRequest(
        umasSubFunction: UmasSubFunction.readMemoryBlock.code,
        pairingKey: _pairingKey,
        payload: request.toBytes(),
        unitId: unitId,
      );
      final code = await sendFn(umasRequest);
      if (code != ModbusResponseCode.requestSucceed) {
        throw UmasException(
          errorCode: code.code,
          message: 'UMAS readMemoryBlock failed: ${code.name}',
        );
      }
      final pdu = umasRequest.responsePdu;
      if (pdu == null || pdu.length < 3) {
        throw UmasException(
          errorCode: 0,
          message: 'Empty UMAS readMemoryBlock response',
        );
      }
      _checkStatus(pdu, 'readMemoryBlock');
      return ReadMemoryBlockResult.fromPayload(pdu.sublist(3));
    });
  }

  /// Read network topology (sub-function 0x39).
  ///
  /// Returns raw response bytes containing Ethernet master/module data.
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<EthMasterDataResult> readEthMasterData() async {
    return _withSession(() async {
      final rawData = await _sendDiagnostic(UmasSubFunction.readEthMasterData);
      return EthMasterDataResult(rawData: rawData);
    });
  }

  /// Verify PLC health (sub-function 0x58).
  ///
  /// Returns raw response bytes indicating PLC health status.
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<CheckPlcResult> checkPlc() async {
    return _withSession(() async {
      final rawData = await _sendDiagnostic(UmasSubFunction.checkPlc);
      return CheckPlcResult(rawData: rawData);
    });
  }

  /// Read I/O module data (sub-function 0x70).
  ///
  /// Returns raw response bytes containing I/O object information.
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<IoObjectResult> readIoObject() async {
    return _withSession(() async {
      final rawData = await _sendDiagnostic(UmasSubFunction.readIoObject);
      return IoObjectResult(rawData: rawData);
    });
  }

  /// Read per-module status (sub-function 0x73).
  ///
  /// Returns raw response bytes containing module status information.
  /// Uses [_withSession] to auto-initialize if not yet paired.
  Future<StatusModuleResult> getStatusModule() async {
    return _withSession(() async {
      final rawData = await _sendDiagnostic(UmasSubFunction.getStatusModule);
      return StatusModuleResult(rawData: rawData);
    });
  }

  /// Convenience method: ensures session -> readDataTypes -> readVariableNames -> buildVariableTree.
  /// This is the primary entry point for the browse dialog.
  ///
  /// When DD03 (data type table) is available, each top-level variable whose
  /// type is a STRUCT (classId=2) or FB (classId=7) is recursively expanded
  /// into its members, OPC-UA-style. Each leaf [UmasVariable] has its
  /// `blockNo` and `offset` set so that [readVariables] can read it directly.
  ///
  /// Data types (DD03) are optional. If the PLC rejects DD03, top-level
  /// variables are still returned but struct members are not expanded.
  Future<List<UmasVariableTreeNode>> browse({int maxDepth = 6}) async {
    return _withSessionAndRecovery(() async {
      List<UmasDataTypeRef> dataTypes;
      try {
        dataTypes = await _readDataTypesInner();
      } on UmasException catch (e) {
        _log.w('Data dictionary types (DD03) unavailable: ${e.message} '
            '— browsing without struct expansion');
        dataTypes = [];
      }
      final variables = await _readVariableNamesInner();

      if (dataTypes.isEmpty) {
        return buildVariableTree(variables, dataTypes);
      }

      // First, dot-split top-level variable names (CodeSys style: e.g.
      // "Application.GVL.temperature") into folder nodes. Then expand any
      // leaf that resolves to a struct/FB type into its members.
      //
      // B-3 (v1.1.x): the member / array caches are hoisted to per-client
      // lifetime (`_persistentMemberCache`, `_persistentArrayCache`) so
      // back-to-back browses don't reissue DD02 for the same custom
      // type id. Per-browse aliases below preserve the inner-API names.
      final memberCache = _persistentMemberCache;
      final arrayCache = _persistentArrayCache;
      final builder = _TreeBuilder();
      for (final v in variables) {
        builder.insert(v, dataTypes);
      }
      final flatRoots = builder.build();
      return [
        for (final root in flatRoots)
          await _expandTreeNode(
            node: root,
            dataTypes: dataTypes,
            memberCache: memberCache,
            arrayCache: arrayCache,
            depth: 0,
            maxDepth: maxDepth,
          ),
      ];
    });
  }

  /// Walk an existing dot-split tree node and expand any struct/FB leaf into
  /// its members. Folder nodes are recursed into; non-struct leaves are kept
  /// as-is.
  Future<UmasVariableTreeNode> _expandTreeNode({
    required UmasVariableTreeNode node,
    required List<UmasDataTypeRef> dataTypes,
    required Map<int, List<UmasVariable>> memberCache,
    required Map<int, UmasArrayTypeDefinition?> arrayCache,
    required int depth,
    required int maxDepth,
  }) async {
    if (node.children.isNotEmpty) {
      // Folder: recurse into children, leave structure as-is.
      final newChildren = <UmasVariableTreeNode>[];
      for (final child in node.children) {
        newChildren.add(await _expandTreeNode(
          node: child,
          dataTypes: dataTypes,
          memberCache: memberCache,
          arrayCache: arrayCache,
          depth: depth,
          maxDepth: maxDepth,
        ));
      }
      return UmasVariableTreeNode(
        name: node.name,
        path: node.path,
        children: newChildren,
        variable: node.variable,
        dataType: node.dataType,
      );
    }
    if (node.variable == null) return node;
    final expanded = await _expandVariable(
      variable: node.variable!,
      path: node.path,
      dataTypes: dataTypes,
      memberCache: memberCache,
      arrayCache: arrayCache,
      depth: depth,
      maxDepth: maxDepth,
    );
    // Preserve the leaf-only name from the dot-tree builder (e.g. "temperature"
    // rather than the full dotted "Application.GVL.temperature").
    return UmasVariableTreeNode(
      name: node.name,
      path: expanded.path,
      children: expanded.children,
      variable: expanded.variable,
      dataType: expanded.dataType,
    );
  }

  /// Recursively expand a variable into its struct/FB members or array elements.
  ///
  /// plc4j(UmasProtocolLogic.java:1079-1097, 1130-1146): for any custom-type
  /// reference whose `classIdentifier != 0`, plc4j issues a DD02 request keyed
  /// on the type's index (NOT 0xFFFF) and discriminates on the first response
  /// byte. `classId == 0x04` ⇒ UmasArrayTypeDefinition; anything else ⇒
  /// UmasPDUReadUmasUDTDefinitionResponse (member records). We extend this
  /// gate to ALSO fire for variables whose `dataTypeId` did not appear in
  /// DD03 at all — the live M580 at 192.168.112.159 omits FB types from DD03
  /// even though their UDT bodies are accessible via DD02-on-typeIndex. plc4j
  /// strictly gates on the non-zero classIdentifier of a *resolved* DD03
  /// record and would silently drop these FB instances; we resolve
  /// speculatively to surface them. See `.planning/phases/02-fb-visibility-bug-b-core/02-RESEARCH.md`.
  Future<UmasVariableTreeNode> _expandVariable({
    required UmasVariable variable,
    required String path,
    required List<UmasDataTypeRef> dataTypes,
    required Map<int, List<UmasVariable>> memberCache,
    required Map<int, UmasArrayTypeDefinition?> arrayCache,
    required int depth,
    required int maxDepth,
  }) async {
    UmasDataTypeRef? type =
        UmasDataTypes.resolve(variable.dataTypeId, dataTypes);
    bool isStructOrFb = type != null &&
        (type.classIdentifier == 2 || type.classIdentifier == 7);
    bool isArray = type != null && type.classIdentifier == 4;

    // Speculative FB / UDT resolution for variables whose type was not
    // enumerated in DD03 and is not a built-in scalar. Mirrors plc4j
    // `parseCustomTypeBlock`'s classId discriminator (UmasProtocolLogic.java:1130-1146):
    // the first byte of the DD02-on-typeIndex response selects between
    // UmasArrayTypeDefinition (0x04) and UmasPDUReadUmasUDTDefinitionResponse
    // (anything else, including FB instances).
    final isCandidateForSpeculativeResolve = type == null &&
        depth < maxDepth &&
        variable.dataTypeId != 0 &&
        !UmasDataTypes.builtIn.containsKey(variable.dataTypeId);
    if (isCandidateForSpeculativeResolve) {
      // Honour caches before reissuing network I/O. A non-null entry in
      // arrayCache means a previous resolve discovered an array def;
      // a non-empty entry in memberCache means an FB/UDT body.
      final cachedArray = arrayCache[variable.dataTypeId];
      final cachedMembers = memberCache[variable.dataTypeId];
      if (cachedArray != null) {
        isArray = true;
        type = UmasDataTypeRef(
          id: variable.dataTypeId,
          name: '?',
          byteSize: 0,
          classIdentifier: 4,
          dataType: cachedArray.elementTypeId,
        );
      } else if (cachedMembers != null && cachedMembers.isNotEmpty) {
        isStructOrFb = true;
        type = UmasDataTypeRef(
          id: variable.dataTypeId,
          name: 'FB',
          byteSize: 0,
          classIdentifier: 7,
          dataType: variable.dataTypeId,
        );
      } else if (cachedMembers == null && !arrayCache.containsKey(variable.dataTypeId)) {
        // No cache entry either way — fire the speculative DD02 once.
        try {
          final raw = await readDD02Raw(variable.dataTypeId);
          final asArray = UmasArrayTypeDefinition.tryParse(raw);
          if (asArray != null) {
            arrayCache[variable.dataTypeId] = asArray;
            isArray = true;
            // Synthesize a minimal array-class type so the existing
            // array branch can pick it up. byteSize 0 disables the
            // total-bytes / element-count derivation; the array branch
            // will degrade gracefully to a children-less node when
            // byteSize <= 0 (already handled at L1917).
            type = UmasDataTypeRef(
              id: variable.dataTypeId,
              name: '?',
              byteSize: 0,
              classIdentifier: 4,
              dataType: asArray.elementTypeId,
            );
          } else {
            // Reissue via _readDD02Block(isMemberLayout: true) so the
            // response is parsed through the shared
            // _parseVariableRecords code path — same wire layout as
            // plc4j's UmasPDUReadUmasUDTDefinitionResponse / UmasUDTDefinition.
            // Speculative-resolved types that aren't arrays are treated
            // as FBs (classId=7) — see the synthesized type below — so
            // direction classification fires for their members.
            final members = await _readDD02Block(
                blockNo: variable.dataTypeId,
                isMemberLayout: true,
                parentClassId: 7);
            memberCache[variable.dataTypeId] = members;
            if (members.isNotEmpty) {
              isStructOrFb = true;
              type = UmasDataTypeRef(
                id: variable.dataTypeId,
                name: 'FB',
                byteSize: 0,
                classIdentifier: 7,
                dataType: variable.dataTypeId,
              );
            }
            // Empty member list ⇒ leaf (observed on M580 for
            // M_Elevator typeId 0xb6, where the PLC returns a single
            // byte 0x00 — firmware-dependent). The cached empty list
            // prevents per-instance retry.
          }
        } on UmasException catch (e) {
          _log.w('Speculative DD02 resolution failed for type '
              '0x${variable.dataTypeId.toRadixString(16)}: ${e.message}');
          // Cache empty so other instances of this type don't retry.
          memberCache[variable.dataTypeId] = const [];
        }
      }
    }

    if (depth >= maxDepth || (!isStructOrFb && !isArray)) {
      return UmasVariableTreeNode(
        name: variable.name,
        path: path,
        children: const [],
        variable: variable,
        dataType: type,
      );
    }

    // Past the gate, `isStructOrFb || isArray` holds, which is only set
    // when `type` is non-null (either via DD03 resolve or via the
    // speculative DD02 branch above). Pin a local non-null view so the
    // downstream branches keep working without a sea of `!` operators.
    final resolvedType = type!;

    if (isArray) {
      // Fetch the array type definition (PLC4X UmasArrayTypeDefinition) by
      // querying DD02 for the array's data-type id. The DD03 record's
      // `dataType` byte points at the array type itself, not the element,
      // so we need the explicit definition to recover the real elementTypeId
      // and dimension bounds.
      UmasArrayTypeDefinition? arrayDef;
      if (arrayCache.containsKey(variable.dataTypeId)) {
        arrayDef = arrayCache[variable.dataTypeId];
      } else {
        try {
          final raw = await readDD02Raw(variable.dataTypeId);
          arrayDef = UmasArrayTypeDefinition.tryParse(raw);
        } on UmasException catch (e) {
          _log.w('Array DD02 fetch failed for type ${resolvedType.name}: ${e.message}');
          arrayDef = null;
        }
        arrayCache[variable.dataTypeId] = arrayDef;
      }

      final totalElements = arrayDef?.totalElementCount ?? 0;
      if (arrayDef == null ||
          totalElements <= 0 ||
          totalElements > _maxArrayElements ||
          resolvedType.byteSize <= 0) {
        return UmasVariableTreeNode(
          name: variable.name,
          path: path,
          children: const [],
          variable: variable,
          dataType: type,
        );
      }

      // Element size derived from total array byte size (works for arrays of
      // builtin scalars, UDTs, and atypically-sized strings alike).
      final elementSize = resolvedType.byteSize ~/ totalElements;
      if (elementSize <= 0) {
        return UmasVariableTreeNode(
          name: variable.name,
          path: path,
          children: const [],
          variable: variable,
          dataType: type,
        );
      }

      final children = <UmasVariableTreeNode>[];
      // Use the element's natural index range from the first dimension when
      // the array is 1D (so e.g. ARRAY[1..100] surfaces [1]..[100], matching
      // the PLC's symbolic addressing). For multi-dim arrays, fall back to a
      // flat zero-based index — operators rarely encounter these and the path
      // notation is unambiguous.
      final useNaturalIndex = arrayDef.dimensions.length == 1;
      final start = useNaturalIndex ? arrayDef.dimensions.first.startIndex : 0;

      // STRING in the built-in table is hardcoded at 256 bytes, but Schneider
      // PLCs store STRING(N) with N typically much smaller (e.g. 16 inside an
      // ARRAY OF STRING(16)). The array layout's per-element size is
      // authoritative — synthesize an element-typed ref whose byteSize matches
      // the actual on-wire size so the read clamp and parser agree.
      // Resolve the element type. Built-ins and DD03 custom types both go
      // through `UmasDataTypes.resolve`. STRING is hardcoded at 256 bytes in
      // the built-in table but Schneider PLCs commonly emit STRING(N) inside
      // arrays — when the layout-derived size disagrees with the built-in,
      // synthesize a ref keyed on the built-in's name with the actual size.
      UmasDataTypeRef? resolvedElementType =
          UmasDataTypes.resolve(arrayDef.elementTypeId, dataTypes);
      final builtin = UmasDataTypes.builtIn[arrayDef.elementTypeId];
      if (builtin != null && resolvedElementType?.byteSize != elementSize) {
        resolvedElementType = UmasDataTypeRef(
          id: builtin.id,
          name: builtin.name,
          byteSize: elementSize,
          classIdentifier: builtin.classIdentifier,
          dataType: builtin.dataType,
        );
      }
      resolvedElementType ??= UmasDataTypeRef(
          id: arrayDef.elementTypeId, name: '?', byteSize: elementSize);

      for (int i = 0; i < totalElements; i++) {
        final displayIndex = start + i;
        final elementVar = UmasVariable(
          name: '[$displayIndex]',
          blockNo: variable.blockNo,
          offset: variable.offset + i * elementSize,
          dataTypeId: arrayDef.elementTypeId,
        );
        // For built-in scalar elements with size override (STRING(N), etc.),
        // emit the leaf directly; otherwise recurse so structs/arrays expand.
        final isCustom = builtin == null;
        if (isCustom) {
          children.add(await _expandVariable(
            variable: elementVar,
            path: '$path[$displayIndex]',
            dataTypes: dataTypes,
            memberCache: memberCache,
            arrayCache: arrayCache,
            depth: depth + 1,
            maxDepth: maxDepth,
          ));
        } else {
          children.add(UmasVariableTreeNode(
            name: '[$displayIndex]',
            path: '$path[$displayIndex]',
            children: const [],
            variable: elementVar,
            dataType: resolvedElementType,
          ));
        }
      }

      // Keep the array variable on the parent node so callers can still issue
      // a whole-array read via readVariables; the per-element children expose
      // individual addresses for OPC-UA-style browsing.
      return UmasVariableTreeNode(
        name: variable.name,
        path: path,
        children: children,
        variable: variable,
        dataType: type,
      );
    }

    // Fetch struct member layout (cached per typeId). Forward
    // resolvedType.classIdentifier so the per-member direction
    // classifier only fires for FB members (classId=7) and NOT for
    // arbitrary UDT struct fields (classId=2). F-1 v1.1.
    List<UmasVariable> members;
    try {
      members = memberCache.putIfAbsent(
          variable.dataTypeId, () => <UmasVariable>[]);
      if (members.isEmpty) {
        memberCache[variable.dataTypeId] = members = await _readDD02Block(
            blockNo: variable.dataTypeId,
            isMemberLayout: true,
            parentClassId: resolvedType.classIdentifier);
      }
    } on UmasException catch (e) {
      _log.w('Struct expansion failed for type ${resolvedType.name}: ${e.message}');
      return UmasVariableTreeNode(
        name: variable.name,
        path: path,
        children: const [],
        variable: variable,
        dataType: type,
      );
    }

    final children = <UmasVariableTreeNode>[];
    for (final m in members) {
      // For struct members, the parser puts the byte-offset-within-parent
      // into `blockNo`. Compute the member's absolute address by combining
      // it with the parent's address.
      // Phase 3 (v1.1): forward the member's `direction` so the tree node
      // can render input/output/public/in_out distinctly. `m.direction` is
      // populated by `_parseVariableRecords` when `isMemberLayout == true`
      // (null for non-FB struct members).
      final memberAddr = UmasVariable(
        name: m.name,
        blockNo: variable.blockNo,
        offset: variable.offset + m.blockNo,
        dataTypeId: m.dataTypeId,
        direction: m.direction,
      );
      final childNode = await _expandVariable(
        variable: memberAddr,
        path: '$path.${m.name}',
        dataTypes: dataTypes,
        memberCache: memberCache,
        arrayCache: arrayCache,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      // Surface direction on the tree node so downstream consumers
      // (browser tree, CLI --show-direction) can read it without
      // peeking into UmasVariable. `_expandVariable` doesn't carry the
      // direction parameter; rebuild the node with the direction attached.
      // F-5 wiring: VAR_IN_OUT members are pointer-backed (PLC returns
      // 0x94 on read); mark them unreadable with a human-readable reason
      // so the UI renders the "not readable" affordance instead of
      // silently dropping them.
      final dir = m.direction;
      final readable = dir == null ? true : isReadableForDirection(dir);
      final unreadableReason =
          dir == null ? null : unreadableReasonForDirection(dir);
      children.add(UmasVariableTreeNode(
        name: childNode.name,
        path: childNode.path,
        children: childNode.children,
        variable: childNode.variable,
        dataType: childNode.dataType,
        direction: dir,
        readable: readable,
        unreadableReason: unreadableReason,
      ));
    }

    return UmasVariableTreeNode(
      name: variable.name,
      path: path,
      children: children,
      variable: variable,
      dataType: type,
    );
  }
}

/// Internal helper for building the variable tree from flat paths.
class _TreeBuilderNode {
  final String name;
  final String path;
  final Map<String, _TreeBuilderNode> children = {};
  UmasVariable? variable;
  UmasDataTypeRef? dataType;

  _TreeBuilderNode(this.name, this.path);

  UmasVariableTreeNode toTreeNode() {
    return UmasVariableTreeNode(
      name: name,
      path: path,
      children: children.values.map((c) => c.toTreeNode()).toList(),
      variable: variable,
      dataType: dataType,
    );
  }
}

class _TreeBuilder {
  final Map<String, _TreeBuilderNode> roots = {};

  void insert(UmasVariable v, List<UmasDataTypeRef> dataTypes) {
    final parts = v.name.split('.');
    var currentLevel = roots;
    var pathSoFar = '';

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      pathSoFar = pathSoFar.isEmpty ? part : '$pathSoFar.$part';
      final isLeaf = (i == parts.length - 1);

      currentLevel.putIfAbsent(part, () => _TreeBuilderNode(part, pathSoFar));
      final node = currentLevel[part]!;

      if (isLeaf) {
        node.variable = v;
        node.dataType = UmasDataTypes.resolve(v.dataTypeId, dataTypes);
      } else {
        currentLevel = node.children;
      }
    }
  }

  List<UmasVariableTreeNode> build() {
    return roots.values.map((n) => n.toTreeNode()).toList();
  }
}
