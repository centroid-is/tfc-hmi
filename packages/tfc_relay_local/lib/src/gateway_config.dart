/// The gateway's configuration, and the composition that turns it into a
/// running process.
///
/// **This is the file where the phase becomes one program.** Everything else
/// in this package is a piece that passes its own tests; `LocalStateMan` is a
/// `StateManApi` over links, `RelayServer` is a socket over a `StateManApi`,
/// and until something hands the first to the second the design's opening
/// sentence — *"one gateway process owns the plant"* — is a claim about code
/// that has never run together.
///
/// **Why the shape is `data → builders → [Gateway]` and not a constructor with
/// twenty arguments.** `data_acquisition_isolate.dart` reads its configuration
/// out of preferences and builds `StateMan.create` from it; the plant already
/// has `StateManConfig`, `OpcUAConfig`, `ModbusConfig` and `M2400Config` on
/// disk in that shape. Inventing a third convention would mean a migration for
/// a file that is already written, so the per-protocol builders below
/// translate this gateway's link list *into* those types and hand them to
/// `buildModbusDeviceClients` / `M2400ClientWrapper` unchanged. The only thing
/// this file adds is what the incumbent has no place for: one alias per link,
/// checked.
///
/// **What is deliberately NOT here.** No `StateMan` composer — the 2,796-line
/// class whose throwing `read`/`write` is the anti-pattern `StateManApi`
/// replaces never enters the gateway (08-CONTEXT ruling 5). The
/// `DeviceClient`s underneath it do, wrapped.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart' as ua;
import 'package:jbtm/jbtm.dart' show M2400ClientWrapper;
import 'package:tfc_dart/core/modbus_device_client.dart'
    show ModbusDeviceClientAdapter, buildModbusDeviceClients;
import 'package:tfc_dart/core/state_man.dart'
    show
        KeyMappings,
        M2400DeviceClientAdapter,
        ModbusConfig,
        StateManConfig;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';

import 'key_router.dart';
import 'local_browse.dart';
import 'local_state_man.dart';
import 'm2400_upstream_link.dart';
import 'modbus_upstream_link.dart';
import 'opcua_upstream_link.dart';
import 'string_encoding.dart';
import 'upstream_link.dart';
import 'write_translation.dart';

/// What `relay_gateway --help` prints.
///
/// Held in `lib/` rather than in `bin/` so a case can read it: a `bin/` file is
/// not addressable by any `package:` URI, and a usage string nothing asserts
/// on is a usage string that drifts from the flags it documents.
const String gatewayUsage = '''
relay_gateway — the plant's one gateway process.

Usage: dart run tfc_relay_local:relay_gateway --config <path>

  --config <path>   The gateway configuration, JSON. Required.
  --help            This text.

One process reads the configured PLCs and serves every panel over one
WebSocket. SIGINT and SIGTERM shut it down: the server first, then the links.
''';

/// Which protocol wire name a configured link speaks.
///
/// The enum is [UpstreamProtocol], reused rather than re-declared — a second
/// protocol enum would be a second place to add a protocol and one of the two
/// would eventually be missed. Only the *spellings* are here, because
/// `UpstreamProtocol.opcUa` is Dart camel case and a configuration file says
/// `opcua`.
const Map<String, UpstreamProtocol> upstreamProtocolWireNames =
    <String, UpstreamProtocol>{
  'opcua': UpstreamProtocol.opcUa,
  'modbus': UpstreamProtocol.modbus,
  'umas': UpstreamProtocol.umas,
  'm2400': UpstreamProtocol.m2400,
};

String _wireNameOf(UpstreamProtocol protocol) => upstreamProtocolWireNames
    .entries
    .firstWhere((e) => e.value == protocol)
    .key;

/// One configured upstream: an alias, a protocol and an address.
final class UpstreamLinkConfig {
  UpstreamLinkConfig({
    required this.alias,
    required this.protocol,
    required this.endpoint,
    this.username,
    this.password,
    this.certificatePath,
    this.privateKeyPath,
    this.stringEncoding = ServerStringEncoding.utf8,
    this.buildStampKey,
    this.buildStampNamespace = 4,
    this.useIsolate = true,
    this.unitId = 1,
  }) {
    if (alias.trim().isEmpty) {
      throw ArgumentError.value(alias, 'alias',
          'a link with no alias cannot be addressed by a keymapping entry, '
              'cannot own a PIPE.upstream.<alias>.* key and cannot be named in '
              'a status notification — it is a plant nobody can point at');
    }
    if (endpoint.trim().isEmpty) {
      throw ArgumentError.value(endpoint, 'endpoint',
          '$alias has no endpoint: an empty address reaches the socket layer '
              'as a hostname lookup for the empty string, so the gateway '
              'fails with a DNS message instead of a configuration one');
    }
  }

