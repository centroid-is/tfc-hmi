// implement
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../widgets/base_scaffold.dart';
import '../widgets/preferences.dart';
import '../core/state_man.dart';
import '../providers/state_man.dart';
import '../providers/preferences.dart';

class CertificateGenerator extends StatefulWidget {
  final Function(File?, File?) onCertificatesGenerated;

  const CertificateGenerator({
    Key? key,
    required this.onCertificatesGenerated,
  }) : super(key: key);

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
    return BaseScaffold(
      title: 'Server Configuration',
      body: Column(
        children: [
          // Database Configuration Section
          const DatabaseConfigWidget(),
          const SizedBox(height: 16),

          // OPC-UA Servers Section - Now expands to fill remaining space
          Expanded(
            child: _OpcUAServersSection(),
          ),
        ],
      ),
    );
  }
}

class _OpcUAServersSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_OpcUAServersSection> createState() =>
      _OpcUAServersSectionState();
}

class _OpcUAServersSectionState extends ConsumerState<_OpcUAServersSection> {
  StateManConfig? _config;
  StateManConfig? _savedConfig;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  Future<bool> _loadConfig() async {
    _error = null;
    try {
      if (_config != null && _savedConfig != null) return true;
      final prefs = await ref.read(preferencesProvider.future);
      final stateManConfig = await StateManConfig.fromPrefs(prefs);
      _config = stateManConfig;
      _savedConfig = stateManConfig.copy();
    } catch (e) {
      _error = e.toString();
    }
    return _config != null;
  }

  bool get _hasUnsavedChanges {
    if (_config == null || _savedConfig == null) return false;

    // Compare the JSON representations for deep equality
    final currentJson = jsonEncode(_config!.toJson());
    final savedJson = jsonEncode(_savedConfig!.toJson());

    return currentJson != savedJson;
  }

  Future<void> _saveConfig() async {
    if (_config == null) return;

    try {
      final prefs = await ref.read(preferencesProvider.future);
      await _config!.toPrefs(prefs);
      // Update the saved config to match current config
      setState(() {
        _savedConfig = _config!.copy();
      });

      // Invalidate the state man provider to reload with new config
      ref.invalidate(stateManProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save configuration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addServer() async {
    if (_config == null) return;

    setState(() {
      _config!.opcua.add(OpcUAConfig());
    });
  }

  Future<void> _updateServer(int index, OpcUAConfig server) async {
    if (_config == null) return;

    setState(() {
      _config!.opcua[index] = server;
    });
  }

  Future<void> _removeServer(int index) async {
    if (_config == null) return;

    setState(() {
      _config!.opcua.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loadConfig(),
      builder: (context, snapshot) {
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
                    onPressed: _loadConfig,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data == false) {
          return const Center(child: CircularProgressIndicator());
        }
        return _build(context);
      },
    );
  }

  Widget _build(BuildContext context) {
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
                Text(
                  'OPC-UA Servers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_hasUnsavedChanges) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Unsaved Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _addServer,
                  icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                  label: const Text('Add Server'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Server list - Now expands to fill available space
            Expanded(
              child: config.opcua.isEmpty
                  ? _EmptyServersWidget()
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

            // Save button - Always visible when there are servers or unsaved changes
            if (config.opcua.isNotEmpty || _hasUnsavedChanges) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _hasUnsavedChanges ? _saveConfig : null,
                  icon: FaIcon(
                    FontAwesomeIcons.floppyDisk,
                    size: 16,
                    color: _hasUnsavedChanges ? null : Colors.grey,
                  ),
                  label: Text(
                    _hasUnsavedChanges
                        ? 'Save Configuration'
                        : 'All Changes Saved',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _hasUnsavedChanges ? null : Colors.grey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyServersWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FaIcon(FontAwesomeIcons.server, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No servers configured',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first OPC-UA server to get started',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ServerConfigCard extends StatefulWidget {
  final OpcUAConfig server;
  final Function(OpcUAConfig) onUpdate;
  final VoidCallback onRemove;

  const _ServerConfigCard({
    required this.server,
    required this.onUpdate,
    required this.onRemove,
  });

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
            backgroundColor: Colors.red,
          ),
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: const FaIcon(FontAwesomeIcons.server, size: 20),
        title: Text(
          widget.server.serverAlias ?? widget.server.endpoint,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          widget.server.endpoint,
          style: TextStyle(color: Colors.grey[600]),
        ),
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
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onRemove();
                        },
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const FaIcon(FontAwesomeIcons.chevronDown, size: 16),
          ],
        ),
        onExpansionChanged: (expanded) {
          setState(() {});
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Basic connection settings
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

                // Authentication
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

                // SSL Certificate configuration - Simplified with file picker
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
                            Text(
                              'SSL Certificates',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Certificate file selection
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                readOnly: true,
                                controller: TextEditingController(
                                  text: widget.server.sslCert?.path ??
                                      'No certificate selected',
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Certificate File',
                                  prefixIcon: FaIcon(
                                      FontAwesomeIcons.certificate,
                                      size: 16),
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

                        // Private key file selection
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                readOnly: true,
                                controller: TextEditingController(
                                  text: widget.server.sslKey?.path ??
                                      'No private key selected',
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Private Key File',
                                  prefixIcon:
                                      FaIcon(FontAwesomeIcons.key, size: 16),
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

                        // Generate new certificates button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showCertificateGenerator(),
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
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
