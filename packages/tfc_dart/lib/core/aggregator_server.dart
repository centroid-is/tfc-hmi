import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart';

import 'alarm.dart';
import 'boolean_expression.dart';
import 'preferences.dart';
import 'state_man.dart';

/// Credentials for a single user allowed to connect to the aggregator server.
class AggregatorUser {
  final String username;
  final String password;
  final bool admin;

  AggregatorUser({
    required this.username,
    required this.password,
    this.admin = false,
  });

  factory AggregatorUser.fromJson(Map<String, dynamic> json) {
    return AggregatorUser(
      username: json['username'] as String,
      password: json['password'] as String,
      admin: json['admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'admin': admin,
      };
}

/// Configuration for the OPC UA aggregator server.
class AggregatorConfig {
  final bool enabled;
  final int port;
  final Duration discoveryTtl;

  /// TLS certificate (DER or PEM bytes). Null = no TLS.
  final Uint8List? certificate;

  /// TLS private key (DER or PEM bytes). Required when [certificate] is set.
  final Uint8List? privateKey;

  /// Allowed users. Empty list = anonymous access only.
  final List<AggregatorUser> users;

  /// Whether to allow anonymous access alongside user auth.
  final bool allowAnonymous;

  /// HMI client connection config for the aggregator server.
  /// Contains endpoint, username, password, TLS cert/key.
  final OpcUAConfig? clientConfig;

  AggregatorConfig({
    this.enabled = false,
    this.port = 4840,
    this.discoveryTtl = const Duration(minutes: 30),
    this.certificate,
    this.privateKey,
    this.users = const [],
    this.allowAnonymous = true,
    this.clientConfig,
  });

  /// Whether TLS is configured (both cert and key present).
  bool get hasTls => certificate != null && privateKey != null;

  /// Whether user authentication is configured.
  bool get hasUsers => users.isNotEmpty;

  factory AggregatorConfig.fromJson(Map<String, dynamic> json) {
    return AggregatorConfig(
      enabled: json['enabled'] as bool? ?? false,
      port: json['port'] as int? ?? 4840,
      discoveryTtl: Duration(
        seconds: json['discovery_ttl_seconds'] as int? ?? 1800,
      ),
      certificate: json['ssl_cert'] != null
          ? base64Decode(json['ssl_cert'] as String)
          : null,
      privateKey: json['ssl_key'] != null
          ? base64Decode(json['ssl_key'] as String)
          : null,
      users: (json['users'] as List<dynamic>?)
              ?.map((u) => AggregatorUser.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [],
      allowAnonymous: json['allow_anonymous'] as bool? ?? true,
      clientConfig: json['client_config'] != null
          ? OpcUAConfig.fromJson(json['client_config'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'port': port,
        'discovery_ttl_seconds': discoveryTtl.inSeconds,
        if (certificate != null) 'ssl_cert': base64Encode(certificate!),
        if (privateKey != null) 'ssl_key': base64Encode(privateKey!),
        if (users.isNotEmpty) 'users': users.map((u) => u.toJson()).toList(),
        'allow_anonymous': allowAnonymous,
        if (clientConfig != null) 'client_config': clientConfig!.toJson(),
      };
}

/// Encodes/decodes aggregator node IDs.
///
/// Maps upstream `(alias, NodeId)` to aggregator namespace node IDs.
/// Format: "alias:ns=N;s=identifier" or "alias:ns=N;i=numericId"
/// When alias is null, uses "default" as the prefix.
class AggregatorNodeId {
  static const String defaultAlias = 'default';

  /// Build an aggregator NodeId from an upstream alias and NodeId.
  /// All aggregator nodes use namespace=1, string identifiers.
  static NodeId encode(String? alias, NodeId upstream) {
    final a = alias ?? defaultAlias;
    final upstreamStr = upstream.toString(); // "ns=N;s=id" or "ns=N;i=id"
    return NodeId.fromString(1, '$a:$upstreamStr');
  }

  /// Build an aggregator folder NodeId for a server alias.
  /// Points to `Servers/Variables/OpcUa/<alias>`.
  static NodeId folderNodeId(String? alias) {
    final a = alias ?? defaultAlias;
    return NodeId.fromString(1, 'Servers/Variables/OpcUa/$a');
  }

  /// Parse an aggregator NodeId back into (alias, upstream NodeId).
  /// Returns null if the NodeId doesn't match the aggregator format.
  static (String alias, NodeId upstreamNodeId)? decode(
      NodeId aggregatorNodeId) {
    if (aggregatorNodeId.namespace != 1) return null;
    if (!aggregatorNodeId.isString()) return null;

    final str = aggregatorNodeId.string;
    final colonIndex = str.indexOf(':');
    if (colonIndex < 0) return null;

    final alias = str.substring(0, colonIndex);
    final nodeIdStr = str.substring(colonIndex + 1);

    final nodeId = _parseNodeIdString(nodeIdStr);
    if (nodeId == null) return null;

    return (alias, nodeId);
  }

  /// Build an aggregator NodeId from a key mapping entry's node config.
  static NodeId fromOpcUANodeConfig(OpcUANodeConfig config) {
    final (nodeId, _) = config.toNodeId();
    return encode(config.serverAlias, nodeId);
  }

  /// Parse a NodeId string like "ns=4;s=GVL.temp" or "ns=0;i=2258".
  static NodeId? _parseNodeIdString(String str) {
    final nsMatch = RegExp(r'^ns=(\d+);([si])=(.+)$').firstMatch(str);
    if (nsMatch == null) return null;

    final ns = int.parse(nsMatch.group(1)!);
    final type = nsMatch.group(2)!;
    final id = nsMatch.group(3)!;

    if (type == 'i') {
      final numId = int.tryParse(id);
      if (numId == null) return null;
      return NodeId.fromNumeric(ns, numId);
    }
    return NodeId.fromString(ns, id);
  }
}

/// OPC UA server that aggregates data from upstream servers.
///
/// Creates a local OPC UA server that exposes upstream PLC data
/// through a single endpoint. Variables are placed under ObjectsFolder
/// with alias-prefixed node IDs.
///
/// Lifecycle:
/// 1. Construct with config + shared StateMan
/// 2. Call [initialize] to create server + populate address space
/// 3. Call [runLoop] to process server iterations (async, non-blocking)
/// 4. Call [shutdown] to stop and clean up
class AggregatorServer {
  AggregatorConfig config;
  final StateMan sharedStateMan;
  final Logger _logger = Logger();

  late Server _server;
  bool _running = false;

  /// Maps aggregator node ID string → upstream StreamSubscription
  final Map<String, StreamSubscription<DynamicValue>> _upstreamSubs = {};

  /// Maps aggregator node ID string → monitorVariable StreamSubscription
  final Map<String, StreamSubscription<(String, DynamicValue?)>> _monitorSubs =
      {};

  /// Cache of last known values per aggregator node
  final Map<String, DynamicValue> _valueCache = {};

  /// Pending internal write count per node key (suppress forward to avoid feedback loop).
  /// A counter instead of a Set so rapid upstream bursts don't lose track.
  final Map<String, int> _internalWrites = {};

  /// Tracks created folder, variable, and discovered nodes
  final Set<String> _createdFolders = {};
  final Set<String> _createdVariables = {};

  /// Custom types registered on the aggregator server (by typeId string).
  final Set<String> _registeredCustomTypes = {};

  /// Discovered nodes with last-accessed timestamp for TTL expiry.
  final Map<String, DateTime> _discoveredNodes = {};

  /// Reverse mapping: aggregator node string → key mapping key
  final Map<String, String> _nodeToKeyMap = {};

  /// NodeIds created per alias — used by _teardownAlias to delete all nodes.
  final Map<String, Set<NodeId>> _aliasNodes = {};

  /// Tracks in-flight discovery/persist operations so shutdown can await them.
  final Set<Future<void>> _pendingDiscoveries = {};

  /// Wait for all pending async operations (persist, reload, discovery).
  Future<void> waitForPending() async {
    if (_pendingDiscoveries.isNotEmpty) {
      await Future.wait(_pendingDiscoveries.toList())
          .catchError((_) => <void>[]);
    }
  }

  /// Periodic timer for TTL cleanup of discovered nodes.
  Timer? _ttlCleanupTimer;

  /// Subscriptions to upstream connection status changes per alias.
  final Map<String, StreamSubscription<(ConnectionStatus, String?)>> _connectionSubs = {};

  /// Optional AlarmMan for injecting connection-status alarms.
  AlarmMan? alarmMan;

  /// NodeIds for per-alias connected status variables.
  final Map<String, NodeId> _connectedNodeIds = {};

  /// NodeIds for per-alias last error variables.
  final Map<String, NodeId> _lastErrorNodeIds = {};

  /// File path for persisting config changes (used by setOpcUaClients).
  final String? configFilePath;

  /// Callback invoked when setOpcUaClients changes the server list.
  /// Receives the new list of OpcUAConfig; returns a status string.
  final Future<String> Function(List<OpcUAConfig> newServers)? onReloadClients;

  /// Preferences API for persisting keymappings.
  final PreferencesApi? prefs;

  AggregatorServer({
    required this.config,
    required this.sharedStateMan,
    this.alarmMan,
    this.configFilePath,
    this.onReloadClients,
    this.prefs,
  });

  /// For testing: access the underlying server directly.
  Server get server => _server;

  /// Whether the server loop is currently running.
  bool get isRunning => _running;

  /// Number of discovered (non-mapped) nodes currently tracked.
  int get discoveredNodeCount => _discoveredNodes.length;

  /// Initialize the OPC UA server and populate address space from key mappings.
  /// Auto-generates a TLS certificate if none is configured, and persists it
  /// to the config file so it survives restarts.
  Future<void> initialize({bool skipTls = false}) async {
    if (!config.hasTls && !skipTls) {
      _logger.i('Aggregator: no TLS certificate configured, generating self-signed (30 year validity)');
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'OPC-UA-Aggregator', 'O': 'Centroid', 'OU': 'OPC-UA'},
        keyPair.privateKey as RSAPrivateKey,
        keyPair.publicKey as RSAPublicKey,
      );
      final certPem = X509Utils.generateSelfSignedCertificate(
        keyPair.privateKey as RSAPrivateKey,
        csr,
        365 * 30,
      );
      final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
          keyPair.privateKey as RSAPrivateKey);
      final certBytes = Uint8List.fromList(utf8.encode(certPem));
      final keyBytes = Uint8List.fromList(utf8.encode(keyPem));

      config = AggregatorConfig(
        enabled: config.enabled,
        port: config.port,
        discoveryTtl: config.discoveryTtl,
        certificate: certBytes,
        privateKey: keyBytes,
        users: config.users,
        allowAnonymous: config.allowAnonymous,
        clientConfig: config.clientConfig,
      );
      sharedStateMan.config.aggregator = config;

      if (configFilePath != null) {
        await sharedStateMan.config.toFile(configFilePath!);
        _logger.i('Aggregator: persisted generated certificate to $configFilePath');
      }
    }

    _server = _createServer();

    // Create folders and methods synchronously so the address space
    // structure exists immediately, then start the server so it's
    // reachable even while upstream PLCs may be offline.
    _createAliasFolders();
    await _syncUpstreamStatusKeys();
    _addGetOpcUaClientsMethod();
    _addSetOpcUaClientsMethod();
    _setupMethodAccessControl();
    _running = true;
    _server.start();
    _startTtlCleanup();
    _watchConnections();

    // Populate data nodes in the background — individual failures
    // are caught and logged, and _repopulateAlias handles reconnection.
    final populateFuture = _populateFromKeyMappings().catchError((e) {
      _logger.e('Aggregator: populateFromKeyMappings failed: $e');
    });
    _pendingDiscoveries.add(populateFuture);
    populateFuture.whenComplete(() => _pendingDiscoveries.remove(populateFuture));
  }

  /// Create the OPC UA server. TLS is always available after initialize().
  Server _createServer() {
    final Map<String, String>? users = config.hasUsers
        ? {for (final u in config.users) u.username: u.password}
        : null;

    if (config.hasTls) {
      _logger.i('Aggregator: TLS enabled on port ${config.port}');
    } else {
      _logger.i('Aggregator: no TLS on port ${config.port}');
    }
    if (config.hasUsers) {
      _logger.i('Aggregator: user auth enabled (${config.users.length} user(s), anonymous=${config.allowAnonymous})');
    }

    return Server(
      port: config.port,
      logLevel: LogLevel.UA_LOGLEVEL_WARNING,
      certificate: config.certificate,
      privateKey: config.privateKey,
      users: users,
      allowAnonymous: config.allowAnonymous,
      allowNonePolicyPassword: false,
      securityPolicyNoneDiscoveryOnly: config.hasTls,
      maxSessionTimeout: 30000, // 30s — clean up stale/failed sessions quickly
    );
  }

  /// Start periodic TTL cleanup of discovered nodes.
  void _startTtlCleanup() {
    _ttlCleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => cleanupExpiredDiscoveries(),
    );
  }

  /// Remove discovered node entries older than [config.discoveryTtl].
  /// Since open62541_dart has no deleteNode, this only clears tracking —
  /// subsequent Discover calls will re-read values from upstream.
  ///
  /// [ttlOverride] can be used in tests to force immediate expiry.
  void cleanupExpiredDiscoveries({Duration? ttlOverride}) {
    final now = DateTime.now();
    final expired = <String>[];
    for (final entry in _discoveredNodes.entries) {
      if (now.difference(entry.value) >= (ttlOverride ?? config.discoveryTtl)) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _discoveredNodes.remove(key);
    }
    if (expired.isNotEmpty) {
      _logger.d('Aggregator: TTL cleanup removed ${expired.length} discovered node entries');
    }
  }

  static const _serversFolder = 'Servers';
  static const _statusFolder = '$_serversFolder/Status';
  static const _opcuaStatusFolder = '$_statusFolder/OpcUa';
  static const _variablesFolder = '$_serversFolder/Variables';
  static const _opcuaVariablesFolder = '$_variablesFolder/OpcUa';

  /// Create Servers/Status/OpcUa/[alias]/ folder with connected + last_error.
  void _addServerStatistics(String alias) {
    // Ensure parent folders exist (only created once)
    if (!_createdFolders.contains(_serversFolder)) {
      _server.addObjectNode(
          NodeId.fromString(1, _serversFolder), 'Servers');
      _createdFolders.add(_serversFolder);
    }
    if (!_createdFolders.contains(_statusFolder)) {
      _server.addObjectNode(
          NodeId.fromString(1, _statusFolder), 'Status',
          parentNodeId: NodeId.fromString(1, _serversFolder));
      _createdFolders.add(_statusFolder);
    }
    if (!_createdFolders.contains(_opcuaStatusFolder)) {
      _server.addObjectNode(
          NodeId.fromString(1, _opcuaStatusFolder), 'OpcUa',
          parentNodeId: NodeId.fromString(1, _statusFolder));
      _createdFolders.add(_opcuaStatusFolder);
    }

    final aliasFolder = NodeId.fromString(1, '$_opcuaStatusFolder/$alias');
    _server.addObjectNode(aliasFolder, alias,
        parentNodeId: NodeId.fromString(1, _opcuaStatusFolder));

    final connNodeId = NodeId.fromString(1, '$_opcuaStatusFolder/$alias/connected');
    _server.addVariableNode(
      connNodeId,
      DynamicValue(value: false, typeId: NodeId.boolean, name: 'connected'),
      parentNodeId: aliasFolder,
      accessLevel: const AccessLevelMask(read: true),
    );
    _connectedNodeIds[alias] = connNodeId;

    final errorNodeId = NodeId.fromString(1, '$_opcuaStatusFolder/$alias/last_error');
    _server.addVariableNode(
      errorNodeId,
      DynamicValue(value: '', typeId: NodeId.uastring, name: 'last_error'),
      parentNodeId: aliasFolder,
      accessLevel: const AccessLevelMask(read: true),
    );
    _lastErrorNodeIds[alias] = errorNodeId;
  }

  /// Watch upstream connection status, update connected variables,
  /// invalidate discovered nodes on reconnection, and inject alarms.
  void _watchConnections() {
    for (final wrapper in sharedStateMan.clients) {
      final alias = wrapper.config.serverAlias ?? AggregatorNodeId.defaultAlias;
      // Track whether we've seen a disconnect (to avoid alarm on initial connect)
      var wasDisconnected = false;
      // Write current status immediately (stream only emits on changes,
      // so if client is already connected we'd miss it).
      final connNodeId = _connectedNodeIds[alias];
      if (connNodeId != null) {
        final connected =
            wrapper.connectionStatus == ConnectionStatus.connected;
        _server.write(connNodeId,
            DynamicValue(value: connected, typeId: NodeId.boolean));
      }

      _connectionSubs[alias] = wrapper.connectionStream.listen((event) {
        final (status, error) = event;
        // Update the connected variable on the aggregator
        final connNodeId = _connectedNodeIds[alias];
        if (connNodeId != null) {
          final connected = status == ConnectionStatus.connected;
          _server.write(connNodeId,
              DynamicValue(value: connected, typeId: NodeId.boolean));
        }
        // Update the last_error variable
        final errorNodeId = _lastErrorNodeIds[alias];
        if (errorNodeId != null) {
          _server.write(errorNodeId,
              DynamicValue(value: error ?? '', typeId: NodeId.uastring));
        }

        if (status == ConnectionStatus.connected) {
          if (wasDisconnected) {
            _fatalErrorAliases.remove(alias);
            _removeDisconnectAlarm(alias);
            final future = _repopulateAlias(alias).catchError((e) {
              _logger.e('Aggregator: repopulate "$alias" failed: $e');
            });
            _pendingDiscoveries.add(future);
            future.whenComplete(() => _pendingDiscoveries.remove(future));
          }
        } else if (status == ConnectionStatus.disconnected) {
          wasDisconnected = true;
          _teardownAlias(alias);
          _injectDisconnectAlarm(alias);
        }
      });
    }
  }

  /// Inject a disconnect alarm into AlarmMan for the given alias.
  void _injectDisconnectAlarm(String alias) {
    if (alarmMan == null) return;
    final uid = 'connection-$alias';

    final rule = AlarmRule(
      level: AlarmLevel.error,
      expression: ExpressionConfig(
        value: Expression(formula: 'disconnected'),
      ),
      acknowledgeRequired: false,
    );

    final alarmConfig = AlarmConfig(
      uid: uid,
      title: '$alias disconnected',
      description: 'OPC UA Server: "$alias" is disconnected',
      rules: [rule],
    );

    alarmMan!.addExternalAlarm(AlarmActive(
      alarm: Alarm(config: alarmConfig),
      notification: AlarmNotification(
        uid: uid,
        active: true,
        expression: 'disconnected',
        rule: rule,
        timestamp: DateTime.now(),
      ),
    ));
    _logger.w('Aggregator: injected disconnect alarm for "$alias"');
  }

  /// Remove a disconnect alarm from AlarmMan when reconnected.
  void _removeDisconnectAlarm(String alias) {
    if (alarmMan == null) return;
    alarmMan!.removeExternalAlarm('connection-$alias');
    _logger.i('Aggregator: removed disconnect alarm for "$alias"');
  }

  /// Tracks aliases that have been marked as having a fatal upstream error
  /// (e.g. BadLicenseExpired) so we only inject the alarm once.
  final Set<String> _fatalErrorAliases = {};

  /// Check if an upstream error is fatal (e.g. license expired) and if so,
  /// mark the alias as disconnected with the error message. This sets the
  /// connected variable to false and updates last_error so the existing
  /// alarm infrastructure fires.
  void _handleUpstreamError(String alias, Object error) {
    final errStr = error.toString();
    if (!errStr.contains('BadLicenseExpired')) return;
    if (_fatalErrorAliases.contains(alias)) return;

    _fatalErrorAliases.add(alias);
    _logger.e('Aggregator: fatal upstream error for "$alias": $errStr');

    final connNodeId = _connectedNodeIds[alias];
    if (connNodeId != null) {
      _server.write(connNodeId,
          DynamicValue(value: false, typeId: NodeId.boolean));
    }
    final errorNodeId = _lastErrorNodeIds[alias];
    if (errorNodeId != null) {
      _server.write(errorNodeId,
          DynamicValue(
              value: 'PLC license expired (BadLicenseExpired)',
              typeId: NodeId.uastring));
    }
    _injectDisconnectAlarm(alias);
  }

  /// Called when a successful value arrives on an upstream subscription.
  /// If the alias was previously marked as having a fatal error, clear
  /// the error state and remove the alarm — the PLC has recovered.
  void _clearFatalError(String alias) {
    if (!_fatalErrorAliases.remove(alias)) return;

    _logger.i('Aggregator: upstream "$alias" recovered, clearing fatal error');

    final connNodeId = _connectedNodeIds[alias];
    if (connNodeId != null) {
      _server.write(connNodeId,
          DynamicValue(value: true, typeId: NodeId.boolean));
    }
    final errorNodeId = _lastErrorNodeIds[alias];
    if (errorNodeId != null) {
      _server.write(errorNodeId,
          DynamicValue(value: '', typeId: NodeId.uastring));
    }
    _removeDisconnectAlarm(alias);
  }

  /// Remove all data nodes for [alias] from the address space and cancel
  /// their subscriptions. Called when the upstream PLC disconnects so that
  /// HMI widgets see the nodes disappear and go grey.
  ///
  /// The alias folder and status nodes (connected / last_error) are kept.
  void _teardownAlias(String alias) {
    final nodes = _aliasNodes.remove(alias);
    if (nodes == null || nodes.isEmpty) {
      _logger.i('Aggregator: teardown "$alias" — no nodes cached');
      return;
    }

    var deleted = 0;
    for (final nodeId in nodes) {
      final nodeKey = nodeId.toString();

      _upstreamSubs[nodeKey]?.cancel();
      _upstreamSubs.remove(nodeKey);
      _monitorSubs[nodeKey]?.cancel();
      _monitorSubs.remove(nodeKey);

      try {
        _server.deleteNode(nodeId);
        deleted++;
      } catch (e) {
        _logger.d('Aggregator: deleteNode failed for "$nodeKey": $e');
      }

      _createdVariables.remove(nodeKey);
      _discoveredNodes.remove(nodeKey);
      _valueCache.remove(nodeKey);
      _internalWrites.remove(nodeKey);
      _nodeToKeyMap.remove(nodeKey);
    }

    _logger.i('Aggregator: teardown "$alias" — deleted $deleted nodes');
  }

  /// Re-create data nodes for [alias] after reconnection.
  Future<void> _repopulateAlias(String alias) async {
    for (final entry in sharedStateMan.keyMappings.nodes.entries) {
      final key = entry.key;
      final mapping = entry.value;
      if (mapping.opcuaNode == null) continue;
      final mapAlias =
          mapping.opcuaNode!.serverAlias ?? AggregatorNodeId.defaultAlias;
      if (mapAlias != alias) continue;

      await _createAndSubscribeVariable(key, mapping);
    }
    _logger.i('Aggregator: repopulated data nodes for "$alias"');
  }

  /// Populate address space from all key mappings.
  /// Folders are already created by initialize(), so this only adds variables.
  Future<void> _populateFromKeyMappings() async {
    for (final entry in sharedStateMan.keyMappings.nodes.entries) {
      final key = entry.key;
      final mapping = entry.value;
      if (mapping.opcuaNode == null) continue;

      await _createAndSubscribeVariable(key, mapping);
    }
  }

  /// Ensure the shared `Servers/`, `Servers/Variables/`, `Servers/Variables/OpcUa/`
  /// folder hierarchy exists (created once, shared with status folders).
  void _ensureVariablesFolderHierarchy() {
    if (!_createdFolders.contains(_serversFolder)) {
      _server.addObjectNode(
          NodeId.fromString(1, _serversFolder), 'Servers');
      _createdFolders.add(_serversFolder);
    }
    if (!_createdFolders.contains(_variablesFolder)) {
      _server.addObjectNode(
          NodeId.fromString(1, _variablesFolder), 'Variables',
          parentNodeId: NodeId.fromString(1, _serversFolder));
      _createdFolders.add(_variablesFolder);
    }
    if (!_createdFolders.contains(_opcuaVariablesFolder)) {
      _server.addObjectNode(
          NodeId.fromString(1, _opcuaVariablesFolder), 'OpcUa',
          parentNodeId: NodeId.fromString(1, _variablesFolder));
      _createdFolders.add(_opcuaVariablesFolder);
    }
  }

  /// Create an object node (folder) and a Discover method for each unique server alias.
  void _createAliasFolders() {
    final aliases = <String>{};
    // Collect aliases from keymappings
    for (final entry in sharedStateMan.keyMappings.nodes.values) {
      if (entry.opcuaNode == null) continue;
      final alias = entry.opcuaNode!.serverAlias ?? AggregatorNodeId.defaultAlias;
      // Skip internal aliases (e.g. '__aggregate' for aggregator-native nodes)
      if (alias.startsWith('__')) continue;
      aliases.add(alias);
    }
    // Also include all configured upstream PLCs (may not have keymappings yet)
    for (final opcConfig in sharedStateMan.config.opcua) {
      aliases.add(opcConfig.serverAlias ?? AggregatorNodeId.defaultAlias);
    }

    _ensureVariablesFolderHierarchy();

    for (final alias in aliases) {
      final folderKey = '$_opcuaVariablesFolder/$alias';
      final isNew = !_createdFolders.contains(folderKey);
      _ensureAliasVariablesFolder(alias);
      if (isNew) {
        _addDiscoverMethod(alias);
        _addServerStatistics(alias);
        _logger.d('Aggregator: created folder "$alias"');
      }
    }
  }

  /// Inject `__agg_<alias>_connected` and `__agg_<alias>_last_error`
  /// keymapping entries for each upstream PLC and persist to the database.
  /// Called at init and after setOpcUaClients changes the server list.
  Future<void> _syncUpstreamStatusKeys() async {
    if (prefs == null) {
      _logger.e('Aggregator: cannot sync upstream status keys — prefs is null');
      return;
    }
    // Fetch the latest keymappings from the database to avoid overwriting
    // entries added by other processes (e.g. the HMI).
    final freshKeyMappings =
        await KeyMappings.fromPrefs(prefs!, createDefault: false);
    // Remove stale __agg_* entries for aliases that no longer exist.
    freshKeyMappings.nodes
        .removeWhere((key, _) => key.startsWith('__agg_'));
    for (final opcConfig in sharedStateMan.config.opcua) {
      final alias = opcConfig.serverAlias ?? AggregatorNodeId.defaultAlias;
      freshKeyMappings.nodes['__agg_${alias}_connected'] = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(
          namespace: 1,
          identifier: 'Servers/Status/OpcUa/$alias/connected',
        )..serverAlias = '__aggregate',
      );
      freshKeyMappings.nodes['__agg_${alias}_last_error'] = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(
          namespace: 1,
          identifier: 'Servers/Status/OpcUa/$alias/last_error',
        )..serverAlias = '__aggregate',
      );
    }
    await prefs!.setString(
        'key_mappings', jsonEncode(freshKeyMappings.toJson()));
    // Update in-memory keymappings so the backend's own StateMan sees them too.
    sharedStateMan.keyMappings = freshKeyMappings;

    // Persist connection alarms to the database so the HMI picks them up
    // as normal alarms. Written directly to prefs (not the backend's
    // in-memory AlarmMan, which can't evaluate __agg_* keys).
    final alarmJson = await prefs!.getString('alarm_man_config');
    final alarmConfig = alarmJson != null
        ? AlarmManConfig.fromJson(jsonDecode(alarmJson))
        : AlarmManConfig(alarms: []);
    alarmConfig.alarms.removeWhere((a) => a.uid.startsWith('connection-'));
    for (final opcConfig in sharedStateMan.config.opcua) {
      final alias = opcConfig.serverAlias ?? AggregatorNodeId.defaultAlias;
      final key = '__agg_${alias}_connected';
      alarmConfig.alarms.add(AlarmConfig(
        uid: 'connection-$alias',
        title: '$alias disconnected',
        description: 'OPC UA Server: "$alias" is disconnected',
        rules: [
          AlarmRule(
            level: AlarmLevel.error,
            expression: ExpressionConfig(
              value: Expression(formula: '$key == false'),
            ),
            acknowledgeRequired: false,
          ),
        ],
      ));
    }
    await prefs!.setString(
        'alarm_man_config', jsonEncode(alarmConfig.toJson()));
  }

