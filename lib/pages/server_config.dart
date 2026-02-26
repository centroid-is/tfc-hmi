import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:cryptography_flutter/cryptography_flutter.dart' as crypto_fl;

import '../widgets/base_scaffold.dart';
import '../widgets/preferences.dart';
import 'package:open62541/open62541.dart' show NodeId, DynamicValue;
import 'package:tfc_dart/core/aggregator_server.dart'
    show AggregatorConfig, AggregatorNodeId;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/database.dart';
import '../providers/state_man.dart';
import '../providers/preferences.dart';
import '../providers/database.dart';
// TODO not the best place but cross platform
import 'package:package_info_plus/package_info_plus.dart';

part 'server_config.g.dart';

const _certPlaceholder = "todo";

// ===================== Secure Envelope (Encryption Helper) =====================
class SecureEnvelope {
  static final Random _rng = Random.secure();
  static const String aadStr = 'centroid-v1';
  static const int _kdfIterations =
      200000; // tune per device; higher = slower/stronger

  static List<int> _rand(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));

  /// Encrypts [jsonConfig] with PBKDF2(HMAC-SHA256) -> AES-256-GCM
  /// using [compiledPrefix]+[exportPostfix] as the passphrase.
  static Future<Map<String, dynamic>> encrypt({
    required Map<String, dynamic> jsonConfig,
    required String compiledPrefix,
    required String exportPostfix,
  }) async {
    // Ensure fast native backends where available
    crypto.Cryptography.instance =
        crypto_fl.FlutterCryptography.defaultInstance;

    final passphrase = '$compiledPrefix$exportPostfix';

    final salt = _rand(16);
    final kdf = crypto.Pbkdf2(
      macAlgorithm: crypto.Hmac.sha256(),
      iterations: _kdfIterations,
      bits: 256,
    );
    final key = await kdf.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(passphrase)),
      nonce: salt, // salt
    );

    final algo = crypto.AesGcm.with256bits();
    final nonce = _rand(12);

    final clear = utf8.encode(jsonEncode(jsonConfig));
    final box = await algo.encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(aadStr),
    );

    return {
      'version': 1,
      'kdf': {
        'name': 'pbkdf2-hmac-sha256',
        'iterations': _kdfIterations,
        'salt_b64': base64Encode(salt),
      },
      'cipher': {
        'name': 'aes-256-gcm',
        'nonce_b64': base64Encode(nonce),
      },
      'aad': aadStr,
      'ciphertext_b64': base64Encode(box.cipherText),
      'tag_b64': base64Encode(box.mac.bytes),
    };
  }

  /// Decrypts an envelope to a JSON Map using [compiledPrefix]+[postfix].
  static Future<Map<String, dynamic>> decrypt({
    required Map<String, dynamic> envelope,
    required String compiledPrefix,
    required String postfix,
  }) async {
    crypto.Cryptography.instance =
        crypto_fl.FlutterCryptography.defaultInstance;

    final passphrase = '$compiledPrefix$postfix';

    final salt = base64Decode(envelope['kdf']['salt_b64']);
    final iterations = envelope['kdf']['iterations'] as int;
    final nonce = base64Decode(envelope['cipher']['nonce_b64']);
    final cipherText = base64Decode(envelope['ciphertext_b64']);
    final tag = base64Decode(envelope['tag_b64']);
    final aad = utf8.encode(envelope['aad'] as String);

    final kdf = crypto.Pbkdf2(
      macAlgorithm: crypto.Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await kdf.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    final algo = crypto.AesGcm.with256bits();
    final clear = await algo.decrypt(
      crypto.SecretBox(cipherText, nonce: nonce, mac: crypto.Mac(tag)),
      secretKey: key,
      aad: aad,
    );

    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }
}

// ===================== Certificate Generator (unchanged) =====================
class CertificateGenerator extends StatefulWidget {
  final Function(Uint8List?, Uint8List?) onCertificatesGenerated;

  const CertificateGenerator({
    super.key,
    required this.onCertificatesGenerated,
  });

  @override
  State<CertificateGenerator> createState() => _CertificateGeneratorState();
}

