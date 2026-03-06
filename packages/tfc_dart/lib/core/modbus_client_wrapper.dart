import 'dart:async';

import 'package:logger/logger.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:rxdart/rxdart.dart';

import 'state_man.dart' show ConnectionStatus;

// =============================================================================
// Data types and configuration classes
// =============================================================================

/// Supported Modbus data type interpretations for register values.
enum ModbusDataType {
  bit,
  int16,
  uint16,
  int32,
  uint32,
  float32,
  int64,
  uint64,
  float64,
}

/// Immutable configuration for a single Modbus register subscription.
///
/// Each spec describes which register to read, how to interpret its bytes,
/// and which poll group controls its read interval.
class ModbusRegisterSpec {
  final String key;
  final ModbusElementType registerType;
  final int address;
  final ModbusDataType dataType;
  final String pollGroup;

  const ModbusRegisterSpec({
    required this.key,
    required this.registerType,
    required this.address,
    this.dataType = ModbusDataType.uint16,
    this.pollGroup = 'default',
  });
}

// =============================================================================
// Internal subscription and poll group classes
// =============================================================================

/// Holds the runtime state for a single subscribed register.
class _RegisterSubscription {
  final ModbusRegisterSpec spec;
  final ModbusElement element;
  final BehaviorSubject<Object?> value$;

  _RegisterSubscription({
    required this.spec,
    required this.element,
  }) : value$ = BehaviorSubject<Object?>();

  Object? get currentValue => value$.valueOrNull;
  Stream<Object?> get stream => value$.stream;
}

/// A named group of register subscriptions polled at a common interval.
class _PollGroup {
  final String name;
  final Duration interval;
  final Duration? responseTimeout;
  Timer? _timer;
  final List<_RegisterSubscription> _subscriptions = [];
  bool _pollInProgress = false;

  _PollGroup({
    required this.name,
    required this.interval,
    this.responseTimeout,
  });

  void start(Future<void> Function() pollCallback) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      await pollCallback();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

// =============================================================================
// ModbusClientWrapper
// =============================================================================

/// Wraps [ModbusClientTcp] with persistent connection lifecycle management:
/// auto-reconnect with exponential backoff, BehaviorSubject status streaming,
/// connect/disconnect/dispose lifecycle, and factory injection for testability.
///
/// Phase 5 extension: poll-based reading of all four Modbus register types
/// (coils FC01, discrete inputs FC02, holding registers FC03, input registers
/// FC04) with configurable data types, named poll groups, and BehaviorSubject
/// value streams.
///
/// Follows the MSocket connection loop pattern from jbtm.
class ModbusClientWrapper {
  final String host;
  final int port;
  final int unitId;
  final ModbusClientTcp Function(String host, int port, int unitId)
      _clientFactory;

  final _status =
      BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.disconnected);

  ModbusClientTcp? _client;

  /// When true the connection loop exits at the next check point.
  bool _stopped = true;

  /// Terminal flag -- once disposed, the wrapper cannot be reused.
  bool _disposed = false;

  static const _initialBackoff = Duration(milliseconds: 500);
  static const _maxBackoff = Duration(seconds: 5);
  Duration _backoff = _initialBackoff;

  static final _log = Logger(
    printer: SimplePrinter(),
    level: Level.info,
  );

  // ---------------------------------------------------------------------------
  // Poll infrastructure (Phase 5)
  // ---------------------------------------------------------------------------

  /// All active register subscriptions, keyed by spec.key.
  final Map<String, _RegisterSubscription> _subscriptions = {};

  /// Named poll groups with their own intervals and subscription lists.
  final Map<String, _PollGroup> _pollGroups = {};

  /// Subscription to connectionStream that drives poll start/stop.
  StreamSubscription<ConnectionStatus>? _pollLifecycleSubscription;

  /// Default poll interval when no explicit interval is configured.
  static const _defaultPollInterval = Duration(seconds: 1);