  /// Ensure the `Servers/Variables/OpcUa/<alias>/` folder exists.
  void _ensureAliasVariablesFolder(String alias) {
    final folderKey = '$_opcuaVariablesFolder/$alias';
    if (_createdFolders.contains(folderKey)) return;
    _ensureVariablesFolderHierarchy();
    _server.addObjectNode(
      AggregatorNodeId.folderNodeId(alias),
      alias,
      parentNodeId: NodeId.fromString(1, _opcuaVariablesFolder),
    );
    _createdFolders.add(folderKey);
  }

  /// Add a Discover method node under the alias folder.
  ///
  /// The method accepts a parent NodeId string (e.g. "ns=0;i=85") and
  /// browses the upstream PLC at that node, creating discovered child
  /// nodes in the aggregator's address space.
  void _addDiscoverMethod(String alias) {
    final folderId = AggregatorNodeId.folderNodeId(alias);
    final methodId = NodeId.fromString(1, '$_opcuaVariablesFolder/$alias/Discover');

    _server.addMethodNode(
      methodId,
      'Discover',
      callback: (inputs) {
        final parentNodeIdStr = inputs.first.value as String;
        final future = _discoverNodes(alias, parentNodeIdStr);
        _pendingDiscoveries.add(future);
        future.whenComplete(() => _pendingDiscoveries.remove(future));
        return [
          DynamicValue(
            value: 'discovering $parentNodeIdStr',
            typeId: NodeId.uastring,
          ),
        ];
      },
      inputArguments: [
        DynamicValue(name: 'parentNodeId', typeId: NodeId.uastring),
      ],
      outputArguments: [
        DynamicValue(name: 'status', typeId: NodeId.uastring),
      ],
      parentNodeId: folderId,
    );
  }

