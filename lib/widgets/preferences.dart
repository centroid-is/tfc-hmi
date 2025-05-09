import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgres/postgres.dart';
import '../providers/preferences.dart';
import '../core/preferences.dart';
import 'dart:convert';

class PreferencesWidget extends ConsumerWidget {
  const PreferencesWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Preferences>(
      future: ref.read(preferencesProvider.future),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final preferences = snapshot.data!;
        final config = preferences.config;

        return ListView(
          children: [
            ExpansionTile(
              title: const Text('Preferences Config'),
              children: [
                _ConfigEditor(
                  config: config,
                  onSave: (newConfig) async {
                    final prefs = preferences.sharedPreferences;
                    await prefs.setString(
                        'preferences_config', jsonEncode(newConfig.toJson()));
                  },
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Preferences Keys'),
              children: [
                FutureBuilder<Map<String, Object?>>(
                  future: preferences.getAll(),
                  builder: (context, keysSnap) {
                    if (!keysSnap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final allPrefs = keysSnap.data!;
                    if (allPrefs.isEmpty) {
                      return const ListTile(
                        title: Text('No preferences found.'),
                      );
                    }
                    return Column(
                      children: allPrefs.entries
                          .where((e) => e.key != 'preferences_config')
                          .map((e) => ExpansionTile(
                                title: Text(e.key),
                                children: [
                                  _ValueEditor(
                                    keyName: e.key,
                                    value: e.value,
                                    onChanged: (newValue) async {
                                      // Save the new value
                                      if (newValue is bool) {
                                        await preferences.setBool(
                                            e.key, newValue);
                                      } else if (newValue is int) {
                                        await preferences.setInt(
                                            e.key, newValue);
                                      } else if (newValue is double) {
                                        await preferences.setDouble(
                                            e.key, newValue);
                                      } else if (newValue is List<String>) {
                                        await preferences.setStringList(
                                            e.key, newValue);
                                      } else if (newValue is String) {
                                        await preferences.setString(
                                            e.key, newValue);
                                      }
                                      // Force refresh
                                      (context as Element).markNeedsBuild();
                                    },
                                  ),
                                ],
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ConfigEditor extends ConsumerStatefulWidget {
  final PreferencesConfig config;
  final ValueChanged<PreferencesConfig> onSave;

  const _ConfigEditor({required this.config, required this.onSave});

  @override
  ConsumerState<_ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends ConsumerState<_ConfigEditor> {
  late TextEditingController hostController;
  late TextEditingController portController;
  late TextEditingController dbController;
  late TextEditingController userController;
  late TextEditingController passController;
  late bool isUnixSocket;
  late SslMode? sslMode;

  @override
  void initState() {
    super.initState();
    final endpoint = widget.config.postgres;
    hostController = TextEditingController(text: endpoint?.host ?? '');
    portController =
        TextEditingController(text: endpoint?.port?.toString() ?? '');
    dbController = TextEditingController(text: endpoint?.database ?? '');
    userController = TextEditingController(text: endpoint?.username ?? '');
    passController = TextEditingController(text: endpoint?.password ?? '');
    isUnixSocket = endpoint?.isUnixSocket ?? false;
    sslMode = widget.config.sslMode;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Preferences>(
        future: ref.watch(preferencesProvider.future),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(child: Text('Error: ${snapshot.error}')),
            );
          }
          final prefs = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text(
                  'Connection Status: ${prefs.dbConnected}',
                  style: const TextStyle(fontSize: 12),
                ),
                TextField(
                    controller: hostController,
                    decoration: const InputDecoration(labelText: 'Host')),
                TextField(
                    controller: portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number),
                TextField(
                    controller: dbController,
                    decoration: const InputDecoration(labelText: 'Database')),
                TextField(
                    controller: userController,
                    decoration: const InputDecoration(labelText: 'Username')),
                TextField(
                    controller: passController,
                    decoration: const InputDecoration(labelText: 'Password')),
                CheckboxListTile(
                  title: const Text('Is Unix Socket'),
                  value: isUnixSocket,
                  onChanged: (v) => setState(() => isUnixSocket = v ?? false),
                ),
                Row(
                  children: [
                    const Text('SSL Mode: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: sslMode == null ? Colors.red : Colors.grey,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          color: sslMode == null
                              ? Colors.red.withAlpha((0.05 * 255).toInt())
                              : null,
                        ),
                        child: DropdownButton<SslMode>(
                          value: sslMode,
                          isExpanded: true,
                          hint: const Text("Select SSL Mode"),
                          icon: const Icon(Icons.arrow_drop_down),
                          onChanged: (v) => setState(() => sslMode = v),
                          items: SslMode.values
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e.name),
                                  ))
                              .toList(),
                          underline: SizedBox(),
                        ),
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () {
                    final newConfig = PreferencesConfig(
                      postgres: Endpoint(
                        host: hostController.text,
                        port: int.tryParse(portController.text) ?? 5432,
                        database: dbController.text,
                        username: userController.text,
                        password: passController.text,
                        isUnixSocket: isUnixSocket,
                      ),
                      sslMode: sslMode,
                    );
                    widget.onSave(newConfig);
                    ref.invalidate(preferencesProvider);
                  },
                  child: const Text('Save Config'),
                ),
              ],
            ),
          );
        });
  }
}

class _ValueEditor extends StatefulWidget {
  final String keyName;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  const _ValueEditor({
    required this.keyName,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value is String
          ? widget.value as String
          : widget.value?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _ValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value is String
          ? widget.value as String
          : widget.value?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    if (value is bool) {
      return SwitchListTile(
        title: Text(widget.keyName),
        value: value,
        onChanged: (v) => widget.onChanged(v),
      );
    } else if (value is int) {
      return ListTile(
        title: Text(widget.keyName),
        subtitle: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          onSubmitted: (v) {
            final intVal = int.tryParse(v) ?? value;
            widget.onChanged(intVal);
          },
        ),
      );
    } else if (value is double) {
      return ListTile(
        title: Text(widget.keyName),
        subtitle: TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (v) {
            final doubleVal = double.tryParse(v) ?? value;
            widget.onChanged(doubleVal);
          },
        ),
      );
    } else if (value is List<String>) {
      return ListTile(
        title: Text(widget.keyName),
        subtitle: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: 'Comma separated'),
          onSubmitted: (v) {
            final listVal = v.split(',').map((e) => e.trim()).toList();
            widget.onChanged(listVal);
          },
        ),
      );
    } else if (value is String) {
      // Try to decode as JSON
      dynamic decoded;
      bool isJson = false;
      try {
        decoded = jsonDecode(value);
        isJson = true;
      } catch (_) {}

      if (isJson) {
        return _JsonEditor(
          keyName: widget.keyName,
          initialText: const JsonEncoder.withIndent('  ').convert(decoded),
          onSave: (formatted) => widget.onChanged(formatted),
        );
      } else {
        return ListTile(
          title: Text(widget.keyName),
          subtitle: TextField(
            controller: _controller,
            onSubmitted: (v) => widget.onChanged(v),
          ),
        );
      }
    } else {
      return ListTile(
        title: Text(widget.keyName),
        subtitle: Text('Unsupported type: ${value.runtimeType}'),
      );
    }
  }
}

/// IDE-like JSON editor with line numbers and format button
class _JsonEditor extends StatefulWidget {
  final String keyName;
  final String initialText;
  final ValueChanged<String> onSave;

  const _JsonEditor({
    required this.keyName,
    required this.initialText,
    required this.onSave,
  });

  @override
  State<_JsonEditor> createState() => _JsonEditorState();
}

class _JsonEditorState extends State<_JsonEditor> {
  late TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  void _formatJson() {
    try {
      final decoded = jsonDecode(_controller.text);
      final formatted = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() {
        _controller.text = formatted;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Invalid JSON: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(_controller.text).length + 1;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.keyName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton(
                onPressed: _formatJson,
                child: const Text('Format JSON'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  try {
                    jsonDecode(_controller.text);
                    widget.onSave(_controller.text);
                    setState(() => _error = null);
                  } catch (e) {
                    setState(() => _error = 'Invalid JSON: $e');
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Line numbers
                Container(
                  color: Colors.grey[200],
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      lines,
                      (i) => Text('${i + 1}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                    ),
                  ),
                ),
                // JSON editor
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