  factory UpstreamLinkConfig.fromJson(Map<String, dynamic> json) {
    final wire = json['protocol'] as String?;
    final protocol = upstreamProtocolWireNames[wire];
    if (protocol == null) {
      throw ArgumentError.value(
          wire,
          'protocol',
          'unknown protocol for link "${json['alias']}". Known: '
              '${upstreamProtocolWireNames.keys.join(', ')}');
    }
    final encoding = json['string_encoding'] as String?;
    return UpstreamLinkConfig(
      alias: json['alias'] as String? ?? '',
      protocol: protocol,
      endpoint: json['endpoint'] as String? ?? '',
      username: json['username'] as String?,
      password: json['password'] as String?,
      certificatePath: json['certificate_path'] as String?,
      privateKeyPath: json['private_key_path'] as String?,
      stringEncoding: switch (encoding) {
        null || 'utf8' => ServerStringEncoding.utf8,
        'latin1' => ServerStringEncoding.latin1,
        _ => throw ArgumentError.value(encoding, 'string_encoding',
            'known encodings are utf8 and latin1 (string_encoding.dart:57-63 '
                'says why the list is closed)'),
      },
      buildStampKey: json['build_stamp_key'] as String?,
      buildStampNamespace: json['build_stamp_namespace'] as int? ?? 4,
      useIsolate: json['use_isolate'] as bool? ?? true,
      unitId: json['unit_id'] as int? ?? 1,
    );
  }

  /// The name this link answers to in keymappings, health keys and status
  /// notifications. Unique across the gateway — see [GatewayConfig].
  final String alias;

  /// Which adapter this link is built from.
  final UpstreamProtocol protocol;

  /// `opc.tcp://host:port` for OPC UA, `host:port` for the rest.
  final String endpoint;

  /// OPC UA user identity, when the server demands one.
  final String? username;
  final String? password;

  /// OPC UA client certificate, when the server demands Sign&Encrypt.
  ///
  /// A path, never bytes: `tls_config.dart:62-69`'s rule, applied to the
  /// upstream side. A config that holds key material is a config that shows up
  /// in a support bundle.
  final String? certificatePath;
  final String? privateKeyPath;

  /// What this server's strings are encoded in (08-CONTEXT ruling 10).
  ///
  /// **In force for `m2400`, `modbus` and `umas` links** — `buildUpstreamLink`
  /// threads a decoder built from this into the client it constructs, and
  /// `freeze_test.dart`'s freeze 7 stops that silently coming undone.
  ///
  /// **Not in force for `opcua` links**, and that is a stated gap rather than
  /// an oversight: the binding decodes before Dart sees a byte, so the hook
  /// has to go in the binding. Setting `latin1` on an OPC UA link is accepted
  /// and has no effect today. At this plant that costs nothing — the TwinCAT
  /// servers emit UTF-8 and the Latin-1 devices are the weighers and the
  /// Saia-over-Modbus box erector, all of which are covered.
  final ServerStringEncoding stringEncoding;

  /// The optional PLC build-stamp tag, the third input to the epoch
  /// (08-CONTEXT ruling 7). Absent is the ordinary case and the epoch is still
  /// two inputs wide.
  final String? buildStampKey;

  /// The namespace [buildStampKey] lives in. Four, because that is the
  /// application namespace every TwinCAT server at this plant publishes `GVL_*`
  /// under; a server that puts it elsewhere says so in one line of config
  /// rather than in a code change.
  final int buildStampNamespace;

  /// OPC UA only: run the blocking FFI on a worker isolate. True in
  /// production, where the gateway's tick must not be blocked by a PLC.
  final bool useIsolate;