class _CertificateGeneratorState extends State<CertificateGenerator> {
  bool _isGenerating = false;
  String? _error;
  late TextEditingController _commonNameController;
  late TextEditingController _organizationController;
  late TextEditingController _validityDaysController;
  late TextEditingController _countryController;
  late TextEditingController _stateController;
  late TextEditingController _localityController;
  Uint8List? _cert;
  Uint8List? _key;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with locale-aware defaults
    _initializeControllers();
  }

  void _initializeControllers() {
    final locale = Platform.localeName;
    final countryCode = locale.split('_').last;

    _commonNameController = TextEditingController(text: 'example.com');
    _organizationController =
        TextEditingController(text: 'Your company/organization name');
    _validityDaysController = TextEditingController(text: '365');
    _countryController = TextEditingController(text: countryCode);
    _stateController =
        TextEditingController(text: _getDefaultState(countryCode));
    _localityController =
        TextEditingController(text: _getDefaultLocality(countryCode));
  }

  String _getDefaultState(String countryCode) {
    // Provide default state/province based on country
    const stateMap = {
      'US': 'State',
      'CA': 'Province',
      'GB': 'England',
      'DE': 'Bundesland',
      'FR': 'Région',
      'IT': 'Regione',
      'ES': 'Comunidad',
      'NL': 'Provincie',
      'AU': 'State',
      'BR': 'Estado',
      'MX': 'Estado',
      'IS': 'Region',
    };
    return stateMap[countryCode] ?? 'State';
  }

  String _getDefaultLocality(String countryCode) {
    // Provide default city based on country
    const localityMap = {
      'US': 'City',
      'CA': 'City',
      'GB': 'London',
      'DE': 'Berlin',
      'FR': 'Paris',
      'IT': 'Rome',
      'ES': 'Madrid',
      'NL': 'Amsterdam',
      'AU': 'Sydney',
      'BR': 'São Paulo',
      'MX': 'Mexico City',
      'IS': 'Reykjavik',
    };
    return localityMap[countryCode] ?? 'City';
  }

  @override
  void dispose() {
    _commonNameController.dispose();
    _organizationController.dispose();
    _validityDaysController.dispose();
    _countryController.dispose();
    _stateController.dispose();
    _localityController.dispose();
    super.dispose();
  }

  Future<void> _generateCertificates() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final commonName = _commonNameController.text.trim();
      final organization = _organizationController.text.trim();
      final validityDays = int.tryParse(_validityDaysController.text) ?? 365;
      final country = _countryController.text.trim();
      final state = _stateController.text.trim();
      final locality = _localityController.text.trim();

      if (commonName.isEmpty) {
        throw Exception('Common Name is required');
      }

      // Generate RSA key pair
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);

      // Create certificate signing request with locale-aware attributes
      final attributes = {
        'CN': commonName,
        'O': organization,
        'OU': 'OPC-UA',
        'C': country,
        'ST': state,
        'L': locality,
      };

      final csr = X509Utils.generateRsaCsrPem(
        attributes,
        keyPair.privateKey as RSAPrivateKey,
        keyPair.publicKey as RSAPublicKey,
        san: ['localhost', '127.0.0.1'],
      );

      // Generate self-signed certificate
      final certPem = X509Utils.generateSelfSignedCertificate(
        keyPair.privateKey as RSAPrivateKey,
        csr,
        validityDays,
        sans: ['localhost', '127.0.0.1'],
      );

      Uint8List certFile = utf8.encode(certPem);
      Uint8List keyString = utf8.encode(CryptoUtils.encodeRSAPrivateKeyToPem(
          keyPair.privateKey as RSAPrivateKey));

      setState(() {
        _cert = certFile;
        _key = keyString;
      });
      widget.onCertificatesGenerated(certFile, keyString);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificates generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Certificate generation form
          TextField(
            controller: _commonNameController,
            decoration: const InputDecoration(
              labelText: 'Common Name (CN)',
              hintText: 'example.com',
              prefixIcon: FaIcon(FontAwesomeIcons.server, size: 16),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _organizationController,
            decoration: const InputDecoration(
              labelText: 'Organization',
              hintText: 'Your company/organization name',
              prefixIcon: FaIcon(FontAwesomeIcons.building, size: 16),
            ),
          ),
          const SizedBox(height: 12),

          // Location fields
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 400;
              if (isNarrow) {
                return Column(
                  children: [
                    TextField(
                      controller: _countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country (C)',
                        hintText: 'US/UK/DE/FR/IT/ES/NL/AU/BR/MX/IS',
                        prefixIcon: FaIcon(FontAwesomeIcons.flag, size: 16),
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(2),
                        UpperCaseTextFormatter(),
                      ],
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State/Province (ST)',
                        hintText: 'State',
                        prefixIcon: FaIcon(FontAwesomeIcons.map, size: 16),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country (C)',
                        hintText: 'US/UK/DE/FR/IT/ES/NL/AU/BR/MX/IS',
                        prefixIcon: FaIcon(FontAwesomeIcons.flag, size: 16),
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(2),
                        UpperCaseTextFormatter(),
                      ],
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State/Province (ST)',
                        hintText: 'State',
                        prefixIcon: FaIcon(FontAwesomeIcons.map, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _localityController,
            decoration: const InputDecoration(
              labelText: 'Locality/City (L)',
              hintText: 'City',
              prefixIcon: FaIcon(FontAwesomeIcons.city, size: 16),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _validityDaysController,
            decoration: const InputDecoration(
              labelText: 'Validity (days)',
              hintText: '365',
              prefixIcon: FaIcon(FontAwesomeIcons.calendar, size: 16),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // Error display
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.error),
              ),
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.triangleExclamation,
                      color: Theme.of(context).colorScheme.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Certificate status
          if (_cert != null && _key != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.circleCheck,
                          color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Certificates generated successfully!',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateCertificates,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const FaIcon(FontAwesomeIcons.plus, size: 16),
                  label: Text(_isGenerating
                      ? 'Generating...'
                      : 'Generate Certificates'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ServerConfigPage extends ConsumerWidget {
  const ServerConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch a simple counter that gets incremented on import
    final refreshKey = ref.watch(refreshKeyProvider);

    return BaseScaffold(
      title: 'Server Configuration',
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Database Configuration Section
            DatabaseConfigWidget(key: ValueKey('db_$refreshKey')),
            const SizedBox(height: 16),

            // OPC-UA Servers Section
            _OpcUAServersSection(key: ValueKey('opcua_$refreshKey')),
            const ImportExportCard(),
          ],
        ),
      ),
    );
  }
}

@riverpod
class RefreshKey extends _$RefreshKey {
  @override
  int build() => 0;

  void increment() => state++;
}

/// Wraps an OpcUAConfig with has_credentials/has_tls flags from the aggregator.
/// Used in aggregation mode where upstream servers are fetched via getOpcUaClients.
class RemoteServerInfo {
  OpcUAConfig config;
  final bool hasCredentials;
  final bool hasTls;
  bool credentialsEdited = false;
  bool tlsEdited = false;

  RemoteServerInfo({
    required this.config,
    this.hasCredentials = false,
    this.hasTls = false,
  });
}

class _OpcUAServersSection extends ConsumerStatefulWidget {
  const _OpcUAServersSection({super.key});
  @override
  ConsumerState<_OpcUAServersSection> createState() =>
      _OpcUAServersSectionState();
}

class _OpcUAServersSectionState extends ConsumerState<_OpcUAServersSection> {
  StateManConfig? _config;
  StateManConfig? _savedConfig;
  bool _isLoading = false;
  String? _error;

  // Aggregation mode: upstream servers fetched from aggregator via OPC UA
  List<RemoteServerInfo>? _remoteServers;
  List<RemoteServerInfo>? _savedRemoteServers;
  bool _remoteLoading = false;
  String? _remoteError;

  bool get _isAggregationMode =>
      _config?.aggregator?.enabled == true;

  bool get _serverListIsEmpty {
    if (_isAggregationMode) {
      return _remoteServers == null || _remoteServers!.isEmpty;
    }
    return _config?.opcua.isEmpty ?? true;
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _config = await StateManConfig.fromPrefs(
          await ref.read(preferencesProvider.future));
      _savedConfig = _config?.copy();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    // In aggregation mode, also fetch upstream servers from the aggregator
    if (_isAggregationMode) {
      await _fetchUpstreamServers();
    }
  }

  /// Fetch upstream server list from the aggregator via getOpcUaClients method.
  Future<void> _fetchUpstreamServers() async {
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });

    try {
      final stateMan = await ref.read(stateManProvider.future);
      if (!stateMan.aggregationMode || stateMan.clients.isEmpty) {
        setState(() {
          _remoteServers = [];
          _savedRemoteServers = [];
          _remoteLoading = false;
        });
        return;
      }

      final client = stateMan.clients.first.client;
      final result = await client.call(
        NodeId.objectsFolder,
        NodeId.fromString(1, 'getOpcUaClients'),
        [],
      );

      final jsonStr = result.first.value as String;
      final List<dynamic> decoded = jsonDecode(jsonStr) as List<dynamic>;

      final servers = decoded.map((entry) {
        final map = entry as Map<String, dynamic>;
        return RemoteServerInfo(
          config: OpcUAConfig()
            ..endpoint = map['endpoint'] as String? ?? ''
            ..serverAlias = map['server_alias'] as String?,
          hasCredentials: map['has_credentials'] as bool? ?? false,
          hasTls: map['has_tls'] as bool? ?? false,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _remoteServers = servers;
          _savedRemoteServers = servers.map((s) => RemoteServerInfo(
            config: OpcUAConfig()
              ..endpoint = s.config.endpoint
              ..serverAlias = s.config.serverAlias,
            hasCredentials: s.hasCredentials,
            hasTls: s.hasTls,
          )).toList();
          _remoteLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _remoteError = e.toString();
          _remoteLoading = false;
        });
      }
    }
  }

  bool get _hasUnsavedChanges {
    if (_config == null || _savedConfig == null) return false;
    final currentJson = jsonEncode(_config!.toJson());
    final savedJson = jsonEncode(_savedConfig!.toJson());
    final localChanged = currentJson != savedJson;

    if (_isAggregationMode) {
      return localChanged || _hasRemoteChanges;
    }
    return localChanged;
  }

  bool get _hasRemoteChanges {
    if (_remoteServers == null || _savedRemoteServers == null) return false;
    if (_remoteServers!.length != _savedRemoteServers!.length) return true;
    for (var i = 0; i < _remoteServers!.length; i++) {
      final cur = _remoteServers![i];
      final saved = _savedRemoteServers![i];
      if (cur.config.endpoint != saved.config.endpoint ||
          cur.config.serverAlias != saved.config.serverAlias ||
          cur.credentialsEdited ||
          cur.tlsEdited) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;

    try {
      // Always save local config (aggregator endpoint, toggle, etc.)
      _config!.toPrefs(await ref.read(preferencesProvider.future));
      _savedConfig = await StateManConfig.fromPrefs(
          await ref.read(preferencesProvider.future));

      // In aggregation mode, also push upstream servers to aggregator
      if (_isAggregationMode && _remoteServers != null) {
        await _saveUpstreamServers();
      }

      ref.invalidate(stateManProvider);
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Configuration saved successfully!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save configuration: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  /// Push upstream server list to aggregator via setOpcUaClients method.
  Future<void> _saveUpstreamServers() async {
    final stateMan = await ref.read(stateManProvider.future);
    if (!stateMan.aggregationMode || stateMan.clients.isEmpty) return;

    final payload = _remoteServers!.map((s) {
      final map = <String, dynamic>{
        'endpoint': s.config.endpoint,
        'server_alias': s.config.serverAlias,
      };
      // Credential handling: if not edited, send flag to preserve existing
      if (!s.credentialsEdited && s.hasCredentials) {
        map['has_credentials'] = true;
      } else if (s.config.username != null && s.config.username!.isNotEmpty) {
        map['username'] = s.config.username;
        map['password'] = s.config.password;
      }
      // TLS handling: if not edited, send flag to preserve existing
      if (!s.tlsEdited && s.hasTls) {
        map['has_tls'] = true;
      } else if (s.config.sslCert != null) {
        map['ssl_cert'] = base64Encode(s.config.sslCert!);
        map['ssl_key'] = s.config.sslKey != null
            ? base64Encode(s.config.sslKey!)
            : null;
      }
      return map;
    }).toList();

    final client = stateMan.clients.first.client;
    final result = await client.call(
      NodeId.objectsFolder,
      NodeId.fromString(1, 'setOpcUaClients'),
      [
        DynamicValue(
          value: jsonEncode(payload),
          typeId: NodeId.uastring,
        ),
      ],
    );

    final status = result.first.value as String;
    if (!status.startsWith('ok')) {
      throw Exception('setOpcUaClients failed: $status');
    }

    // Re-fetch to update flags (has_credentials/has_tls reflect new state)
    await _fetchUpstreamServers();
  }

  Future<void> _addServer() async {
    if (_isAggregationMode) {
      setState(() {
        _remoteServers ??= [];
        _remoteServers!.add(RemoteServerInfo(config: OpcUAConfig()));
      });
      return;
    }
    setState(() => _config?.opcua.add(OpcUAConfig()));
  }

  Future<void> _updateServer(int index, OpcUAConfig server) async {
    if (_isAggregationMode && _remoteServers != null) {
      setState(() => _remoteServers![index].config = server);
      return;
    }
    setState(() => _config!.opcua[index] = server);
  }

  void _updateRemoteEditState(int index, {required bool credentialsEdited, required bool tlsEdited}) {
    if (_remoteServers == null || index >= _remoteServers!.length) return;
    _remoteServers![index].credentialsEdited = credentialsEdited;
    _remoteServers![index].tlsEdited = tlsEdited;
  }

  Future<void> _removeServer(int index) async {
    if (_isAggregationMode && _remoteServers != null) {
      setState(() => _remoteServers!.removeAt(index));
      return;
    }
    setState(() => _config!.opcua.removeAt(index));
  }

  /// Helper to update the aggregator config preserving all existing fields.
  void _updateAggregator(AggregatorConfig current, {
    bool? enabled,
    OpcUAConfig? clientConfig,
  }) {
    final wasEnabled = current.enabled;
    setState(() {
      _config?.aggregator = AggregatorConfig(
        enabled: enabled ?? current.enabled,
        port: current.port,
        discoveryTtl: current.discoveryTtl,
        certificate: current.certificate,
        privateKey: current.privateKey,
        users: current.users,
        allowAnonymous: current.allowAnonymous,
        clientConfig: clientConfig ?? current.clientConfig,
      );
    });
    // When toggling aggregation ON, fetch upstream servers
    if (enabled == true && !wasEnabled) {
      _fetchUpstreamServers();
    }
    // When toggling OFF, clear remote state
    if (enabled == false && wasEnabled) {
      _remoteServers = null;
      _savedRemoteServers = null;
      _remoteError = null;
    }
  }

  /// Build the aggregator endpoint card using the standard _ServerConfigCard.
  Widget _buildAggregatorEndpointCard(AggregatorConfig aggregator) {
    final stateManAsync = ref.watch(stateManProvider);
    final stateMan = stateManAsync.valueOrNull;

    // In aggregation mode, there's a single client for the aggregator
    ClientWrapper? wrapper;
    if (stateMan != null && stateMan.aggregationMode && stateMan.clients.isNotEmpty) {
      wrapper = stateMan.clients.first;
    }

    return _ServerConfigCard(
      server: aggregator.clientConfig ?? OpcUAConfig(),
      onUpdate: (updated) => _updateAggregator(aggregator, clientConfig: updated),
      onRemove: () {}, // Cannot remove the aggregator endpoint
      showAlias: false,
      connectionStatus: wrapper?.connectionStatus,
      connectionStream: wrapper?.connectionStream,
      lastError: wrapper?.lastError,
      stateManLoading: stateManAsync.isLoading,
    );
  }

  Widget _buildServerList(StateManConfig config) {
    final stateManAsync = ref.watch(stateManProvider);
    final StateMan? stateMan = stateManAsync.valueOrNull;
    final isAggregationMode = stateMan?.aggregationMode ?? false;

    // In aggregation mode, use remote servers fetched via getOpcUaClients
    if (isAggregationMode && _remoteServers != null) {
      if (_remoteLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_remoteError != null) {
        return Center(
          child: Column(
            children: [
              Text('Error fetching upstream servers: $_remoteError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _fetchUpstreamServers,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _remoteServers!.length,
        itemBuilder: (context, index) {
          final remote = _remoteServers![index];
          ConnectionStatus? connStatus;
          Stream<(ConnectionStatus, String?)>? connStream;
          String? lastError;

          if (stateMan != null) {
            final alias = remote.config.serverAlias ?? AggregatorNodeId.defaultAlias;
            final upstreamEntry = stateMan.upstreamConnectionStatus[alias];
            connStatus = upstreamEntry?.$1;
            lastError = upstreamEntry?.$2;
            connStream = stateMan.upstreamConnectionStream.map(
              (map) {
                final entry = map[alias];
                return (
                  entry?.$1 ?? ConnectionStatus.disconnected,
                  entry?.$2,
                );
              },
            );
          }

          return _ServerConfigCard(
            server: remote.config,
            onUpdate: (server) => _updateServer(index, server),
            onRemove: () => _removeServer(index),
            connectionStatus: connStatus,
            connectionStream: connStream,
            lastError: lastError,
            stateManLoading: stateManAsync.isLoading,
            hasExistingCredentials: remote.hasCredentials,
            hasExistingTls: remote.hasTls,
            onEditState: ({credentialsEdited = false, tlsEdited = false}) =>
                _updateRemoteEditState(index, credentialsEdited: credentialsEdited, tlsEdited: tlsEdited),
          );
        },
      );
    }

    // Direct mode: use config.opcua from local prefs
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: config.opcua.length,
      itemBuilder: (context, index) {
        final server = config.opcua[index];
        ConnectionStatus? connStatus;
        Stream<(ConnectionStatus, String?)>? connStream;
        String? lastError;

        if (stateMan != null) {
          final wrapper =
              stateMan.clients.cast<ClientWrapper?>().firstWhere(
                    (w) =>
                        (server.serverAlias != null &&
                            server.serverAlias!.isNotEmpty &&
                            w!.config.serverAlias == server.serverAlias) ||
                        w!.config.endpoint == server.endpoint,
                    orElse: () => null,
                  );
          connStatus = wrapper?.connectionStatus;
          connStream = wrapper?.connectionStream;
          lastError = wrapper?.lastError;
        }

        return _ServerConfigCard(
          server: server,
          onUpdate: (server) => _updateServer(index, server),
          onRemove: () => _removeServer(index),
          connectionStatus: connStatus,
          connectionStream: connStream,
          lastError: lastError,
          stateManLoading: stateManAsync.isLoading,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(FontAwesomeIcons.triangleExclamation,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading configuration: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _loadConfig, child: const Text('Retry')),
              ElevatedButton(
                  onPressed: () => ref
                      .read(preferencesProvider.future)
                      .then((value) =>
                          value.remove(StateManConfig.configKey, secret: true))
                      .then((value) => _loadConfig()),
                  child: const Text('Delete saved configuration')),
            ],
          ),
        ),
      );
    }

    final config = _config ?? StateManConfig(opcua: []);
    final aggregator = config.aggregator ?? AggregatorConfig();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Aggregation mode toggle (top-level) ---
            SwitchListTile(
              title: const Text('Aggregation Mode'),
              subtitle: const Text(
                  'Connect to an aggregator server instead of directly to PLCs'),
              value: aggregator.enabled,
              onChanged: (value) => _updateAggregator(aggregator, enabled: value),
              dense: true,
            ),

            // --- When aggregation is ON: show aggregator endpoint card ---
            if (aggregator.enabled) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.networkWired, size: 16),
                    const SizedBox(width: 8),
                    Text('Aggregator Server',
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
              _buildAggregatorEndpointCard(aggregator),
              const SizedBox(height: 16),
            ],

            // --- Server list header + Add Server button ---
            const Divider(),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 500;
                final title = aggregator.enabled
                    ? 'Upstream Servers'
                    : 'OPC-UA Servers';
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const FaIcon(FontAwesomeIcons.server, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(title,
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          if (_hasUnsavedChanges) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Text('Unsaved',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _addServer,
                        icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                        label: const Text('Add Server'),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.server, size: 20),
                    const SizedBox(width: 8),
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_hasUnsavedChanges) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text('Unsaved Changes',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addServer,
                      icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                      label: const Text('Add Server'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Server list
            _serverListIsEmpty
                ? const SizedBox(
                    height: 200,
                    child: _EmptyServersWidget(),
                  )
                : _buildServerList(config),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!_serverListIsEmpty || _hasUnsavedChanges)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _hasUnsavedChanges ? _saveConfig : null,
                      icon: FaIcon(FontAwesomeIcons.floppyDisk,
                          size: 16,
                          color: _hasUnsavedChanges ? null : Colors.grey),
                      label: Text(_hasUnsavedChanges
                          ? 'Save Configuration'
                          : 'All Changes Saved'),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor:
                              _hasUnsavedChanges ? null : Colors.grey),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyServersWidget extends StatelessWidget {
  const _EmptyServersWidget();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FaIcon(FontAwesomeIcons.server, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No servers configured',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('Add your first OPC-UA server to get started',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ServerConfigCard extends StatefulWidget {
  final OpcUAConfig server;
  final Function(OpcUAConfig) onUpdate;
  final VoidCallback onRemove;
  final ConnectionStatus? connectionStatus;
  final Stream<(ConnectionStatus, String?)>? connectionStream;
  final String? lastError;
  final bool stateManLoading;
  final bool showAlias;

  /// When true, existing credentials are configured on the remote server.
  /// Shows a "Credentials configured" indicator; user can type new values to replace.
  final bool hasExistingCredentials;

  /// When true, existing TLS certs are configured on the remote server.
  /// Shows a "TLS configured" indicator; user can pick new files to replace.
  final bool hasExistingTls;

  /// Called when the user edits credentials or TLS, reporting edit state.
  final void Function({bool credentialsEdited, bool tlsEdited})? onEditState;

  const _ServerConfigCard({
    required this.server,
    required this.onUpdate,
    required this.onRemove,
    this.connectionStatus,
    this.connectionStream,
    this.lastError,
    this.stateManLoading = false,
    this.showAlias = true,
    this.hasExistingCredentials = false,
    this.hasExistingTls = false,
    this.onEditState,
  });

  @override
  State<_ServerConfigCard> createState() => _ServerConfigCardState();
}

class _ServerConfigCardState extends State<_ServerConfigCard> {
  late TextEditingController _endpointController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _serverAliasController;
  ConnectionStatus? _connectionStatus;
  String? _lastError;
  StreamSubscription<(ConnectionStatus, String?)>? _stateSubscription;
  bool _credentialsEdited = false;
  bool _tlsEdited = false;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: widget.server.endpoint);
    _usernameController =
        TextEditingController(text: widget.server.username ?? '');
    _passwordController =
        TextEditingController(text: widget.server.password ?? '');
    _serverAliasController =
        TextEditingController(text: widget.server.serverAlias ?? '');
    _connectionStatus = widget.connectionStatus;
    _lastError = widget.lastError;
    _listenToState();
  }

  @override
  void didUpdateWidget(covariant _ServerConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionStream != widget.connectionStream) {
      _stateSubscription?.cancel();
      _connectionStatus = widget.connectionStatus;
      _lastError = widget.lastError;
      _listenToState();
    }
  }

  void _listenToState() {
    _stateSubscription = widget.connectionStream?.listen((event) {
      final (status, error) = event;
      if (mounted) {
        setState(() {
          _connectionStatus = status;
          _lastError = error;
        });
      }
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _serverAliasController.dispose();
    super.dispose();
  }

  void _updateServer() {
    final updatedServer = OpcUAConfig()
      ..endpoint = _endpointController.text
      ..username =
          _usernameController.text.isEmpty ? null : _usernameController.text
      ..password =
          _passwordController.text.isEmpty ? null : _passwordController.text
      ..serverAlias = _serverAliasController.text.isEmpty
          ? null
          : _serverAliasController.text
      ..sslCert = widget.server.sslCert
      ..sslKey = widget.server.sslKey;

    widget.onUpdate(updatedServer);
  }

  void _onCredentialChanged() {
    if (!_credentialsEdited) {
      _credentialsEdited = true;
      widget.onEditState?.call(credentialsEdited: true, tlsEdited: _tlsEdited);
    }
    _updateServer();
  }

  void _onTlsChanged() {
    if (!_tlsEdited) {
      _tlsEdited = true;
      widget.onEditState?.call(credentialsEdited: _credentialsEdited, tlsEdited: true);
    }
    _updateServer();
  }

  Future<void> _selectCertificate() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'crt', 'cer'],
        dialogTitle: 'Select Certificate File',
        initialDirectory: (await getApplicationSupportDirectory()).path,
      );

      if (result != null && result.files.single.path != null) {
        setState(() async {
          widget.server.sslCert =
              await (File(result.files.single.path!).readAsBytes());
        });
        _updateServer();
      }
    } catch (e) {
      if (!context.mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error selecting certificate: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _selectPrivateKey() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'key'],
        dialogTitle: 'Select Private Key File',
        initialDirectory: (await getApplicationSupportDirectory()).path,
      );

      if (result != null && result.files.single.path != null) {
        setState(() async {
          widget.server.sslKey =
              await (File(result.files.single.path!).readAsBytes());
        });
        _updateServer();
      }
    } catch (e) {
      if (!context.mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error selecting private key: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  void _showCertificateGenerator() {
    showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final isSmallScreen = size.width < 600;
        return AlertDialog(
          title: const Text('Generate SSL Certificates'),
          content: SizedBox(
            width: isSmallScreen ? size.width * 0.85 : 600,
            height: isSmallScreen ? size.height * 0.6 : 600,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: CertificateGenerator(
                  onCertificatesGenerated: (cert, key) {
                    setState(() {
                      widget.server.sslCert = cert;
                      widget.server.sslKey = key;
                    });
                    _updateServer();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close')),
          ],
        );
      },
    );
  }

  String? uint8ListToString(Uint8List? ls) {
    return ls != null ? String.fromCharCodes(ls) : null;
  }

  Color _connectionStatusColor() {
    if (_connectionStatus == null) {
      return widget.stateManLoading ? Colors.orange : Colors.grey;
    }
    return switch (_connectionStatus!) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting => Colors.orange,
      ConnectionStatus.disconnected => Colors.red,
    };
  }

  String _connectionStatusLabel() {
    if (_connectionStatus == null) {
      return widget.stateManLoading ? 'Loading...' : 'Not active';
    }
    return switch (_connectionStatus!) {
      ConnectionStatus.connected => 'Connected',
      ConnectionStatus.connecting => 'Connecting...',
      ConnectionStatus.disconnected =>
        _lastError != null ? 'Disconnected: $_lastError' : 'Disconnected',
    };
  }

  Widget _buildStatusChip() {
    final color = _connectionStatusColor();
    final label = _connectionStatusLabel();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sslCertString = uint8ListToString(widget.server.sslCert);
    final sslKeyString = uint8ListToString(widget.server.sslKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: FaIcon(
          FontAwesomeIcons.server,
          size: 20,
          color: sslCertString == _certPlaceholder ||
                  sslKeyString == _certPlaceholder
              ? Theme.of(context).colorScheme.error
              : null,
        ),
        title: Text(
          widget.server.serverAlias ?? widget.server.endpoint,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Text(widget.server.endpoint,
            style: TextStyle(color: Colors.grey[600]),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusChip(),
            const SizedBox(width: 8),
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.trash, size: 16),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Remove Server'),
                    content: const Text(
                        'Are you sure you want to remove this server?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onRemove();
                          },
                          child: const Text('Remove')),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            const FaIcon(FontAwesomeIcons.chevronDown, size: 16),
          ],
        ),
        onExpansionChanged: (expanded) => setState(() {}),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint URL',
                    hintText: 'opc.tcp://localhost:4840',
                    prefixIcon: FaIcon(FontAwesomeIcons.link, size: 16),
                  ),
                  onChanged: (_) => _updateServer(),
                ),
                if (widget.showAlias) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverAliasController,
                    decoration: const InputDecoration(
                      labelText: 'Server Alias (optional)',
                      hintText: 'My OPC-UA Server',
                      prefixIcon: FaIcon(FontAwesomeIcons.tag, size: 16),
                    ),
                    onChanged: (_) => _updateServer(),
                  ),
                ],
                const SizedBox(height: 12),
                if (widget.hasExistingCredentials && !_credentialsEdited)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.circleCheck, size: 14, color: Colors.green),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Credentials configured on server')),
                        TextButton(
                          onPressed: () => setState(() => _credentialsEdited = true),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ),
                if (!widget.hasExistingCredentials || _credentialsEdited)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    if (isNarrow) {
                      return Column(
                        children: [
                          TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username (optional)',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.user, size: 16),
                            ),
                            onChanged: (_) => _onCredentialChanged(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password (optional)',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.lock, size: 16),
                            ),
                            obscureText: true,
                            onChanged: (_) => _onCredentialChanged(),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username (optional)',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.user, size: 16),
                            ),
                            onChanged: (_) => _onCredentialChanged(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password (optional)',
                              prefixIcon:
                                  FaIcon(FontAwesomeIcons.lock, size: 16),
                            ),
                            obscureText: true,
                            onChanged: (_) => _onCredentialChanged(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (widget.hasExistingTls && !_tlsEdited)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.circleCheck, size: 14, color: Colors.green),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('TLS certificates configured on server')),
                        TextButton(
                          onPressed: () => setState(() => _tlsEdited = true),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ),
                if (!widget.hasExistingTls || _tlsEdited)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    return Card(
                      child: Padding(
                        padding: EdgeInsets.all(isNarrow ? 12.0 : 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const FaIcon(FontAwesomeIcons.certificate,
                                    size: 16),
                                const SizedBox(width: 8),
                                Text('SSL Certificates',
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                widget.server.sslCert == null
                                    ? Text(
                                        'Please import or generate a certificate if needed')
                                    : sslCertString == _certPlaceholder
                                        ? Text(
                                            'Please import or generate a certificate',
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error),
                                          )
                                        : Text('Certificate in place'),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () { _selectCertificate(); _onTlsChanged(); },
                                  icon: const FaIcon(
                                      FontAwesomeIcons.folderOpen,
                                      size: 14),
                                  label: const Text('Browse Certificate'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                widget.server.sslKey == null
                                    ? Text(
                                        'Please import or generate a private key if needed')
                                    : sslKeyString == _certPlaceholder
                                        ? Text(
                                            'Please import or generate a private key',
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error),
                                          )
                                        : Text('Private key in place'),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () { _selectPrivateKey(); _onTlsChanged(); },
                                  icon: const FaIcon(
                                      FontAwesomeIcons.folderOpen,
                                      size: 14),
                                  label: const Text('Browse Private Key'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () { _showCertificateGenerator(); _onTlsChanged(); },
                                icon: const FaIcon(FontAwesomeIcons.plus,
                                    size: 14),
                                label: const Text('Generate New Certificates'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImportExportCard extends ConsumerStatefulWidget {
  const ImportExportCard({super.key});

  static const String _compiledPrefix = 'Flottur köttur:'; // same secret prefix

  @override
  ConsumerState<ImportExportCard> createState() => _ImportExportCardState();
}

class _ImportExportCardState extends ConsumerState<ImportExportCard> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;
            final versionText = _packageInfo != null
                ? Text(
                    'v${_packageInfo!.version}+${_packageInfo!.buildNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(100),
                        ),
                  )
                : null;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync_alt, size: 20),
                      const SizedBox(width: 8),
                      Text('Import / Export',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _onImport(context, ref),
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Import'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _onExport(context, ref),
                    icon: const Icon(Icons.file_download),
                    label: const Text('Export'),
                  ),
                  if (versionText != null) ...[
                    const SizedBox(height: 12),
                    Center(child: versionText),
                  ],
                ],
              );
            }
            return Row(
              children: [
                const Icon(Icons.sync_alt, size: 20),
                const SizedBox(width: 8),
                Text('Import / Export',
                    style: Theme.of(context).textTheme.titleMedium),
                if (versionText != null)
                  Expanded(child: Center(child: versionText)),
                if (versionText == null) const Spacer(),
                FilledButton.icon(
                  onPressed: () => _onImport(context, ref),
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _onExport(context, ref),
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // -------------------- EXPORT --------------------
  Future<void> _onExport(BuildContext context, WidgetRef ref) async {
    try {
      // Load current/saved config from prefs
      final prefs = await ref.read(preferencesProvider.future);
      final stateMan = await StateManConfig.fromPrefs(prefs);
      final db = await DatabaseConfig.fromPrefs();

      final rawJsonMap = stateMan.toJson();
      final jsonMap = _scrubCertPaths(rawJsonMap);
      jsonMap['database'] = db.toJson();

      final postfix = _generatePostfix(12);
      final envelope = await SecureEnvelope.encrypt(
        jsonConfig: jsonMap,
        compiledPrefix: ImportExportCard._compiledPrefix,
        exportPostfix: postfix,
      );

      String? savePath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Encrypted Config',
          fileName: 'server_config.enc',
          type: FileType.custom,
          allowedExtensions: ['enc'],
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
        savePath = path.join(dir.path, 'server_config_$ts.enc');
      }
      if (savePath == null) return;

      final file = File(savePath);
      await file
          .writeAsString(const JsonEncoder.withIndent('  ').convert(envelope));

      if (!context.mounted) return;

      // Show postfix/code
      // ignore: use_build_context_synchronously
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export Complete'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Encrypted file saved.'),
                const SizedBox(height: 12),
                const Text('Use this code to decrypt:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: SelectableText(
                    postfix,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Location:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(file.path,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: postfix));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied to clipboard')),
                );
              },
              child: const Text('Copy Code'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  // -------------------- IMPORT --------------------
  Future<void> _onImport(BuildContext context, WidgetRef ref) async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['enc'],
        dialogTitle: 'Select Encrypted Config',
      );
      if (pick == null || pick.files.single.path == null) return;

      final file = File(pick.files.single.path!);
      final envelope =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      if (!context.mounted) return;

      // Ask for code
      final ctrl = TextEditingController();
      final postfix = await showDialog<String?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter Code to Decrypt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current server config will be overwritten!',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.orange),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    hintText: 'Enter the code shared with you',
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Decrypt')),
          ],
        ),
      );
      if (postfix == null || postfix.isEmpty) return;

      // Decrypt & scrub
      final decrypted = await SecureEnvelope.decrypt(
        envelope: envelope,
        compiledPrefix: ImportExportCard._compiledPrefix,
        postfix: postfix,
      );

      // Persist Database first (so DB widget re-reads correct values)
      if (decrypted['database'] != null) {
        final db = DatabaseConfig.fromJson(decrypted['database']);
        await db.toPrefs();
        decrypted.remove('database');
      }

      // Persist StateManConfig to prefs as current config
      final stateMan = StateManConfig.fromJson(decrypted);
      final prefs = await ref.read(preferencesProvider.future);
      await stateMan.toPrefs(prefs);

      // Trigger rebuilds:
      ref.invalidate(databaseProvider);
      ref.invalidate(stateManProvider);
      ref.read(refreshKeyProvider.notifier).increment();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Config imported. Please generate new certificates for the servers that need them.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  String _generatePostfix(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // Remove sslCert/sslKey file paths from incoming JSON and count affected servers
  Map<String, dynamic> _scrubCertPaths(Map<String, dynamic> jsonMap) {
    final copy =
        jsonDecode(jsonEncode(jsonMap)) as Map<String, dynamic>; // deep copy
    if (copy['opcua'] is List) {
      for (final s in (copy['opcua'] as List)) {
        if (s is Map<String, dynamic>) {
          if ((s['ssl_cert'] != null) && (s['ssl_key'] != null)) {
            s['ssl_cert'] =
                Base64Converter().toJson(utf8.encode(_certPlaceholder));
            s['ssl_key'] =
                Base64Converter().toJson(utf8.encode(_certPlaceholder));
          }
        }
      }
    }
    return copy;
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
        text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
