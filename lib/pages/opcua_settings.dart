import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/base_scaffold.dart';
import '../page_creator/client.dart';

/// A page to view and edit StateManConfig and KeyMappings stored in SharedPreferences.
class OpcuaSettingsPage extends StatefulWidget {
  const OpcuaSettingsPage({Key? key}) : super(key: key);

  @override
  _OpcuaSettingsPageState createState() => _OpcuaSettingsPageState();
}

class _OpcuaSettingsPageState extends State<OpcuaSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late SharedPreferencesAsync prefs;

  // Controllers for OPC UA settings
  final _endpointController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // Dynamic list of key-mapping entries
  List<KeyMappingEntry> _entries = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    prefs = SharedPreferencesAsync();

    // Load or initialize StateManConfig
    var stateManJson = await prefs.getString('state_man_config');
    StateManConfig stateManConfig;
    if (stateManJson == null) {
      stateManConfig = StateManConfig(opcua: OpcUAConfig());
      await prefs.setString('state_man_config', jsonEncode(stateManConfig.toJson()));
    } else {
      stateManConfig = StateManConfig.fromJson(jsonDecode(stateManJson));
    }

    // Load or initialize KeyMappings
    var keyMappingsJson = await prefs.getString('key_mappings');
    KeyMappings keyMappings;
    if (keyMappingsJson == null) {
      keyMappings = KeyMappings(nodes: {});
      await prefs.setString('key_mappings', jsonEncode(keyMappings.toJson()));
    } else {
      keyMappings = KeyMappings.fromJson(jsonDecode(keyMappingsJson));
    }

    // Populate controllers
    _endpointController.text = stateManConfig.opcua.endpoint;
    _usernameController.text = stateManConfig.opcua.username ?? '';
    _passwordController.text = stateManConfig.opcua.password ?? '';

    _entries = keyMappings.nodes.entries.map((e) {
      return KeyMappingEntry(
        keyController: TextEditingController(text: e.key),
        namespaceController: TextEditingController(text: e.value.namespace.toString()),
        identifierController: TextEditingController(text: e.value.identifier),
      );
    }).toList();

    setState(() {
      _loading = false;
    });
  }

  void _addEntry() {
    setState(() {
      _entries.add(
        KeyMappingEntry(
          keyController: TextEditingController(),
          namespaceController: TextEditingController(),
          identifierController: TextEditingController(),
        ),
      );
    });
  }

  void _removeEntry(int index) {
    setState(() {
      _entries.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Save OPC UA config
    final stateManConfig = StateManConfig(
      opcua: OpcUAConfig()
        ..endpoint = _endpointController.text
        ..username = _usernameController.text.isNotEmpty ? _usernameController.text : null
        ..password = _passwordController.text.isNotEmpty ? _passwordController.text : null,
    );
    await prefs.setString('state_man_config', jsonEncode(stateManConfig.toJson()));

    // Save key mappings
    final nodes = <String, NodeIdConfig>{};
    for (var entry in _entries) {
      final key = entry.keyController.text;
      final ns = int.tryParse(entry.namespaceController.text) ?? 0;
      final id = entry.identifierController.text;
      if (key.isNotEmpty) {
        nodes[key] = NodeIdConfig(namespace: ns, identifier: id);
      }
    }
    final keyMappings = KeyMappings(nodes: nodes);
    await prefs.setString('key_mappings', jsonEncode(keyMappings.toJson()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuration saved')),
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    for (var entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return BaseScaffold(
      title: 'StateMan Config',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OPC UA Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextFormField(
                  controller: _endpointController,
                  decoration: const InputDecoration(labelText: 'Endpoint'),
                  validator: (v) => v == null || v.isEmpty ? 'Endpoint required' : null,
                ),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Key Mappings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton(onPressed: _addEntry, child: const Text('Add')),
                  ],
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: entry.keyController,
                                    decoration: const InputDecoration(labelText: 'Key'),
                                    validator: (v) => v == null || v.isEmpty ? 'Key required' : null,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _removeEntry(index),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: entry.namespaceController,
                                    decoration: const InputDecoration(labelText: 'Namespace'),
                                    keyboardType: TextInputType.number,
                                    validator: (v) => v == null || v.isEmpty ? 'Namespace required' : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: entry.identifierController,
                                    decoration: const InputDecoration(labelText: 'Identifier'),
                                    validator: (v) => v == null || v.isEmpty ? 'Identifier required' : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save Config'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A helper class holding controllers for a single mapping entry.
class KeyMappingEntry {
  final TextEditingController keyController;
  final TextEditingController namespaceController;
  final TextEditingController identifierController;

  KeyMappingEntry({
    required this.keyController,
    required this.namespaceController,
    required this.identifierController,
  });

  void dispose() {
    keyController.dispose();
    namespaceController.dispose();
    identifierController.dispose();
  }
}
