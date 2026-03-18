import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart'
    show McpConfig, McpToolToggles, readMcpConfigFromPreferences, writeMcpConfigToPreferences;

import '../providers/mcp_bridge.dart';
import '../providers/preferences.dart';
import 'package:tfc_dart/core/preferences.dart'
    if (dart.library.js_interop) 'package:tfc_dart/core/web_stubs/preferences_stub.dart';
import 'package:tfc/core/preferences.dart';
import 'package:tfc_dart/core/database.dart'
    if (dart.library.js_interop) 'package:tfc_dart/core/web_stubs/database_stub.dart';

/// MCP Server settings section for the preferences page.
///
/// Contains the server enable toggle, port configuration, connection status,
/// Claude Desktop config snippet, and tool group toggles.
///
/// All settings are stored as a single JSON blob under [McpConfig.kPrefKey].
class McpServerSection extends ConsumerStatefulWidget {
  const McpServerSection({super.key});

  @override
  ConsumerState<McpServerSection> createState() => _McpServerSectionState();
}

class _McpServerSectionState extends ConsumerState<McpServerSection> {
  late TextEditingController _portController;
  bool _loaded = false;
  McpConfig _config = McpConfig.defaults;

  @override
  void initState() {
    super.initState();
    _portController =
        TextEditingController(text: McpConfig.defaultPort.toString());
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadState(Preferences prefs) async {
    if (_loaded) return;
    _config = await readMcpConfigFromPreferences(prefs);
    _portController.text = _config.port.toString();
    _loaded = true;
  }

  /// Saves the current [_config] to preferences and invalidates providers.
  Future<void> _saveConfig(Preferences prefs) async {
    await writeMcpConfigToPreferences(prefs, _config);
    ref.invalidate(mcpConfigProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Use AsyncValue directly instead of FutureBuilder to avoid
    // Future identity changes that destroy ExpansionTile state on rebuild.
    final prefsAsync = ref.watch(preferencesProvider);

    return prefsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (prefs) => _buildContent(context, prefs),
    );
  }

  Widget _buildContent(BuildContext context, Preferences prefs) {
    if (!_loaded) {
      // Schedule initial load; will call setState when done.
      _loadState(prefs).then((_) {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }

    final bridge = ref.watch(mcpBridgeProvider);
    final bridgeState = bridge.currentState;
    final isRunning =
        bridgeState.connectionState == McpConnectionState.connected;

    return Card(
      child: ExpansionTile(
        leading: const FaIcon(FontAwesomeIcons.robot, size: 20),
        title: const Text('MCP Server'),
        subtitle: Text(
          isRunning
              ? (bridgeState.port != null
                  ? 'Running on port ${bridgeState.port}'
                  : 'Running (in-process)')
              : 'Stopped',
          style: TextStyle(
            color: isRunning ? Colors.green : Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        initiallyExpanded: false,
        children: [
          // Enable/Disable toggle
          SwitchListTile(
            title: const Text('Enable MCP Server'),
            subtitle: const Text(
                'Allow Claude Desktop to connect via Streamable HTTP'),
            value: _config.serverEnabled,
            onChanged: (value) async {
              setState(() => _config = _config.copyWith(serverEnabled: value));
              await _saveConfig(prefs);
            },
          ),

          // Chat bubble toggle (only when server enabled)
          if (_config.serverEnabled)
            SwitchListTile(
              title: const Text('Show Chat Bubble'),
              subtitle: const Text(
                  'Display AI copilot chat button on the main screen'),
              value: _config.chatEnabled,
              onChanged: (value) async {
                setState(() => _config = _config.copyWith(chatEnabled: value));
                await _saveConfig(prefs);
              },
            ),

          // Port field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Server Port',
                prefixIcon: FaIcon(FontAwesomeIcons.hashtag, size: 16),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (v) async {
                final port = int.tryParse(v) ?? McpConfig.defaultPort;
                setState(() => _config = _config.copyWith(port: port));
                await _saveConfig(prefs);
              },
            ),
          ),

          // Status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isRunning
                    ? Colors.green.withValues(alpha: 0.1)
                    : bridgeState.connectionState == McpConnectionState.error
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isRunning
                      ? Colors.green
                      : bridgeState.connectionState == McpConnectionState.error
                          ? Colors.red
                          : Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  FaIcon(
                    isRunning
                        ? FontAwesomeIcons.circleCheck
                        : bridgeState.connectionState ==
                                McpConnectionState.error
                            ? FontAwesomeIcons.circleExclamation
                            : FontAwesomeIcons.circle,
                    color: isRunning
                        ? Colors.green
                        : bridgeState.connectionState ==
                                McpConnectionState.error
                            ? Colors.red
                            : Colors.grey,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isRunning
                          ? (bridgeState.port != null
                              ? 'Server running on port ${bridgeState.port}'
                              : 'Server running (in-process)')
                          : bridgeState.connectionState ==
                                  McpConnectionState.error
                              ? 'Error: ${bridgeState.error}'
                              : 'Server stopped',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Claude Desktop config snippet (only when running with SSE port)
          if (isRunning && bridgeState.port != null)
            _ClaudeDesktopConfigSnippet(port: bridgeState.port!),

          // Divider before tool toggles
          if (_config.serverEnabled) const Divider(),

          // Tool toggles (only visible when MCP enabled)
          if (_config.serverEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tool Groups',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          if (_config.serverEnabled)
            for (final meta in McpToolToggles.toolGroupMeta)
              SwitchListTile(
                title: Text(meta.title),
                subtitle: Text(meta.description),
                value: _config.toggles.getByKey(meta.key),
                onChanged: (value) async {
                  final newToggles =
                      _config.toggles.copyWithToggle(meta.key, value);
                  setState(
                      () => _config = _config.copyWith(toggles: newToggles));
                  await _saveConfig(prefs);
                  debugPrint(
                    'AUDIT: toggle_change key=${meta.key} '
                    'value=$value '
                    'timestamp=${DateTime.now().toIso8601String()}',
                  );
                },
              ),
        ],
      ),
    );
  }
}

/// Shows a copyable Claude Desktop config snippet.
class _ClaudeDesktopConfigSnippet extends StatelessWidget {
  final int port;
  const _ClaudeDesktopConfigSnippet({required this.port});

  @override
  Widget build(BuildContext context) {
    final config = '''{
  "mcpServers": {
    "centroid-hmi": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:$port/mcp"]
    }
  }
}''';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Claude Desktop Config',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.copy, size: 14),
                tooltip: 'Copy to clipboard',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: config));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Config copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SelectableText(
              config,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DatabaseConfigWidget extends ConsumerStatefulWidget {
  const DatabaseConfigWidget({super.key});

  @override
  ConsumerState<DatabaseConfigWidget> createState() =>
      _DatabaseConfigWidgetState();
}

class _DatabaseConfigWidgetState extends ConsumerState<DatabaseConfigWidget> {
  DatabaseConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await DatabaseConfig.fromPrefs();
    if (mounted) {
      setState(() {
        _config = config;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _DatabaseConfigEditor(
      config: _config!,
      onSave: (newConfig) async {
        await newConfig.toPrefs();
        ref.invalidate(databaseProvider);
        // Reload config after save so the editor reflects new values
        _loadConfig();
      },
    );
  }
}

class _DatabaseConfigEditor extends ConsumerStatefulWidget {
  final DatabaseConfig config;
  final ValueChanged<DatabaseConfig> onSave;

  const _DatabaseConfigEditor({required this.config, required this.onSave});

  @override
  ConsumerState<_DatabaseConfigEditor> createState() =>
      _DatabaseConfigEditorState();
}

class _DatabaseConfigEditorState extends ConsumerState<_DatabaseConfigEditor> {
  late TextEditingController hostController;
  late TextEditingController portController;
  late TextEditingController dbController;
  late TextEditingController userController;
  late TextEditingController passController;
  late bool isUnixSocket;
  late SslMode? sslMode;
  final SharedPreferencesAsync sharedPreferences = SharedPreferencesAsync();

  @override
  void initState() {
    super.initState();
    final endpoint = widget.config.postgres;
    hostController = TextEditingController(text: endpoint?.host ?? '');
    portController = TextEditingController(
      text: endpoint?.port.toString() ?? '5432',
    );
    dbController = TextEditingController(text: endpoint?.database ?? '');
    userController = TextEditingController(text: endpoint?.username ?? '');
    passController = TextEditingController(text: endpoint?.password ?? '');
    isUnixSocket = endpoint?.isUnixSocket ?? false;
    sslMode = widget.config.sslMode;
  }

  @override
  Widget build(BuildContext context) {
    // Use AsyncValue directly instead of FutureBuilder to avoid
    // Future identity changes that destroy ExpansionTile state on rebuild.
    final prefsAsync = ref.watch(preferencesProvider);

    return prefsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(child: Text('Error: $error')),
      ),
      data: (prefs) => Card(
        child: ExpansionTile(
          leading: const FaIcon(FontAwesomeIcons.database, size: 20),
          title: const Text('Database Configuration'),
          subtitle: StreamBuilder<bool>(
            stream: prefs.database?.connectionState,
            initialData: false,
            builder: (context, connectionSnapshot) {
              final isConnected = connectionSnapshot.data ?? false;
              return Text(
                'Status: ${isConnected ? "Connected" : "Disconnected"}',
                style: TextStyle(
                  color: isConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
          initiallyExpanded: false, // Default to folded
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<bool>(
                    stream: prefs.database?.connectionState,
                    initialData: false,
                    builder: (context, snapshot) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (snapshot.data ?? false)
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (snapshot.data ?? false)
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        child: Row(
                          children: [
                            FaIcon(
                              (snapshot.data ?? false)
                                  ? FontAwesomeIcons.checkCircle
                                  : FontAwesomeIcons.exclamationCircle,
                              color: (snapshot.data ?? false)
                                  ? Colors.green
                                  : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Connection Status: ${snapshot.data ?? false ? "Connected" : "Disconnected"}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      prefixIcon: FaIcon(FontAwesomeIcons.server, size: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      prefixIcon: FaIcon(FontAwesomeIcons.hashtag, size: 16),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dbController,
                    decoration: const InputDecoration(
                      labelText: 'Database',
                      prefixIcon: FaIcon(FontAwesomeIcons.database, size: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: userController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: FaIcon(FontAwesomeIcons.user, size: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: FaIcon(FontAwesomeIcons.lock, size: 16),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Is Unix Socket'),
                    value: isUnixSocket,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => isUnixSocket = v ?? false),
                  ),
                  const SizedBox(height: 8),
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
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e.name),
                                  ),
                                )
                                .toList(),
                            underline: const SizedBox(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final newConfig = DatabaseConfig(
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
                      },
                      icon: const FaIcon(FontAwesomeIcons.save, size: 16),
                      label: const Text('Save Database Config'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PreferencesKeysWidget extends ConsumerStatefulWidget {
  const PreferencesKeysWidget({super.key});

  @override
  ConsumerState<PreferencesKeysWidget> createState() =>
      _PreferencesKeysWidgetState();
}

class _PreferencesKeysWidgetState extends ConsumerState<PreferencesKeysWidget> {
  Map<String, Object?>? _allPrefs;
  Map<String, bool>? _dbKeyFlags;
  Preferences? _preferences;
  SharedPreferencesWrapper? _localPrefs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Defer loading until the first build, when the provider is available.
  }

  Future<void> _loadData(Preferences preferences) async {
    final localPrefs = SharedPreferencesWrapper(SharedPreferencesAsync());
    final results = await Future.wait([
      preferences.getAll(),
      localPrefs.getAll(),
    ]);
    final merged = <String, Object?>{};
    merged.addAll(results[1]); // local prefs first
    merged.addAll(results[0]); // db prefs override

    // Pre-fetch all isKeyInDatabase flags in parallel
    final dbFlags = <String, bool>{};
    await Future.wait(
      merged.keys.map((key) async {
        try {
          dbFlags[key] = await preferences
              .isKeyInDatabase(key)
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          dbFlags[key] = false;
        }
      }),
    );

    if (mounted) {
      setState(() {
        _preferences = preferences;
        _localPrefs = localPrefs;
        _allPrefs = merged;
        _dbKeyFlags = dbFlags;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(preferencesProvider);

    return prefsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (preferences) {
        // Trigger load once when preferences become available
        if (_loading && _preferences == null) {
          _loadData(preferences);
          return const Center(child: CircularProgressIndicator());
        }
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final allPrefs = _allPrefs!;
        final dbFlags = _dbKeyFlags!;
        final prefs = _preferences!;
        final localPrefs = _localPrefs!;

        if (allPrefs.isEmpty) {
          return const ListTile(title: Text('No preferences found.'));
        }

        final sortedEntries = allPrefs.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.key, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Preferences Keys',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: sortedEntries
                        .map(
                          (e) => _PreferenceKeyTile(
                            keyName: e.key,
                            value: e.value,
                            isInDatabase: dbFlags[e.key] ?? false,
                            onChanged: (newValue) async {
                              final isInDb = dbFlags[e.key] ?? false;
                              final target = isInDb ? prefs : localPrefs;

                              if (newValue is bool) {
                                await target.setBool(e.key, newValue);
                              } else if (newValue is int) {
                                await target.setInt(e.key, newValue);
                              } else if (newValue is double) {
                                await target.setDouble(e.key, newValue);
                              } else if (newValue is List<String>) {
                                await target.setStringList(e.key, newValue);
                              } else if (newValue is String) {
                                await target.setString(e.key, newValue);
                              }
                              // Reload data to reflect changes
                              _loading = true;
                              _loadData(prefs);
                            },
                            onDelete: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Preference'),
                                  content: Text('Delete "${e.key}"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                final isInDb = dbFlags[e.key] ?? false;
                                if (isInDb) {
                                  await prefs.remove(e.key);
                                } else {
                                  await localPrefs.remove(e.key);
                                }
                                // Reload data and invalidate provider
                                _loading = true;
                                _loadData(prefs);
                                ref.invalidate(preferencesProvider);
                              }
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreferenceKeyTile extends StatefulWidget {
  final String keyName;
  final Object? value;
  final bool isInDatabase;
  final ValueChanged<Object?> onChanged;
  final VoidCallback onDelete;

  const _PreferenceKeyTile({
    required this.keyName,
    required this.value,
    required this.isInDatabase,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_PreferenceKeyTile> createState() => _PreferenceKeyTileState();
}

class _PreferenceKeyTileState extends State<_PreferenceKeyTile> {
  late TextEditingController _controller;
  final _expansionController =
      ExpansibleController(); // todo deprecated since 3.31
  bool _isExpanded = false;

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
  void didUpdateWidget(covariant _PreferenceKeyTile oldWidget) {
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
    return ExpansionTile(
      controller: _expansionController,
      leading: FaIcon(
        widget.isInDatabase
            ? FontAwesomeIcons.database
            : FontAwesomeIcons.hardDrive,
        size: 16,
        color: widget.isInDatabase ? Colors.blue : Colors.grey,
      ),
      title: Text(
        '(${widget.isInDatabase ? 'DB' : 'Local'}) ${widget.keyName}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.trash, size: 16),
            onPressed: widget.onDelete,
          ),
          IconButton(
            icon: FaIcon(
              _isExpanded
                  ? FontAwesomeIcons.chevronUp
                  : FontAwesomeIcons.chevronDown,
              size: 16,
            ),
            onPressed: () {
              if (_isExpanded) {
                _expansionController.collapse();
              } else {
                _expansionController.expand();
              }
            },
          ),
        ],
      ),
      onExpansionChanged: (expanded) {
        setState(() {
          _isExpanded = expanded;
        });
      },
      children: [
        if (value is bool)
          SwitchListTile(
            title: Text(widget.keyName),
            value: value,
            onChanged: (v) => widget.onChanged(v),
          )
        else if (value is int)
          ListTile(
            title: Text(widget.keyName),
            subtitle: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              onSubmitted: (v) {
                final intVal = int.tryParse(v) ?? value;
                widget.onChanged(intVal);
              },
            ),
          )
        else if (value is double)
          ListTile(
            title: Text(widget.keyName),
            subtitle: TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (v) {
                final doubleVal = double.tryParse(v) ?? value;
                widget.onChanged(doubleVal);
              },
            ),
          )
        else if (value is List<String>)
          ListTile(
            title: Text(widget.keyName),
            subtitle: TextField(
              controller: _controller,
              decoration: const InputDecoration(hintText: 'Comma separated'),
              onSubmitted: (v) {
                final listVal = v.split(',').map((e) => e.trim()).toList();
                widget.onChanged(listVal);
              },
            ),
          )
        else if (value is String)
          _buildStringEditor()
        else
          ListTile(
            title: Text(widget.keyName),
            subtitle: Text('Unsupported type: ${value.runtimeType}'),
          ),
      ],
    );
  }

  Widget _buildStringEditor() {
    // Try to decode as JSON
    dynamic decoded;
    bool isJson = false;
    try {
      decoded = jsonDecode(widget.value as String);
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
  static const double _lineHeight = 24.0;

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
              Text(
                widget.keyName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      lines,
                      (i) => SizedBox(
                        height: _lineHeight,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // JSON editor
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: _lineHeight / 14,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
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
