import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import '../widgets/base_scaffold.dart';
import 'config_edit.dart';

class ConfigListPage extends StatefulWidget {
  final DBusClient dbusClient;

  const ConfigListPage({
    Key? key,
    required this.dbusClient,
  }) : super(key: key);

  @override
  State<ConfigListPage> createState() => _ConfigListPageState();
}

class _ConfigListPageState extends State<ConfigListPage> {
  bool _isLoading = false;
  String _error = '';
  List<_ConfigInterfaceInfo> _foundConfigs = [];

  @override
  void initState() {
    super.initState();
    _scanConfigs();
  }

  Future<void> _scanConfigs() async {
    setState(() {
      _isLoading = true;
      _error = '';
      _foundConfigs.clear();
    });

    try {
      // 1) Get all bus names
      final reply = await widget.dbusClient.callMethod(
        destination: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus',
        name: 'ListNames',
        values: <DBusValue>[],
      );
      if (reply.returnValues.isEmpty) {
        throw Exception('No bus names returned!');
      }
      final allNames = (reply.returnValues.first as DBusArray)
          .children
          .map((e) => (e as DBusString).value)
          .toList();

      // 2) Create a map of unique names to their aliases
      final nameOwners = <String, String>{};
      for (final name in allNames) {
        if (!name.startsWith(':')) continue; // Skip non-unique names
        try {
          final ownerReply = await widget.dbusClient.callMethod(
            destination: 'org.freedesktop.DBus',
            path: DBusObjectPath('/org/freedesktop/DBus'),
            interface: 'org.freedesktop.DBus',
            name: 'GetNameOwner',
            values: [DBusString(name)],
          );
          final owner = (ownerReply.returnValues.first as DBusString).value;
          nameOwners[name] = owner;
        } catch (_) {
          // Skip if we can't get the owner
        }
      }

      // 3) For each bus name, introspect and look for object paths
      final List<_ConfigInterfaceInfo> found = [];
      final seenPaths = <String>{}; // To track unique paths

      for (final serviceName in allNames) {
        if (serviceName.startsWith('org.freedesktop.')) {
          continue;
        }

        // Skip if this is an alias of a service we've already processed
        if (nameOwners.containsValue(serviceName)) {
          continue;
        }

        try {
          final result = await widget.dbusClient.callMethod(
            destination: serviceName,
            path: DBusObjectPath('/'),
            interface: 'org.freedesktop.DBus.Introspectable',
            name: 'Introspect',
            replySignature: DBusSignature('s'),
          );
          final node =
              parseDBusIntrospectXml(result.returnValues.first.asString());

          // Create a unique key for this service+path combination
          for (final config in await _scanNodeForConfigInterfaces(
            serviceName,
            DBusObjectPath('/'),
            node,
          )) {
            final pathKey = '${config.serviceName}:${config.objectPath}';
            if (!seenPaths.contains(pathKey)) {
              seenPaths.add(pathKey);
              found.add(config);
            }
          }
        } catch (_) {
          // Not all services can be introspected at "/"; skip or handle
        }
      }

      setState(() {
        _foundConfigs = found;
        _isLoading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _isLoading = false;
      });
    }
  }

  Future<List<_ConfigInterfaceInfo>> _scanNodeForConfigInterfaces(
    String serviceName,
    DBusObjectPath path,
    DBusIntrospectNode node,
  ) async {
    final List<_ConfigInterfaceInfo> matches = [];

    // Skip paths containing "/Config/filters/"
    if (path.value.contains('/Config/filters/')) {
      return matches; // Return empty list for filtered paths
    }

    // If any interface matches "is.centroid.Config", add
    for (final iface in node.interfaces) {
      if (iface.name == 'is.centroid.Config') {
        matches.add(_ConfigInterfaceInfo(serviceName, path.value));
        break;
      }
    }

    // Recurse into child nodes
    for (final subnode in node.children) {
      final childPath = path.value.endsWith('/')
          ? '${path.value}${subnode.name}'
          : '${path.value}/${subnode.name}';
      try {
        final result = await widget.dbusClient.callMethod(
          destination: serviceName,
          path: DBusObjectPath(childPath),
          interface: 'org.freedesktop.DBus.Introspectable',
          name: 'Introspect',
          replySignature: DBusSignature('s'),
        );
        final childNode =
            parseDBusIntrospectXml(result.returnValues.first.asString());
        matches.addAll(await _scanNodeForConfigInterfaces(
          serviceName,
          DBusObjectPath(childPath),
          childNode,
        ));
      } catch (_) {
        // Could fail on some child path; skip
      }
    }

    return matches;
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Available Configs',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : _foundConfigs.isEmpty
                  ? const Center(child: Text('No configs found.'))
                  : ListView.builder(
                      itemCount: _foundConfigs.length,
                      itemBuilder: (context, index) {
                        final info = _foundConfigs[index];
                        return ListTile(
                          title:
                              Text('${info.serviceName} - ${info.objectPath}'),
                          onTap: () {
                            // Instead of beaming, open a dialog
                            showDialog(
                              context: context,
                              barrierDismissible: false, // Force user to choose
                              builder: (_) => ConfigEditDialog(
                                dbusClient: widget.dbusClient,
                                serviceName: info.serviceName,
                                objectPath: info.objectPath,
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}

class _ConfigInterfaceInfo {
  final String serviceName;
  final String objectPath;

  _ConfigInterfaceInfo(this.serviceName, this.objectPath);
}
