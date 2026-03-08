import 'package:flutter/material.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/modbus_device_client.dart';

import 'browse_panel.dart';

/// Adapts a [UmasClient] to the protocol-agnostic [BrowseDataSource].
///
/// Fetches the complete variable tree on first [fetchRoots] call, caches it,
/// and serves subsequent [fetchChildren]/[fetchDetail] calls from the cache.
class UmasBrowseDataSource implements BrowseDataSource {
  final UmasClient _client;
  List<UmasVariableTreeNode>? _tree; // Cached after initial browse
  Map<String, UmasVariableTreeNode>? _pathIndex; // O(1) lookup by path

  UmasBrowseDataSource(this._client);

  @override
  Future<List<BrowseNode>> fetchRoots() async {
    _tree ??= await _client.browse();
    _buildPathIndex(_tree!);
    return _tree!.map(_toBrowseNode).toList();
  }

  void _buildPathIndex(List<UmasVariableTreeNode> roots) {
    _pathIndex = {};
    void index(List<UmasVariableTreeNode> nodes) {
      for (final node in nodes) {
        _pathIndex![node.path] = node;
        index(node.children);
      }
    }
    index(roots);
  }

  @override
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent) async {
    final node = _findTreeNode(parent.id);
    if (node == null) return [];
    return node.children.map(_toBrowseNode).toList();
  }

  @override
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node) async {
    return BrowseNodeDetail(
      dataType: node.dataType,
      description: node.metadata['path'],
    );
  }

  BrowseNode _toBrowseNode(UmasVariableTreeNode treeNode) {
    return BrowseNode(
      id: treeNode.path,
      displayName: treeNode.name,
      type: treeNode.isFolder
          ? BrowseNodeType.folder
          : BrowseNodeType.variable,
      dataType: treeNode.dataType?.name,
      metadata: {
        'path': treeNode.path,
        if (treeNode.variable != null) ...{
          'blockNo': treeNode.variable!.blockNo.toString(),
          'offset': treeNode.variable!.offset.toString(),
          'dataTypeId': treeNode.variable!.dataTypeId.toString(),
        },
        if (treeNode.dataType != null) ...{
          'dataTypeName': treeNode.dataType!.name,
          'byteSize': treeNode.dataType!.byteSize.toString(),
        },
      },
    );
  }

  UmasVariableTreeNode? _findTreeNode(String path) {
    return _pathIndex?[path];
  }
}

/// Convenience function to open UMAS browse dialog for a Modbus server.
///
/// Finds the [ModbusDeviceClientAdapter] matching [serverAlias], creates a
/// [UmasClient] from its TCP transport, and opens [showBrowseDialog] with a
/// [UmasBrowseDataSource].
Future<BrowseNode?> browseUmasNode({
  required BuildContext context,
  required StateMan stateMan,
  required String? serverAlias,
}) async {
  // Find the ModbusDeviceClientAdapter for this server alias.
  // StateMan exposes `deviceClients: List<DeviceClient>`.
  // There is NO `modbusDeviceClients` field. Filter with whereType.
  ModbusDeviceClientAdapter? adapter;
  for (final dc
      in stateMan.deviceClients.whereType<ModbusDeviceClientAdapter>()) {
    if (dc.serverAlias == serverAlias) {
      adapter = dc;
      break;
    }
  }
  if (adapter == null) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No Modbus client found for "$serverAlias"')),
    );
    return null;
  }

  // wrapper.client is nullable (ModbusClientTcp?).
  // It is null when the Modbus connection is not established.
  final tcpClient = adapter.wrapper.client;
  if (tcpClient == null) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Modbus not connected. Connect first, then browse.')),
    );
    return null;
  }

  final umasClient = UmasClient(sendFn: tcpClient.send);
  final dataSource = UmasBrowseDataSource(umasClient);

  return showBrowseDialog(
    context: context,
    dataSource: dataSource,
    serverAlias: serverAlias ?? '',
  );
}