  /// Add getOpcUaClients method node under ObjectsFolder.
  /// Returns a sanitized JSON list of upstream server configs.
  void _addGetOpcUaClientsMethod() {
    final methodId = NodeId.fromString(1, 'getOpcUaClients');
    _server.addMethodNode(
      methodId,
      'getOpcUaClients',
      callback: (inputs) {
        final sanitized = sharedStateMan.config.opcua.map((c) => {
              'endpoint': c.endpoint,
              'server_alias': c.serverAlias,
              'has_tls': c.sslCert != null && c.sslKey != null,
              'has_credentials':
                  c.username != null && c.username!.isNotEmpty,
            }).toList();
        return [
          DynamicValue(
            value: jsonEncode(sanitized),
            typeId: NodeId.uastring,
          ),
        ];
      },
      outputArguments: [
        DynamicValue(name: 'servers', typeId: NodeId.uastring),
      ],
    );
  }

  /// Guards against concurrent setOpcUaClients calls.
  bool _setOpcUaClientsInProgress = false;

  /// Add setOpcUaClients method node under ObjectsFolder.
  /// Accepts a JSON list of server configs, merges credentials, persists, and reloads.
  void _addSetOpcUaClientsMethod() {
    final methodId = NodeId.fromString(1, 'setOpcUaClients');
    _server.addMethodNode(
      methodId,
      'setOpcUaClients',
      callback: (inputs) {
        final jsonStr = inputs.first.value as String;

        // Validate and process synchronously so we can return a real status
        final result = _handleSetOpcUaClients(jsonStr);
        return [
          DynamicValue(value: result, typeId: NodeId.uastring),
        ];
      },
      inputArguments: [
        DynamicValue(name: 'serversJson', typeId: NodeId.uastring),
      ],
      outputArguments: [
        DynamicValue(name: 'status', typeId: NodeId.uastring),
      ],
    );
  }