  /// Creates a wrapper for a Modbus device at [host]:[port] with [unitId].
  ///
  /// Provide [clientFactory] to inject a custom/mock ModbusClientTcp for
  /// testing. The default factory creates a real ModbusClientTcp with
  /// [ModbusConnectionMode.doNotConnect] so the wrapper owns the connection
  /// loop.
  ModbusClientWrapper(
    this.host,
    this.port,
    this.unitId, {
    ModbusClientTcp Function(String, int, int)? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultFactory;

  static ModbusClientTcp _defaultFactory(String host, int port, int unitId) {
    return ModbusClientTcp(
      host,
      serverPort: port,
      unitId: unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 3),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API -- Connection
  // ---------------------------------------------------------------------------

  /// Current connection status (synchronous).
  ConnectionStatus get connectionStatus => _status.value;

  /// Connection status stream with replay of current value to new subscribers.
  Stream<ConnectionStatus> get connectionStream => _status.stream;

  /// The underlying Modbus client, if connected. Null when disconnected.
  ModbusClientTcp? get client => _client;

  /// Starts the connection loop (fire-and-forget). The loop runs until
  /// [disconnect] or [dispose] is called. Status changes are emitted via
  /// [connectionStream].
  void connect() {
    if (_disposed) return;
    _stopped = false;
    _connectionLoop();
  }

  /// Stops the reconnect loop and disconnects the client. The wrapper can be
  /// reconnected by calling [connect] again. Streams remain open.
  void disconnect() {
    _stopped = true;
    _cleanupClient();
  }

  /// Terminal shutdown -- stops reconnect, disconnects, and closes all streams.
  /// The wrapper cannot be reused after dispose.
  void dispose() {
    _stopped = true;
    _disposed = true;
    _cleanupClient();
    _stopAllPolling();
    _pollLifecycleSubscription?.cancel();
    _pollLifecycleSubscription = null;
    // Close all subscription BehaviorSubjects
    for (final sub in _subscriptions.values) {
      if (!sub.value$.isClosed) {
        sub.value$.close();
      }
    }
    if (!_status.isClosed) {
      _status.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Public API -- Reading (Phase 5)
  // ---------------------------------------------------------------------------

  /// Creates or updates a named poll group with the given [interval].
  ///
  /// If a group with [name] already exists, its interval is NOT changed --
  /// call before subscribing registers to set the desired interval.
  void addPollGroup(String name, Duration interval,
      {Duration? responseTimeout}) {
    _pollGroups.putIfAbsent(
      name,
      () => _PollGroup(
        name: name,
        interval: interval,
        responseTimeout: responseTimeout,
      ),
    );
  }

  /// Subscribes to a Modbus register described by [spec].
  ///
  /// Returns a `Stream<Object?>` that emits parsed values (bool, int, or
  /// double) on each successful poll read. The stream is backed by a
  /// BehaviorSubject, so new listeners receive the last-known value
  /// immediately.
  ///
  /// If the spec's poll group does not exist, it is lazily created with the
  /// default 1-second interval.
  Stream<Object?> subscribe(ModbusRegisterSpec spec) {
    // Create element for this spec
    final element = _createElement(spec);
    final subscription = _RegisterSubscription(spec: spec, element: element);
    _subscriptions[spec.key] = subscription;

    // Ensure the poll group exists
    final group = _pollGroups.putIfAbsent(
      spec.pollGroup,
      () => _PollGroup(
        name: spec.pollGroup,
        interval: _defaultPollInterval,
      ),
    );
    group._subscriptions.add(subscription);

    // Initialize poll lifecycle listener if not already active
    _initPollLifecycle();

    // If already connected, restart polling to pick up new subscription
    if (connectionStatus == ConnectionStatus.connected) {
      _stopAllPolling();
      _startAllPolling();
    }

    return subscription.stream;
  }

  /// Returns the last-known cached value for [key], or null if not subscribed
  /// or not yet polled.
  Object? read(String key) {
    return _subscriptions[key]?.currentValue;
  }

  /// Removes the subscription for [key] from its poll group.
  void unsubscribe(String key) {
    final sub = _subscriptions.remove(key);
    if (sub == null) return;

    // Remove from its poll group
    final group = _pollGroups[sub.spec.pollGroup];
    if (group != null) {
      group._subscriptions.remove(sub);
    }

    if (!sub.value$.isClosed) {
      sub.value$.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Connection loop (follows MSocket._connectionLoop pattern)
  // ---------------------------------------------------------------------------

  Future<void> _connectionLoop() async {
    while (!_stopped) {
      if (!_status.isClosed) {
        _status.add(ConnectionStatus.connecting);
      }

      try {
        _client = _clientFactory(host, port, unitId);
        final connected = await _client!.connect();

        if (_stopped) {
          await _cleanupClientInstance();
          break;
        }

        if (!connected) {
          throw StateError('connect() returned false');
        }

        // Connected successfully
        if (!_status.isClosed) {
          _status.add(ConnectionStatus.connected);
        }
        _backoff = _initialBackoff;

        // Block until connection drops or stopped
        await _awaitDisconnect();
      } catch (e) {
        _log.i('ModbusClientWrapper($host:$port) connection error: $e');
      }

      // Socket is gone -- clean up
      await _cleanupClientInstance();
      if (!_stopped && !_status.isClosed) {
        _status.add(ConnectionStatus.disconnected);
      }
      if (_stopped) break;

      // Exponential backoff delay
      await Future.delayed(_backoff);
      if (_stopped) break;
      _backoff = _clampDuration(_backoff * 2, Duration.zero, _maxBackoff);
    }
  }

  /// Polls [_client.isConnected] until the connection drops or [_stopped] is
  /// set. Returns when disconnect is detected.
  Future<void> _awaitDisconnect() async {
    while (!_stopped && _client != null && _client!.isConnected) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  // ---------------------------------------------------------------------------
  // Poll lifecycle (Phase 5)
  // ---------------------------------------------------------------------------

  /// Initializes the connection-lifecycle-tied poll management.
  /// Called lazily on first subscribe(). Listens to connectionStream to
  /// start/stop all poll timers.
  void _initPollLifecycle() {
    if (_pollLifecycleSubscription != null) return;
    _pollLifecycleSubscription = connectionStream.listen((status) {
      if (status == ConnectionStatus.connected) {
        _startAllPolling();
      } else {
        _stopAllPolling();
      }
    });
  }

  /// Starts Timer.periodic for each poll group that has subscriptions.
  void _startAllPolling() {
    for (final group in _pollGroups.values) {
      if (group._subscriptions.isNotEmpty) {
        group.start(() => _onPollTick(group));
      }
    }
  }

  /// Cancels all poll timers.
  void _stopAllPolling() {
    for (final group in _pollGroups.values) {
      group.stop();
    }
  }

  /// Executes a single poll tick for a group: reads all subscribed registers
  /// and pipes values into their BehaviorSubjects.
  ///
  /// Guarded by [_pollInProgress] to prevent concurrent sends if a tick
  /// takes longer than the poll interval.
  Future<void> _onPollTick(_PollGroup group) async {
    if (_disposed || connectionStatus != ConnectionStatus.connected) return;
    if (group._pollInProgress) return; // skip if previous tick still running
    if (group._subscriptions.isEmpty) return;
    group._pollInProgress = true;

    try {
      for (final sub in List.of(group._subscriptions)) {
        if (_disposed || connectionStatus != ConnectionStatus.connected) break;

        try {
          final request = sub.element.getReadRequest(
            responseTimeout: group.responseTimeout,
          );
          final result = await _client!.send(request);

          if (result == ModbusResponseCode.requestSucceed) {
            if (!sub.value$.isClosed) {
              sub.value$.add(sub.element.value);
            }
          } else {
            _log.w(
                'Poll group "${group.name}" read failed for "${sub.spec.key}": ${result.name}');
            // Last-known value remains in BehaviorSubject (SCADA behavior)
          }
        } catch (e) {
          _log.w(
              'Poll group "${group.name}" error reading "${sub.spec.key}": $e');
          // Continue to next register
        }
      }
    } finally {
      group._pollInProgress = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Element factory (Phase 5)
  // ---------------------------------------------------------------------------

  /// Creates the correct [ModbusElement] subclass from a [ModbusRegisterSpec].
  ///
  /// Bit types (coil, discreteInput) always return a [ModbusBitElement]
  /// subclass regardless of [spec.dataType]. Register types use [spec.dataType]
  /// to select the correct numeric element class.
  ModbusElement _createElement(ModbusRegisterSpec spec) {
    final type = spec.registerType;
    final address = spec.address;
    final name = spec.key;

    // Bit types (coils and discrete inputs)
    if (type == ModbusElementType.coil) {
      return ModbusCoil(name: name, address: address);
    }
    if (type == ModbusElementType.discreteInput) {
      return ModbusDiscreteInput(name: name, address: address);
    }

    // Register types -- select by dataType
    switch (spec.dataType) {
      case ModbusDataType.int16:
        return ModbusInt16Register(name: name, address: address, type: type);
      case ModbusDataType.uint16:
        return ModbusUint16Register(name: name, address: address, type: type);
      case ModbusDataType.int32:
        return ModbusInt32Register(name: name, address: address, type: type);
      case ModbusDataType.uint32:
        return ModbusUint32Register(name: name, address: address, type: type);
      case ModbusDataType.float32:
        return ModbusFloatRegister(name: name, address: address, type: type);
      case ModbusDataType.int64:
        return ModbusInt64Register(name: name, address: address, type: type);
      case ModbusDataType.uint64:
        return ModbusUint64Register(name: name, address: address, type: type);
      case ModbusDataType.float64:
        return ModbusDoubleRegister(name: name, address: address, type: type);
      case ModbusDataType.bit:
        // bit for register type defaults to uint16
        return ModbusUint16Register(name: name, address: address, type: type);
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Disconnects and nulls out the current client instance.
  Future<void> _cleanupClientInstance() async {
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {
        // Ignore errors during cleanup
      }
    }
  }

  /// Stops the client and emits disconnected status if appropriate.
  void _cleanupClient() {
    _cleanupClientInstance();
    if (!_status.isClosed &&
        _status.value != ConnectionStatus.disconnected) {
      _status.add(ConnectionStatus.disconnected);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Duration _clampDuration(
      Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
