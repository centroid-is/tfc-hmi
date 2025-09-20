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
import '../core/state_man.dart';
import '../core/database.dart';
import '../providers/state_man.dart';
import '../providers/preferences.dart';
import '../providers/database.dart';

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
  final Function(File?, File?) onCertificatesGenerated;

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
  File? _certFile;
  File? _keyFile;
  late TextEditingController _commonNameController;
  late TextEditingController _organizationController;
  late TextEditingController _validityDaysController;
  late TextEditingController _countryController;
  late TextEditingController _stateController;
  late TextEditingController _localityController;
  late TextEditingController _certFileNameController;
  late TextEditingController _keyFileNameController;
  late TextEditingController _saveLocationController;
  Directory? _selectedDirectory;

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

    // Initialize file naming and location controllers
    _certFileNameController = TextEditingController(text: 'opcua.crt');
    _keyFileNameController = TextEditingController(text: 'opcua.key');
    _saveLocationController = TextEditingController();

    // Set default save location
    _setDefaultSaveLocation();
  }

  Future<void> _setDefaultSaveLocation() async {
    try {
      final Directory appDir = await getApplicationSupportDirectory();
      final Directory certsDir = Directory(path.join(appDir.path, 'certs'));
      _selectedDirectory = certsDir;
      _saveLocationController.text = certsDir.path;
    } catch (e) {
      final appDir = await getApplicationDocumentsDirectory();
      final certsDir = Directory(path.join(appDir.path, 'certs'));
      _selectedDirectory = certsDir;
      _saveLocationController.text = certsDir.path;
    }
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
    _certFileNameController.dispose();
    _keyFileNameController.dispose();
    _saveLocationController.dispose();
    super.dispose();
  }

  Future<void> _selectSaveLocation() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Certificate Save Location',
      );

      if (selectedDirectory != null) {
        _selectedDirectory = Directory(selectedDirectory);
        _saveLocationController.text = selectedDirectory;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting directory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateCertificates() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      // Ensure save directory exists
      if (_selectedDirectory == null) {
        throw Exception('Please select a save location');
      }

      if (!await _selectedDirectory!.exists()) {
        await _selectedDirectory!.create(recursive: true);
      }

      final commonName = _commonNameController.text.trim();
      final organization = _organizationController.text.trim();
      final validityDays = int.tryParse(_validityDaysController.text) ?? 365;
      final country = _countryController.text.trim();
      final state = _stateController.text.trim();
      final locality = _localityController.text.trim();
      final certFileName = _certFileNameController.text.trim();
      final keyFileName = _keyFileNameController.text.trim();

      if (commonName.isEmpty) {
        throw Exception('Common Name is required');
      }
      if (certFileName.isEmpty) {
        throw Exception('Certificate filename is required');
      }
      if (keyFileName.isEmpty) {
        throw Exception('Private key filename is required');
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

      // Save certificate and key files with user-specified names
      final certFile = File(path.join(_selectedDirectory!.path, certFileName));
      final keyFile = File(path.join(_selectedDirectory!.path, keyFileName));

      await certFile.writeAsString(certPem);
      await keyFile.writeAsString(CryptoUtils.encodeRSAPrivateKeyToPem(
          keyPair.privateKey as RSAPrivateKey));

      setState(() {
        _certFile = certFile;
        _keyFile = keyFile;
      });

      widget.onCertificatesGenerated(_certFile, _keyFile);

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
          Row(
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

          // File naming and location section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.folderOpen, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'File Location & Naming',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Save location
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _saveLocationController,
                          decoration: const InputDecoration(
                            labelText: 'Save Location',
                            prefixIcon:
                                FaIcon(FontAwesomeIcons.folder, size: 16),
                          ),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _selectSaveLocation,
                        icon:
                            const FaIcon(FontAwesomeIcons.folderOpen, size: 14),
                        label: const Text('Browse'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // File names
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _certFileNameController,
                          decoration: const InputDecoration(
                            labelText: 'Certificate Filename',
                            hintText: 'opcua_cert',
                            prefixIcon:
                                FaIcon(FontAwesomeIcons.certificate, size: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _keyFileNameController,
                          decoration: const InputDecoration(
                            labelText: 'Private Key Filename',
                            hintText: 'opcua_key',
                            prefixIcon: FaIcon(FontAwesomeIcons.key, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Error display
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.triangleExclamation,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Certificate status
          if (_certFile != null && _keyFile != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.circleCheck,
                      color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Certificates generated successfully!',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Certificate: ${path.basename(_certFile!.path)}',
                            style: const TextStyle(fontSize: 12)),
                        Text('Private Key: ${path.basename(_keyFile!.path)}',
                            style: const TextStyle(fontSize: 12)),
                        Text('Location: ${_certFile!.parent.path}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
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
      body: Column(
        children: [
          // Database Configuration Section
          DatabaseConfigWidget(key: ValueKey('db_$refreshKey')),
          const SizedBox(height: 16),

          // OPC-UA Servers Section
          Expanded(
            child: _OpcUAServersSection(key: ValueKey('opcua_$refreshKey')),
          ),
          const ImportExportCard(),
        ],
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
      setState(() => _isLoading = false);
    }
  }

  bool get _hasUnsavedChanges {
    if (_config == null || _savedConfig == null) return false;
    final currentJson = jsonEncode(_config!.toJson());
    final savedJson = jsonEncode(_savedConfig!.toJson());
    return currentJson != savedJson;
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;

    try {
      _config!.toPrefs(await ref.read(preferencesProvider.future));
      _savedConfig = await StateManConfig.fromPrefs(
          await ref.read(preferencesProvider.future));
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save configuration: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addServer() async {
    setState(() => _config?.opcua.add(OpcUAConfig()));
  }

  Future<void> _updateServer(int index, OpcUAConfig server) async {
    setState(() => _config!.opcua[index] = server);
  }

  Future<void> _removeServer(int index) async {
    setState(() => _config!.opcua.removeAt(index));
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
              const FaIcon(FontAwesomeIcons.triangleExclamation,
                  size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading configuration: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _loadConfig, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final config = _config ?? StateManConfig(opcua: []);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.server, size: 20),
                const SizedBox(width: 8),
                Text('OPC-UA Servers',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_hasUnsavedChanges) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                // Import/Export Buttons
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addServer,
                  icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                  label: const Text('Add Server'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: config.opcua.isEmpty
                  ? const _EmptyServersWidget()
                  : ListView.builder(
                      itemCount: config.opcua.length,
                      itemBuilder: (context, index) {
                        return _ServerConfigCard(
                          server: config.opcua[index],
                          onUpdate: (server) => _updateServer(index, server),
                          onRemove: () => _removeServer(index),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            // place import and export button in bottom right corner
            // place save config button in bottom left corner, it should take 60% of the width
            Row(
              children: [
                if (config.opcua.isNotEmpty || _hasUnsavedChanges)
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

  const _ServerConfigCard(
      {required this.server, required this.onUpdate, required this.onRemove});

  @override
  State<_ServerConfigCard> createState() => _ServerConfigCardState();
}

class _ServerConfigCardState extends State<_ServerConfigCard> {
  late TextEditingController _endpointController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _serverAliasController;

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
  }

  @override
  void dispose() {
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

  Future<void> _selectCertificate() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'crt', 'cer'],
        dialogTitle: 'Select Certificate File',
        initialDirectory: widget.server.sslCert?.path,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          widget.server.sslCert = File(result.files.single.path!);
        });
        _updateServer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error selecting certificate: $e'),
              backgroundColor: Colors.red),
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
        initialDirectory: widget.server.sslKey?.path,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          widget.server.sslKey = File(result.files.single.path!);
        });
        _updateServer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error selecting private key: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCertificateGenerator() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate SSL Certificates'),
        content: SizedBox(
          width: 600,
          height: 600,
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
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: FaIcon(FontAwesomeIcons.server,
            size: 20,
            color: widget.server.sslCert?.path == _certPlaceholder ||
                    widget.server.sslKey?.path == _certPlaceholder
                ? Theme.of(context).colorScheme.error
                : null),
        title: Text(
          widget.server.serverAlias ?? widget.server.endpoint,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(widget.server.endpoint,
            style: TextStyle(color: Colors.grey[600])),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username (optional)',
                          prefixIcon: FaIcon(FontAwesomeIcons.user, size: 16),
                        ),
                        onChanged: (_) => _updateServer(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password (optional)',
                          prefixIcon: FaIcon(FontAwesomeIcons.lock, size: 16),
                        ),
                        obscureText: true,
                        onChanged: (_) => _updateServer(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const FaIcon(FontAwesomeIcons.certificate,
                                size: 16),
                            const SizedBox(width: 8),
                            Text('SSL Certificates',
                                style: Theme.of(context).textTheme.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                readOnly: true,
                                controller: TextEditingController(
                                  text: widget.server.sslCert?.path ??
                                      'No certificate selected',
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Certificate File',
                                  prefixIcon: const FaIcon(
                                      FontAwesomeIcons.certificate,
                                      size: 16),
                                  // Add red border if certificate path is the placeholder
                                  border: widget.server.sslCert?.path ==
                                          _certPlaceholder
                                      ? const OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.red, width: 2),
                                        )
                                      : null,
                                  enabledBorder: widget.server.sslCert?.path ==
                                          _certPlaceholder
                                      ? const OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.red, width: 2),
                                        )
                                      : null,
                                  focusedBorder: widget.server.sslCert?.path ==
                                          _certPlaceholder
                                      ? const OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.red, width: 2),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _selectCertificate,
                              icon: const FaIcon(FontAwesomeIcons.folderOpen,
                                  size: 14),
                              label: const Text('Browse'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                readOnly: true,
                                controller: TextEditingController(
                                  text: widget.server.sslKey?.path ??
                                      'No private key selected',
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Private Key File',
                                  prefixIcon: const FaIcon(FontAwesomeIcons.key,
                                      size: 16),
                                  // Add red border if key path is the placeholder
                                  border: widget.server.sslKey?.path ==
                                          _certPlaceholder
                                      ? const OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.red, width: 2),
                                        )
                                      : null,
                                  enabledBorder: widget.server.sslKey?.path ==
                                          _certPlaceholder
                                      ? const OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.red, width: 2),
                                        )
                                      : null,
                                  focusedBorder: widget.server.sslKey?.path ==
                                          _certPlaceholder
                                      ? const OutlineInputBorder(
                                          borderSide: BorderSide(
                                              color: Colors.red, width: 2),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _selectPrivateKey,
                              icon: const FaIcon(FontAwesomeIcons.folderOpen,
                                  size: 14),
                              label: const Text('Browse'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showCertificateGenerator,
                            icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                            label: const Text('Generate New Certificates'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImportExportCard extends ConsumerWidget {
  const ImportExportCard({super.key});

  static const String _compiledPrefix = 'Flottur köttur:'; // same secret prefix

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              const Icon(Icons.sync_alt, size: 20),
              const SizedBox(width: 8),
              Text('Import / Export',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
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
          ),
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
        compiledPrefix: _compiledPrefix,
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Encrypted file saved.'),
              const SizedBox(height: 12),
              const Text('Use this code to decrypt:'),
              const SizedBox(height: 8),
              SelectableText(postfix,
                  style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Text('Location:\n${file.path}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'), backgroundColor: Colors.red),
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
          title: const Text(
              'Enter Code to Decrypt. \nCurrent server config will be overwritten!'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'Enter the code shared with you',
            ),
            obscureText: true,
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
        compiledPrefix: _compiledPrefix,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Import failed: $e'), backgroundColor: Colors.red),
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
            s['ssl_cert'] = _certPlaceholder;
            s['ssl_key'] = _certPlaceholder;
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