  /// Handle the setOpcUaClients method call synchronously for validation,
  /// then schedule async persistence/reload.
  String _handleSetOpcUaClients(String jsonStr) {
    if (_setOpcUaClientsInProgress) {
      return 'error: another setOpcUaClients call is in progress';
    }

    // Validate JSON input
    final List<dynamic> decoded;
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! List) {
        return 'error: expected JSON array, got ${parsed.runtimeType}';
      }
      decoded = parsed;
    } catch (e) {
      return 'error: invalid JSON: $e';
    }

    // Validate each entry is a map with required fields
    final incoming = <Map<String, dynamic>>[];
    for (var i = 0; i < decoded.length; i++) {
      if (decoded[i] is! Map<String, dynamic>) {
        return 'error: entry $i is not an object';
      }
      final entry = decoded[i] as Map<String, dynamic>;
      if (entry['endpoint'] is! String || (entry['endpoint'] as String).isEmpty) {
        return 'error: entry $i missing or empty "endpoint" field';
      }
      incoming.add(entry);
    }

    // Reject empty server list
    if (incoming.isEmpty) {
      return 'error: server list cannot be empty';
    }

    try {
      // Build current config lookup by serverAlias
      final currentByAlias = <String, OpcUAConfig>{};
      for (final c in sharedStateMan.config.opcua) {
        final alias = c.serverAlias ?? c.endpoint;
        currentByAlias[alias] = c;
      }

      // Merge credentials: has_credentials/has_tls → keep existing
      final merged = <OpcUAConfig>[];
      for (final raw in incoming) {
        final alias = raw['server_alias'] as String? ?? raw['endpoint'] as String;
        final existing = currentByAlias[alias];
        final config = OpcUAConfig()
          ..endpoint = raw['endpoint'] as String
          ..serverAlias = raw['server_alias'] as String?;

        // Credential merge
        if (raw['has_credentials'] == true && existing != null) {
          config.username = existing.username;
          config.password = existing.password;
        } else if (raw.containsKey('username')) {
          config.username = raw['username'] as String?;
          config.password = raw['password'] as String?;
        }

        // TLS merge
        if (raw['has_tls'] == true && existing != null) {
          config.sslCert = existing.sslCert;
          config.sslKey = existing.sslKey;
        } else if (raw.containsKey('ssl_cert')) {
          config.sslCert = raw['ssl_cert'] != null
              ? base64Decode(raw['ssl_cert'] as String)
              : null;
          config.sslKey = raw['ssl_key'] != null
              ? base64Decode(raw['ssl_key'] as String)
              : null;
        }

        merged.add(config);
      }

      // Schedule async persistence + reload (guarded against concurrent calls).
      // Config is updated AFTER the reload callback so the callback can
      // compare old vs new to decide which servers need restarting.
      _setOpcUaClientsInProgress = true;
      final future = _persistAndReload(merged);
      _pendingDiscoveries.add(future);
      future.whenComplete(() {
        _pendingDiscoveries.remove(future);
        _setOpcUaClientsInProgress = false;
      });

      // Create alias folders for any new aliases
      _createAliasFolders();

      return 'ok: ${merged.length} server(s) configured';
    } catch (e) {
      _logger.e('Aggregator: setOpcUaClients failed: $e');
      return 'error: $e';
    }
  }

  /// Persist config to file, trigger reload callback, then update in-memory config.
  Future<void> _persistAndReload(List<OpcUAConfig> merged) async {
    // Save old list so the reload callback can compare old vs new.
    final old = sharedStateMan.config.opcua;
    // Update in-memory BEFORE writing so toFile() serializes the merged config.
    sharedStateMan.config.opcua = merged;
    try {
      if (configFilePath != null) {
        await sharedStateMan.config.toFile(configFilePath!);
        _logger.i('Aggregator: persisted config to $configFilePath');
      }
      await _syncUpstreamStatusKeys();
      if (onReloadClients != null) {
        final result = await onReloadClients!(merged);
        _logger.i('Aggregator: reload callback returned: $result');
      }
    } catch (e) {
      _logger.e('Aggregator: persist/reload failed: $e');
      // Restore old config on failure
      sharedStateMan.config.opcua = old;
    }
  }

  /// Configure native OPC UA per-method access control.
  /// getOpcUaClients: any authenticated user.
  /// setOpcUaClients: only admin users.
  void _setupMethodAccessControl() {
    if (!config.hasUsers) return;
    final allUsers = config.users.map((u) => u.username).toSet();
    final adminUsers =
        config.users.where((u) => u.admin).map((u) => u.username).toSet();
    final getMethodId = NodeId.fromString(1, 'getOpcUaClients');
    final setMethodId = NodeId.fromString(1, 'setOpcUaClients');
    _server.setMethodAccess(getMethodId, allowedUsers: allUsers);
    _server.setMethodAccess(setMethodId, allowedUsers: adminUsers);
    _logger.i(
        'Aggregator: method access control configured (${allUsers.length} user(s), ${adminUsers.length} admin(s))');
  }

  /// Find the ClientApi for a given server alias.
  ClientApi? _getClientForAlias(String alias) {
    for (final wrapper in sharedStateMan.clients) {
      final wrapperAlias =
          wrapper.config.serverAlias ?? AggregatorNodeId.defaultAlias;
      if (wrapperAlias == alias) return wrapper.client;
    }
    return null;
  }

  /// Browse upstream PLC at [parentNodeIdStr] and create discovered nodes
  /// in the aggregator under the [alias] folder.
  Future<void> _discoverNodes(String alias, String parentNodeIdStr) async {
    if (!_running) return;

    final parentNodeId = AggregatorNodeId._parseNodeIdString(parentNodeIdStr);
    if (parentNodeId == null) {
      _logger.w('Aggregator: invalid NodeId string "$parentNodeIdStr"');
      return;
    }

    final client = _getClientForAlias(alias);
    if (client == null) {
      _logger.w('Aggregator: no client found for alias "$alias"');
      return;
    }

    try {
      final results = await client.browse(parentNodeId).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('browse timed out for $alias at $parentNodeIdStr'),
      );
      if (!_running) return;
      final folderId = AggregatorNodeId.folderNodeId(alias);

      for (final item in results) {
        if (!item.isForward) continue;
        if (!_running) return;

        final upstreamNodeId = item.nodeId;
        final aggregatorNodeId = AggregatorNodeId.encode(alias, upstreamNodeId);
        final nodeKey = aggregatorNodeId.toString();

        // Skip if already created (mapped or previously discovered)
        if (_createdVariables.contains(nodeKey) ||
            _discoveredNodes.containsKey(nodeKey)) {
          // Touch the timestamp so TTL resets on re-access
          if (_discoveredNodes.containsKey(nodeKey)) {
            _discoveredNodes[nodeKey] = DateTime.now();
          }
          continue;
        }

        try {
          if (item.nodeClass == NodeClass.UA_NODECLASS_OBJECT) {
            try {
              _server.addObjectNode(
                aggregatorNodeId,
                item.browseName,
                parentNodeId: folderId,
              );
            } catch (_) {
              // Node may already exist (TTL cleanup only clears tracking)
            }
            _discoveredNodes[nodeKey] = DateTime.now();
            (_aliasNodes[alias] ??= {}).add(aggregatorNodeId);
            _logger.d(
                'Aggregator: discovered object "${item.browseName}" from $alias');
          } else if (item.nodeClass == NodeClass.UA_NODECLASS_VARIABLE) {
            final value = await client.read(upstreamNodeId).timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('read timed out for ${item.browseName}'),
            );
            if (!_running) return;
            value.name = item.browseName;
            try {
              _server.addVariableNode(
                aggregatorNodeId,
                value,
                parentNodeId: folderId,
                accessLevel: const AccessLevelMask(read: true, write: true),
              );
            } catch (_) {
              // Node may already exist (TTL cleanup only clears tracking)
            }
            _discoveredNodes[nodeKey] = DateTime.now();
            (_aliasNodes[alias] ??= {}).add(aggregatorNodeId);
            _logger.d(
                'Aggregator: discovered variable "${item.browseName}" from $alias');
          }
        } catch (e) {
          _logger.w(
              'Aggregator: failed to add discovered node "${item.browseName}": $e');
        }
      }
    } catch (e) {
      _logger.e(
          'Aggregator: discovery failed for $alias at $parentNodeIdStr: $e');
    }
  }

  /// Create a variable node in the aggregator and subscribe to upstream.
  Future<void> _createAndSubscribeVariable(
      String key, KeyMappingEntry mapping) async {
    final nodeConfig = mapping.opcuaNode!;
    final aggregatorNodeId = AggregatorNodeId.fromOpcUANodeConfig(nodeConfig);
    final nodeKey = aggregatorNodeId.toString();

    if (_createdVariables.contains(nodeKey) || !_running) return;

    try {
      // Read initial value from upstream (with timeout — if the PLC is
      // offline, read() blocks on awaitConnect indefinitely).
      // On timeout the node is skipped; _repopulateAlias creates it
      // when the upstream PLC reconnects.
      final initialValue = await sharedStateMan.read(key).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
            'upstream read timed out for "$key"'),
      );

      // Use the key as the browse name for the variable
      initialValue.name = key;

      // Place variable under its alias folder
      final alias =
          nodeConfig.serverAlias ?? AggregatorNodeId.defaultAlias;
      final parentNodeId = AggregatorNodeId.folderNodeId(alias);

      // Register custom type on the aggregator server if this is an
      // extension object (struct) that the aggregator doesn't know about yet.
      // Both addCustomType (internal type registry for encoding/decoding) and
      // addDataTypeNode (address space node so clients can read the schema)
      // are needed.
      if (initialValue.isObject && initialValue.typeId != null) {
        final typeKey = initialValue.typeId.toString();
        if (!_registeredCustomTypes.contains(typeKey)) {
          _server.addCustomType(initialValue.typeId!, initialValue);
          _server.addDataTypeNode(
            initialValue.typeId!,
            initialValue.name ?? typeKey,
          );
          _registeredCustomTypes.add(typeKey);
          _logger.d('Aggregator: registered custom type $typeKey for key "$key"');
        }
      }

      _server.addVariableNode(
        aggregatorNodeId,
        initialValue,
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: parentNodeId,
      );
      _createdVariables.add(nodeKey);
      (_aliasNodes[alias] ??= {}).add(aggregatorNodeId);
      _valueCache[nodeKey] = initialValue;
      _nodeToKeyMap[nodeKey] = key;

      // Subscribe to upstream changes and push to aggregator server
      final stream = await sharedStateMan.subscribe(key);
      _upstreamSubs[nodeKey] = stream.listen(
        (value) {
          _clearFatalError(alias);
          _valueCache[nodeKey] = value;
          _internalWrites[nodeKey] = (_internalWrites[nodeKey] ?? 0) + 1;
          // Node may have been removed by _teardownAlias; ignore write errors
          _server.write(aggregatorNodeId, value).catchError((e) {
            _logger.d('Aggregator: write to $aggregatorNodeId failed: $e');
          });
        },
        onError: (e) {
          _logger.d('Aggregator: upstream stream error for "$key": $e');
          _handleUpstreamError(alias, e);
        },
      );

      // Monitor for external client writes and forward to upstream PLC.
      // Skip writes that originated from our own upstream subscription.
      _monitorSubs[nodeKey] =
          _server.monitorVariable(aggregatorNodeId).listen(
        (event) {
          final (type, value) = event;
          if (type == 'write' && value != null) {
            final count = _internalWrites[nodeKey] ?? 0;
            if (count > 0) {
              _internalWrites[nodeKey] = count - 1;
              return;
            }
            _forwardWrite(aggregatorNodeId, value);
          }
        },
        onError: (e) {
          _logger.d('Aggregator: monitor error for $aggregatorNodeId: $e');
        },
      );

      _logger.d('Aggregator: exposed key "$key" as $aggregatorNodeId');
    } catch (e) {
      _logger.w('Failed to create aggregator node for key "$key": $e');
      final alias =
          mapping.opcuaNode!.serverAlias ?? AggregatorNodeId.defaultAlias;
      _handleUpstreamError(alias, e);
    }
  }

  /// Forward a write from an external client to the upstream PLC.
  void _forwardWrite(NodeId aggregatorNodeId, DynamicValue value) {
    final nodeKey = aggregatorNodeId.toString();
    final key = _nodeToKeyMap[nodeKey];
    if (key != null) {
      final decoded = AggregatorNodeId.decode(aggregatorNodeId);
      final alias = decoded?.$1 ?? 'unknown';
      sharedStateMan.write(key, value).then((_) {
        _logger.d('Aggregator: forwarded write for key "$key" to upstream "$alias"');
      }).catchError((e) {
        _logger.e('Aggregator: failed to forward write for key "$key" to upstream "$alias": $e');
      });
    } else {
      _logger.w(
          'Aggregator: write to unknown node $aggregatorNodeId (no key mapping)');
    }
  }

  /// Run the server iteration loop. Call from async context.
  /// Returns when [shutdown] is called.
  Future<void> runLoop() async {
    while (_running) {
      try {
        _server.runIterate(waitInterval: false);
      } catch (e) {
        _logger.e('Aggregator: runIterate error: $e');
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Shutdown and clean up all resources.
  Future<void> shutdown() async {
    _running = false;
    _ttlCleanupTimer?.cancel();

    // Wait for any in-flight discoveries to finish (they check _running).
    // Copy to list first — futures self-remove via whenComplete.
    if (_pendingDiscoveries.isNotEmpty) {
      await Future.wait(_pendingDiscoveries.toList())
          .catchError((_) => <void>[]);
    }

    // Cancel all subscriptions
    for (final sub in _upstreamSubs.values) {
      await sub.cancel();
    }
    for (final sub in _monitorSubs.values) {
      await sub.cancel();
    }
    for (final sub in _connectionSubs.values) {
      await sub.cancel();
    }
    _upstreamSubs.clear();
    _monitorSubs.clear();
    _connectionSubs.clear();
    _valueCache.clear();
    _nodeToKeyMap.clear();
    _internalWrites.clear();
    _createdFolders.clear();
    _createdVariables.clear();
    _registeredCustomTypes.clear();
    _discoveredNodes.clear();
    _aliasNodes.clear();
    _connectedNodeIds.clear();
    _lastErrorNodeIds.clear();
    _fatalErrorAliases.clear();

    _server.shutdown();
    _server.delete();
  }
}