  /// Modbus only: the unit id. Defaulted to 1, which is what every device at
  /// this plant is set to.
  final int unitId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'alias': alias,
        'protocol': _wireNameOf(protocol),
        'endpoint': endpoint,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (certificatePath != null) 'certificate_path': certificatePath,
        if (privateKeyPath != null) 'private_key_path': privateKeyPath,
        if (stringEncoding != ServerStringEncoding.utf8)
          'string_encoding': stringEncoding.name,
        if (buildStampKey != null) 'build_stamp_key': buildStampKey,
        if (buildStampKey != null && buildStampNamespace != 4)
          'build_stamp_namespace': buildStampNamespace,
        if (!useIsolate) 'use_isolate': false,
        if (unitId != 1) 'unit_id': unitId,
      };

  /// `host` and `port`, for the two protocols whose endpoint is not a URI.
  (String, int) get hostPort {
    final cut = endpoint.lastIndexOf(':');
    if (cut < 0) return (endpoint, protocol == UpstreamProtocol.m2400 ? 52211 : 502);
    final port = int.tryParse(endpoint.substring(cut + 1));
    if (port == null) {
      throw ArgumentError.value(endpoint, 'endpoint',
          '$alias: "${endpoint.substring(cut + 1)}" is not a port number');
    }
    return (endpoint.substring(0, cut), port);
  }
}

/// Everything one gateway process needs to know.
///
/// Pure data, in `ServerConfig`'s style (`server_config.dart:4-5`): nothing
/// here reads a file, opens a socket or starts a clock. The one thing the
/// constructor does is **refuse** — see the duplicate-alias check.
final class GatewayConfig {
  GatewayConfig({
    required this.server,
    required this.links,
    required this.keyMappingsPath,
    this.staleAfter = const Duration(seconds: 5),
    this.linger = Duration.zero,
  }) {
    // T-08-50, and the reason it is here rather than at first use: the router
    // offers a key to every link in order and takes the first claim
    // (`key_router.dart`), so two links called `ST101` route a key to whichever
    // one the JSON happened to list first. The symptom downstream is a motor
    // speed that reads a different motor, on a screen that says nothing is
    // wrong. `KeyRouter` has an `ambiguousAliases` set for the case it cannot
    // refuse; this one it can, so it is refused where it is cheapest to
    // diagnose — at the file.
    final seen = <String?, String>{};
    for (final link in links) {
      final normalized = StateManConfig.normalizeAlias(link.alias);
      final first = seen[normalized];
      if (first != null) {
        throw ArgumentError('two upstream links share the alias '
            '"${link.alias}" (also spelled "$first"). The router offers each '
            'key to every link in order and takes the first claim, so which '
            'PLC answers a key would depend on the order they are listed in '
            'this file. Give each link its own alias');
      }
      seen[normalized] = link.alias;
    }
  }

