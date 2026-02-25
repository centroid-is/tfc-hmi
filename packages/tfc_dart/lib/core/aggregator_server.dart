import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart';

import 'alarm.dart';
import 'boolean_expression.dart';
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
        seconds: json['discoveryTtlSeconds'] as int? ?? 1800,
      ),
      certificate: json['certificate'] != null
          ? base64Decode(json['certificate'] as String)
          : null,
      privateKey: json['privateKey'] != null
          ? base64Decode(json['privateKey'] as String)
          : null,
      users: (json['users'] as List<dynamic>?)
              ?.map((u) => AggregatorUser.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [],
      allowAnonymous: json['allowAnonymous'] as bool? ?? true,
      clientConfig: json['client_config'] != null
          ? OpcUAConfig.fromJson(json['client_config'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'port': port,
        'discoveryTtlSeconds': discoveryTtl.inSeconds,
        if (certificate != null) 'certificate': base64Encode(certificate!),
        if (privateKey != null) 'privateKey': base64Encode(privateKey!),
        if (users.isNotEmpty) 'users': users.map((u) => u.toJson()).toList(),
        'allowAnonymous': allowAnonymous,
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
  static NodeId folderNodeId(String? alias) {
    return NodeId.fromString(1, alias ?? defaultAlias);
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

  /// Tracks created folder, variable, and discovered nodes
  final Set<String> _createdFolders = {};
  final Set<String> _createdVariables = {};

  /// Discovered nodes with last-accessed timestamp for TTL expiry.
  final Map<String, DateTime> _discoveredNodes = {};

  /// Reverse mapping: aggregator node string → key mapping key
  final Map<String, String> _nodeToKeyMap = {};

  /// Tracks in-flight discovery operations so shutdown can await them.
  final Set<Future<void>> _pendingDiscoveries = {};

  /// Periodic timer for TTL cleanup of discovered nodes.
  Timer? _ttlCleanupTimer;

  /// Subscriptions to upstream connection status changes per alias.
  final Map<String, StreamSubscription<ConnectionStatus>> _connectionSubs = {};

  /// Optional AlarmMan for injecting connection-status alarms.
  AlarmMan? alarmMan;

  /// NodeIds for per-alias connected status variables.
  final Map<String, NodeId> _connectedNodeIds = {};

  /// File path for persisting config changes (used by setOpcUaClients).
  final String? configFilePath;

  /// Callback invoked when setOpcUaClients changes the server list.
  /// Receives the new list of OpcUAConfig; returns a status string.
  final Future<String> Function(List<OpcUAConfig> newServers)? onReloadClients;

  AggregatorServer({
    required this.config,
    required this.sharedStateMan,
    this.alarmMan,
    this.configFilePath,
    this.onReloadClients,
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
  Future<void> initialize() async {
    if (!config.hasTls) {
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
    await _populateFromKeyMappings();
    _addGetOpcUaClientsMethod();
    _addSetOpcUaClientsMethod();
    _setupMethodAccessControl();
    _server.start();
    _startTtlCleanup();
    _watchConnections();
  }

  /// Create the OPC UA server. TLS is always available after initialize().
  Server _createServer() {
    final Map<String, String>? users = config.hasUsers
        ? {for (final u in config.users) u.username: u.password}
        : null;

    _logger.i('Aggregator: TLS enabled on port ${config.port}');
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

  /// Create a boolean variable node for connection status under an alias folder.
  void _addConnectedVariable(String alias, NodeId parentFolderId) {
    final connNodeId = NodeId.fromString(1, '$alias/connected');
    _server.addVariableNode(
      connNodeId,
      DynamicValue(value: false, typeId: NodeId.boolean, name: '$alias/connected'),
      parentNodeId: parentFolderId,
      accessLevel: const AccessLevelMask(read: true),
    );
    _connectedNodeIds[alias] = connNodeId;
  }

  /// Watch upstream connection status, update connected variables,
  /// invalidate discovered nodes on reconnection, and inject alarms.
  void _watchConnections() {
    for (final wrapper in sharedStateMan.clients) {
      final alias = wrapper.config.serverAlias ?? AggregatorNodeId.defaultAlias;
      // Track whether we've seen a disconnect (to avoid alarm on initial connect)
      var wasDisconnected = false;
      _connectionSubs[alias] = wrapper.connectionStream.listen((status) {
        // Update the connected variable on the aggregator
        final connNodeId = _connectedNodeIds[alias];
        if (connNodeId != null) {
          final connected = status == ConnectionStatus.connected;
          _server.write(connNodeId,
              DynamicValue(value: connected, typeId: NodeId.boolean));
        }

        if (status == ConnectionStatus.connected) {
          _invalidateDiscoveredNodes(alias);
          if (wasDisconnected) {
            _removeDisconnectAlarm(alias);
          }
        } else if (status == ConnectionStatus.disconnected) {
          wasDisconnected = true;
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
      description: 'Lost connection to upstream server "$alias"',
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

  /// Clear discovered node tracking for a specific alias (e.g. on reconnection).
  void _invalidateDiscoveredNodes(String alias) {
    final prefix = '$alias:';
    final keysToRemove = _discoveredNodes.keys
        .where((key) => key.contains(prefix))
        .toList();
    for (final key in keysToRemove) {
      _discoveredNodes.remove(key);
    }
    if (keysToRemove.isNotEmpty) {
      _logger.i('Aggregator: reconnection invalidated ${keysToRemove.length} discovered nodes for "$alias"');
    }
  }

  /// Populate address space from all key mappings.
  Future<void> _populateFromKeyMappings() async {
    // Create folder nodes per unique server alias
    _createAliasFolders();

    for (final entry in sharedStateMan.keyMappings.nodes.entries) {
      final key = entry.key;
      final mapping = entry.value;
      if (mapping.opcuaNode == null) continue;

      await _createAndSubscribeVariable(key, mapping);
    }
  }

  /// Create an object node (folder) and a Discover method for each unique server alias.
  void _createAliasFolders() {
    final aliases = <String>{};
    for (final entry in sharedStateMan.keyMappings.nodes.values) {
      if (entry.opcuaNode == null) continue;
      aliases.add(entry.opcuaNode!.serverAlias ?? AggregatorNodeId.defaultAlias);
    }

    for (final alias in aliases) {
      final folderId = AggregatorNodeId.folderNodeId(alias);
      if (_createdFolders.contains(alias)) continue;
      _server.addObjectNode(folderId, alias);
      _createdFolders.add(alias);
      _addDiscoverMethod(alias);
      _addConnectedVariable(alias, folderId);
      _logger.d('Aggregator: created folder "$alias"');
    }
  }

  /// Add a Discover method node under the alias folder.
  ///
  /// The method accepts a parent NodeId string (e.g. "ns=0;i=85") and
  /// browses the upstream PLC at that node, creating discovered child
  /// nodes in the aggregator's address space.
  void _addDiscoverMethod(String alias) {
    final folderId = AggregatorNodeId.folderNodeId(alias);
    final methodId = NodeId.fromString(1, '$alias/Discover');

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

      // Update in-memory config
      sharedStateMan.config.opcua = merged;

      // Schedule async persistence + reload (guarded against concurrent calls)
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

  /// Persist config to file and trigger reload callback.
  Future<void> _persistAndReload(List<OpcUAConfig> merged) async {
    try {
      if (configFilePath != null) {
        await sharedStateMan.config.toFile(configFilePath!);
        _logger.i('Aggregator: persisted config to $configFilePath');
      }
      if (onReloadClients != null) {
        final result = await onReloadClients!(merged);
        _logger.i('Aggregator: reload callback returned: $result');
      }
    } catch (e) {
      _logger.e('Aggregator: persist/reload failed: $e');
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
            _server.addObjectNode(
              aggregatorNodeId,
              item.browseName,
              parentNodeId: folderId,
            );
            _discoveredNodes[nodeKey] = DateTime.now();
            _logger.d(
                'Aggregator: discovered object "${item.browseName}" from $alias');
          } else if (item.nodeClass == NodeClass.UA_NODECLASS_VARIABLE) {
            final value = await client.read(upstreamNodeId).timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('read timed out for ${item.browseName}'),
            );
            if (!_running) return;
            value.name = item.browseName;
            _server.addVariableNode(
              aggregatorNodeId,
              value,
              parentNodeId: folderId,
              accessLevel: const AccessLevelMask(read: true, write: true),
            );
            _discoveredNodes[nodeKey] = DateTime.now();
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

    if (_createdVariables.contains(nodeKey)) return;

    try {
      // Read initial value from upstream
      final initialValue = await sharedStateMan.read(key);

      // Use the key as the browse name for the variable
      initialValue.name = key;

      // Place variable under its alias folder
      final alias =
          nodeConfig.serverAlias ?? AggregatorNodeId.defaultAlias;
      final parentNodeId = AggregatorNodeId.folderNodeId(alias);

      _server.addVariableNode(
        aggregatorNodeId,
        initialValue,
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: parentNodeId,
      );
      _createdVariables.add(nodeKey);
      _valueCache[nodeKey] = initialValue;
      _nodeToKeyMap[nodeKey] = key;

      // Subscribe to upstream changes and push to aggregator server
      final stream = await sharedStateMan.subscribe(key);
      _upstreamSubs[nodeKey] = stream.listen((value) {
        _valueCache[nodeKey] = value;
        _server.write(aggregatorNodeId, value);
      });

      // Monitor for external client writes and forward to upstream PLC
      _monitorSubs[nodeKey] =
          _server.monitorVariable(aggregatorNodeId).listen((event) {
        final (type, value) = event;
        if (type == 'write' && value != null) {
          _forwardWrite(aggregatorNodeId, value);
        }
      });

      _logger.d('Aggregator: exposed key "$key" as $aggregatorNodeId');
    } catch (e) {
      _logger.w('Failed to create aggregator node for key "$key": $e');
    }
  }

  /// Forward a write from an external client to the upstream PLC.
  void _forwardWrite(NodeId aggregatorNodeId, DynamicValue value) {
    final nodeKey = aggregatorNodeId.toString();
    final key = _nodeToKeyMap[nodeKey];
    if (key != null) {
      sharedStateMan.write(key, value).then((_) {
        _logger.d('Aggregator: forwarded write for key "$key"');
      }).catchError((e) {
        _logger.e('Aggregator: failed to forward write for key "$key": $e');
      });
    } else {
      _logger.w(
          'Aggregator: write to unknown node $aggregatorNodeId (no key mapping)');
    }
  }

  /// Run the server iteration loop. Call from async context.
  /// Returns when [shutdown] is called.
  Future<void> runLoop() async {
    _running = true;
    while (_running) {
      _server.runIterate(waitInterval: false);
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Shutdown and clean up all resources.
  Future<void> shutdown() async {
    _running = false;
    _ttlCleanupTimer?.cancel();

    // Wait for any in-flight discoveries to finish (they check _running)
    if (_pendingDiscoveries.isNotEmpty) {
      await Future.wait(_pendingDiscoveries).catchError((_) => <void>[]);
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
    _createdFolders.clear();
    _createdVariables.clear();
    _discoveredNodes.clear();
    _connectedNodeIds.clear();

    _server.shutdown();
    _server.delete();
  }
}