  factory GatewayConfig.fromJson(Map<String, dynamic> json) => GatewayConfig(
        server: serverConfigFromJson(
            (json['server'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
        links: <UpstreamLinkConfig>[
          for (final raw in (json['links'] as List? ?? const <dynamic>[]))
            UpstreamLinkConfig.fromJson((raw as Map).cast<String, dynamic>()),
        ],
        keyMappingsPath: json['key_mappings'] as String? ?? '',
        staleAfter:
            Duration(milliseconds: json['stale_after_ms'] as int? ?? 5000),
        linger: Duration(milliseconds: json['linger_ms'] as int? ?? 0),
      );

  /// Reads and parses [path]. Not a constructor, because a factory that does
  /// file IO is a factory a test cannot call.
  static GatewayConfig readFile(String path) => GatewayConfig.fromJson(
      (jsonDecode(File(path).readAsStringSync()) as Map)
          .cast<String, dynamic>());

  /// The front end: port, TLS, tokens, tick, `publisherId`.
  final ServerConfig server;

  /// The plant, one entry per PLC. Aliases are unique — the constructor is
  /// what makes that true.
  final List<UpstreamLinkConfig> links;

  /// Where the keymapping file lives.
  ///
  /// A path and not the mappings themselves, because the mappings are
  /// reloadable at runtime (`KeyRouter.applyKeyMappings` diffs them in place)
  /// and a config object that held them would be the wrong lifetime for both.
  final String keyMappingsPath;

  /// How long a value may go unheard-of before it stops claiming to be current.
  final Duration staleAfter;

  /// How long an upstream subscription survives its last client subscriber
  /// (SRV-07). Zero is the correct gateway default.
  final Duration linger;

  /// The per-alias encoding table, derived from [links] rather than configured
  /// twice. A second list of aliases is a second list to get out of step.
  StringEncodingConfig get stringEncodings => StringEncodingConfig(byAlias: {
        for (final link in links) link.alias: link.stringEncoding,
      });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'server': serverConfigToJson(server),
        'links': <Map<String, dynamic>>[for (final l in links) l.toJson()],
        'key_mappings': keyMappingsPath,
        'stale_after_ms': staleAfter.inMilliseconds,
        'linger_ms': linger.inMilliseconds,
      };
}

/// `ServerConfig` out of JSON.
///
/// **Here rather than on `ServerConfig`.** That class is in `tfc_relay_server`,
/// which has zero native dependencies and no opinion about where a deployment
/// keeps its configuration; every one of its ~30 fields is already validated in
/// its own constructor, so this function's whole job is to name the wire
/// spellings. Only the fields a deployment actually sets are read — the rest
/// keep the defaults the server package argued for, and a config file that
/// wanted to override a backpressure ceiling would add the line here in the
/// commit that needed it.
ServerConfig serverConfigFromJson(Map<String, dynamic> json) {
  final tls = (json['tls'] as Map?)?.cast<String, dynamic>();
  final auth = (json['auth'] as Map?)?.cast<String, dynamic>();
  return ServerConfig(
    port: json['port'] as int? ?? 0,
    address: json['address'] == null
        ? InternetAddress.anyIPv4
        : InternetAddress(json['address'] as String),
    tick: Duration(milliseconds: json['tick_ms'] as int? ?? 100),
    publisherId: json['publisher_id'] as String?,
    allowedOrigins: <String>[
      for (final o in (json['allowed_origins'] as List? ?? const <dynamic>[]))
        o as String,
    ],
    tls: tls == null
        ? null
        : TlsConfig(
            chainPath: tls['chain_path'] as String? ?? '',
            keyPath: tls['key_path'] as String? ?? '',
            keyPassword: tls['key_password'] as String?,
          ),
    auth: auth == null
        ? null
        : AuthConfig(tokenFilePath: auth['token_file'] as String? ?? ''),
  );
}

/// The inverse, for the round trip. Secrets are carried because they were
/// given: this is the config the operator wrote, echoed back.
Map<String, dynamic> serverConfigToJson(ServerConfig config) =>
    <String, dynamic>{
      'port': config.port,
      'address': config.address.address,
      'tick_ms': config.tick.inMilliseconds,
      if (config.publisherId != null) 'publisher_id': config.publisherId,
      if (config.allowedOrigins.isNotEmpty)
        'allowed_origins': config.allowedOrigins,
      if (config.tls != null)
        'tls': <String, dynamic>{
          'chain_path': config.tls!.chainPath,
          'key_path': config.tls!.keyPath,
          if (config.tls!.keyPassword != null)
            'key_password': config.tls!.keyPassword,
        },
      if (config.auth != null)
        'auth': <String, dynamic>{'token_file': config.auth!.tokenFilePath},
    };

/// The keys in [mappings] that claim a name inside the reserved `PIPE.` prefix.
///
/// **HLTH-03 is per key** (T-08-51). A gateway that refused to boot because one
/// mapping entry was wrong would be a plant that is down because one mapping
/// entry is wrong: every other tag on the file is fine, and the operator's
/// screen going black for a typo is a worse outcome than one box reading
/// `errorConfig`. So this returns the offenders for the boot log and the
/// gateway starts.
///
/// The predicate is `PipeKeys.isPipeKey` and not a list, so a health key
/// invented in a later phase is reserved on the day it is invented
/// (`pipe_keys.dart:40-45`). `KeyRouter.applyKeyMappings` refuses the same set
/// again at ingest with a `RouteRefusal` per key — this function exists to name
/// them *once, at boot*, in the log, rather than one line per panel that asks.
Set<String> reservedKeyMappingNames(KeyMappings mappings) => <String>{
      for (final key in mappings.nodes.keys)
        if (PipeKeys.isPipeKey(key)) key,
    };

/// The server's error seam, pointed at the gateway's log.
///
/// The server package defaults to `reportToStderr`, which is right for a
/// library with no logger of its own; a process that has one should not print
/// half its diagnostics through a second channel with a different format.
void Function(Object, StackTrace, String) _logServerError(Logger log) =>
    (error, stack, where) => log.e('[server] $where: $error',
        // `StackTrace.empty` is this package's "condition, not defect" marker
        // (`relay_server.dart:357-361`): the message is already complete and a
        // trace would be noise.
        stackTrace: identical(stack, StackTrace.empty) ? null : stack);

/// One running gateway: the plant, the front end, and the order they stop in.
final class Gateway {
  Gateway._(this.plant, this.server, this.links, this.refusedKeys, this._status);

  /// The `StateManApi` the server is a projection of.
  final LocalStateMan plant;

  /// The socket. Its `api` is [plant] — that identity is the phase.
  final RelayServer server;

  /// The links, held for the log line and for nothing else: their lifecycle is
  /// [plant]'s (`local_state_man.dart:137-145`).
  final List<UpstreamLink> links;

  /// What the keymapping file claimed inside the `PIPE.` prefix and did not get.
  final Set<String> refusedKeys;

  /// The plant's announcements, on the server's notification path.
  ///
  /// **Held here rather than left to the caller, and that is a fix rather than
  /// a preference.** It was `main`'s to wire, one line after `buildGateway`
  /// returned, and the end-to-end leg found what that costs: a `Gateway` built
  /// by anything other than that one `main` — every test in this package, and
  /// any deployment that embeds the composition — served panels that never
  /// heard a word about a PLC going down. The health keys still flipped, so
  /// nothing looked broken; SRV-08's announcement was simply absent, which is
  /// the failure mode that is hardest to notice and easiest to ship.
  ///
  /// A composition root that returns a half-composed object is not a
  /// composition root. It is cancelled in [stop], before the server closes, so
  /// no frame is emitted into a session that is already draining.
  final StreamSubscription<StatusParams> _status;

  var _stopped = false;

  /// **Server first, then the plant.** The reverse order is the bug: a link
  /// disposed under a live session leaves the session serving a `ValueStore`
  /// nobody is updating, and that store reads *fresh* for exactly as long as it
  /// takes the freshness sweep to notice — which on the default `staleAfter` is
  /// five seconds of a panel showing confident, current-looking numbers from a
  /// PLC this process has already hung up on (T-08-52). Closing the socket
  /// first means the panel sees a closed socket, which is a thing it knows how
  /// to display.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _status.cancel();
    await server.close();
    await plant.dispose();
  }
}

/// Builds the links, the router and `LocalStateMan` — allocation only.
///
/// Nothing here connects. `LocalStateMan.start()` is what opens the links, and
/// keeping the two apart is what lets a case build the whole plant side without
/// a PLC in the room.
Future<Gateway> buildGateway(
  GatewayConfig config, {
  required KeyMappings mappings,
  required Logger log,
  void Function(Object error, StackTrace stack, String where)? onError,
}) async {
  final refused = reservedKeyMappingNames(mappings);
  final links = <UpstreamLink>[];
  for (final link in config.links) {
    links.add(await buildUpstreamLink(link, mappings: mappings));
  }
  // Built empty and then fed, deliberately: `applyKeyMappings` is what
  // *refuses* a reserved name, per key, and it hands back the refusals. Passing
  // the mappings to the constructor would put them in force without anything
  // ever naming what it dropped, which is HLTH-03 happening silently.
  final router =
      KeyRouter.overLinks(links, mappings: KeyMappings(nodes: {}));
  router.applyKeyMappings(mappings);
  final plant = LocalStateMan(
    links: links,
    router: router,
    staleAfter: config.staleAfter,
    linger: config.linger,
    // **Deliberately empty, and 10-01 owes the wiring** (08-REVIEW WR-07).
    // This used to be a local that was declared, never written to, and passed
    // anyway — which reads as wired and is not: every gateway built through
    // here had live browse unreachable, and only a caller constructing
    // `LocalStateMan` directly (that is, the tests) could see the feature
    // 08-11 shipped.
    //
    // It cannot be filled here as things stand, and that is the substance of
    // the finding rather than an excuse: `OpcUaAddressSpace` needs a
    // `ua.ClientApi`, and nothing in this function has one — the adapters
    // construct their clients inside `connect()`, which is `LocalStateMan.
    // start()`'s job and happens after this returns. Wiring it means a lazy
    // per-alias resolution the browse map's `final` field cannot express, so
    // it belongs to the plan that owns browse rather than to a review fix
    // smuggling a design change past a scope fence.
    //
    // Until then the keymapping tree is browsable and the live one is not,
    // which `local_state_man.dart` already documents as a *configuration* gap
    // that lands in `LocalBrowse.incidents` rather than in an exception.
    browseSpaces: const <String, UpstreamAddressSpace>{},
  );
  final server = RelayServer(
    // **The identity this whole phase exists to make true.** The server's
    // `StateManApi` source is the plant; 08-12's per-session health overlay is
    // chained over it inside `RelayServer.start`, and the policy decorator over
    // that. Two overlays, one shared instance.
    api: plant,
    config: config.server,
    onError: onError ?? _logServerError(log),
  );
  return Gateway._(
    plant,
    server,
    links,
    refused,
    // SRV-08's last connection, made HERE and not by the caller — see
    // [Gateway._status] for what leaving it to the caller cost.
    wireStatusNotifications(plant, server,
        publisherId: config.server.publisherId),
  );
}

/// One configured link, built.
///
/// A function per protocol would be four functions with one caller each; a
/// switch here keeps the four next to each other, which is where a reader
/// compares them.
Future<UpstreamLink> buildUpstreamLink(
  UpstreamLinkConfig config, {
  required KeyMappings mappings,
}) async {
  switch (config.protocol) {
    case UpstreamProtocol.opcUa:
      return OpcUaUpstreamLink(
        alias: config.alias,
        endpoint: config.endpoint,
        useIsolate: config.useIsolate,
        buildStampNode: config.buildStampKey == null
            ? null
            : ua.NodeId.fromString(
                config.buildStampNamespace, config.buildStampKey!),
        // **The credentialed client is built here and injected**, because the
        // adapter's own fallback builds an anonymous one. This is the same
        // division `state_man.dart:1517-1570` makes — the composer builds the
        // `Client` from the server's credentials and hands it over — and it is
        // why the adapter takes a `client:` seam at all. An anonymous server
        // gets no injection, so nothing is allocated before `connect`.
        //
        // **Handed over, not lent** (08-REVIEW WR-03): the link owns it from
        // here and deletes it in `dispose`, which is what `Gateway.stop`
        // reaches through `plant.dispose()`. Nothing in this file may touch it
        // afterwards, and nothing does — at `useIsolate: true` it is a spawned
        // isolate, and an undeleted one keeps the VM alive past `stop()`.
        client: await _opcUaClient(config),
      );
    case UpstreamProtocol.modbus:
    case UpstreamProtocol.umas:
      final (host, port) = config.hostPort;
      final clients = buildModbusDeviceClients(
        <ModbusConfig>[
          ModbusConfig(host: host, port: port, unitId: config.unitId)
            ..serverAlias = config.alias
            ..umasEnabled = config.protocol == UpstreamProtocol.umas,
        ],
        mappings,
        // **Ruling 10, wired** (08-REVIEW WR-01). This function is the only
        // place that knows both the alias and the client being constructed,
        // which is precisely why the decoder is threaded from here rather
        // than reached for inside jbtm or umas_types — neither has a server
        // alias in scope and neither should.
        decodeStringFor: (_) => latin1DecoderFor(config.stringEncoding),
      );
      return ModbusUpstreamLink.wrapping(
        clients.single as ModbusDeviceClientAdapter,
        alias: config.alias,
      );
    case UpstreamProtocol.m2400:
      final (host, port) = config.hostPort;
      return M2400UpstreamLink(
        alias: config.alias,
        client: M2400DeviceClientAdapter(
          // The weighers are the plant's Latin-1 devices (08-RESEARCH §H.3),
          // so this is the wire that makes `"string_encoding": "latin1"` mean
          // something. Before it, the value was parsed, validated, echoed in
          // toJson — and every actual decode was still
          // `utf8.decode(allowMalformed: true)`, which is the behaviour the
          // module exists to replace.
          M2400ClientWrapper(host, port,
              decodeBytes: latin1DecoderFor(config.stringEncoding)),
          serverAlias: config.alias,
        ),
      );
  }
}

/// The OPC UA client, when the configuration names an identity for it.
///
/// Null when it does not, which is the ordinary case at this plant and which
/// leaves the adapter to build its own inside `connect()` — nothing allocated
/// until something is dialled.
Future<ua.ClientApi?> _opcUaClient(UpstreamLinkConfig config) async {
  final hasUser = config.username != null && config.password != null;
  final hasCert =
      config.certificatePath != null && config.privateKeyPath != null;
  if (!hasUser && !hasCert) return null;
  final cert =
      hasCert ? File(config.certificatePath!).readAsBytesSync() : null;
  final key = hasCert ? File(config.privateKeyPath!).readAsBytesSync() : null;
  final mode = hasCert
      ? ua.MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT
      : ua.MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE;
  return config.useIsolate
      ? await ua.ClientIsolate.create(
          username: config.username,
          password: config.password,
          certificate: cert,
          privateKey: key,
          securityMode: mode,
          logLevel: ua.LogLevel.UA_LOGLEVEL_ERROR,
        )
      : ua.Client(
          username: config.username,
          password: config.password,
          certificate: cert,
          privateKey: key,
          securityMode: mode,
          logLevel: ua.LogLevel.UA_LOGLEVEL_ERROR,
        );
}

/// The shutdown handler both signals share.
///
/// **In `lib/` and not in `main`, for the same reason [gatewayUsage] is**: a
/// `bin/` file is not addressable by any `package:` URI, so logic that lives
/// there is logic nothing can assert on — and 08-REVIEW WR-12 is two defects
/// that lived there for exactly that long.
///
///  * **The latch was the completer.** `if (stopped.isCompleted) return;` was
///    checked at the top and `stopped.complete()` reached only *after*
///    `gateway.stop()` finished, so a second SIGTERM arriving during teardown
///    passed the guard. `Gateway.stop` has its own `_stopped` latch, so the
///    second call returned at once — and then completed an already-complete
///    `Completer`, which throws `StateError` out of a stream callback where
///    nothing catches. A container runtime sending SIGTERM and then SIGTERM
///    again is ordinary, and so is a shell where somebody presses Ctrl-C
///    twice.
///  * **A throwing `stop()` hung the process forever.** `stopped` was never
///    completed, so `await stopped.future` never returned — with the socket
///    already closed. The gateway would sit there, serving nothing, until it
///    was killed.
///
/// So: latch on entry, and complete in a `finally`. A failed stop is logged
/// and the process still exits, because a gateway that cannot tear down
/// cleanly must still tear down.
Future<void> Function(ProcessSignal) gatewayShutdown({
  required Future<void> Function() stop,
  required Completer<void> stopped,
  required void Function(ProcessSignal signal) onSignal,
  required void Function(Object error, StackTrace stack) onError,
}) {
  var stopping = false;
  return (ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    onSignal(signal);
    try {
      await stop();
    } catch (error, stack) {
      onError(error, stack);
    } finally {
      // Guarded even under the latch: belt and braces on the one line whose
      // failure mode is an uncatchable throw out of a signal handler.
      if (!stopped.isCompleted) stopped.complete();
    }
  };
}

/// Wires the plant's link-state announcements onto the server's status
/// notification path — the last piece of SRV-08.
///
/// **The DTO crosses whole and is never rebuilt as a map.** That is 03-REVIEW
/// WR-06, recorded at `relay_server.dart:702-712`: this channel once sent a
/// hand-built `{'fatal': ...}` under the `status` method, a conforming client
/// routed it through `StatusParams.fromJson`, and `json['alias'] as String`
/// threw a `TypeError` on null — on the notification path, where there is no
/// request to fail and nothing catches. So the one frame whose job was to
/// explain a wiring failure was the one frame a conforming client could not
/// read. `StatusParams.toJson` is the only spelling here.
///
/// One frame per link event, never one per key: fifteen hundred keys behind one
/// PLC is fifteen hundred frames for one event, arriving in the instant the
/// panel is already re-rendering every box they are all about
/// (`local_state_man.dart:1414-1421`).
StreamSubscription<StatusParams> wireStatusNotifications(
  LocalStateMan plant,
  RelayServer server, {
  String? publisherId,
}) =>
    plant.statusStream.listen((status) {
      final frame = jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': Methods.status,
        'params': status.publisherId == null && publisherId != null
            ? StatusParams(
                alias: status.alias,
                state: status.state,
                error: status.error,
                publisherId: publisherId,
              ).toJson()
            : status.toJson(),
      });
      for (final session in server.sessions.sessions) {
        session.emit(frame);
      }
    });
