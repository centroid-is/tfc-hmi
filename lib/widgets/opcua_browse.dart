import 'package:flutter/material.dart';
import 'package:open62541/open62541.dart'
    if (dart.library.js_interop) 'package:tfc_dart/core/web_stubs/open62541_stub.dart'
    show BrowseResultItem, NodeClass, NodeId, ClientApi, DynamicValue;
import 'package:tfc_dart/core/state_man.dart' show StateMan;

import 'browse_panel.dart';

// Re-export generic types so existing importers can still reach them.
export 'browse_panel.dart'
    show BrowseNode, BrowseNodeType, BrowseDataSource, BrowsePanel,
         BrowseNodeTile, VariableDetailStrip, showBrowseDialog;

/// Finds the [ClientApi] for [serverAlias] in [stateMan], opens the OPC UA
/// browse dialog, and returns the selected [BrowseResultItem] (or null).
///
/// Shows a [SnackBar] when no matching client is found.
Future<BrowseResultItem?> browseOpcUaNode({
  required BuildContext context,
  required StateMan stateMan,
  required String? serverAlias,
}) async {
  ClientApi? client;
  for (final wrapper in stateMan.clients) {
    if (wrapper.config.serverAlias == serverAlias) {
      client = wrapper.client;
      break;
    }
  }
  if (client == null) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'No client found for alias "${serverAlias ?? "(none)"}"')),
    );
    return null;
  }

  final alias = serverAlias ?? stateMan.clients.first.config.endpoint;
  final dataSource = OpcUaBrowseDataSource(client);

  final result = await showBrowseDialog(
    context: context,
    dataSource: dataSource,
    serverAlias: alias,
  );

  if (result == null) return null;
  return _toBrowseResultItem(result);
}

/// Adapts an OPC UA [ClientApi] to the protocol-agnostic [BrowseDataSource].
class OpcUaBrowseDataSource implements BrowseDataSource {
  final ClientApi client;

  OpcUaBrowseDataSource(this.client);

  @override
  Future<List<BrowseNode>> fetchRoots() async {
    final results = await client.browse(NodeId.objectsFolder);
    return results.map(_toBrowseNode).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent) async {
    final nodeId = parseNodeId(parent.id);
    final results = await client.browse(nodeId);
    return results.map(_toBrowseNode).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node) async {
    final nodeId = parseNodeId(node.id);
    final val = await client.read(nodeId);
    return BrowseNodeDetail(
      value: formatDynamicValue(val),
      description: val.description != null && val.description!.value.isNotEmpty
          ? val.description!.value
          : null,
      dataType: val.typeId?.toString(),
      structChildren: _extractStructChildren(val, node, nodeId),
    );
  }

  BrowseNode _toBrowseNode(BrowseResultItem item) {
    return BrowseNode(
      id: item.nodeId.toString(),
      displayName: item.displayName,
      type: _mapNodeClass(item.nodeClass),
      metadata: {
        'nodeId': item.nodeId.toString(),
        'browseName': item.browseName,
        'nodeClass': item.nodeClass.toString(),
      },
    );
  }

  static BrowseNodeType _mapNodeClass(NodeClass nc) {
    switch (nc) {
      case NodeClass.UA_NODECLASS_OBJECT:
      case NodeClass.UA_NODECLASS_VIEW:
        return BrowseNodeType.folder;
      case NodeClass.UA_NODECLASS_VARIABLE:
        return BrowseNodeType.variable;
      case NodeClass.UA_NODECLASS_METHOD:
        return BrowseNodeType.method;
      default:
        return BrowseNodeType.other;
    }
  }

  List<BrowseNode>? _extractStructChildren(
      DynamicValue val, BrowseNode parent, NodeId nodeId) {
    if (val.isObject && nodeId.isString()) {
      final fields = val.asObject;
      return fields.keys.map((fieldName) {
        return BrowseNode(
          id: 'ns=${nodeId.namespace};s=${nodeId.string}.$fieldName',
          displayName: fieldName,
          type: BrowseNodeType.variable,
        );
      }).toList();
    }
    return null;
  }

  /// Parses a NodeId string back to a [NodeId] object.
  ///
  /// Handles formats: `ns=X;i=Y` (numeric) and `ns=X;s=Y` (string).
  @visibleForTesting
  static NodeId parseNodeId(String idStr) {
    final nsMatch = RegExp(r'^ns=(\d+);([si])=(.+)$').firstMatch(idStr);
    if (nsMatch == null) {
      throw ArgumentError('Cannot parse NodeId: "$idStr"');
    }
    final ns = int.parse(nsMatch.group(1)!);
    final type = nsMatch.group(2)!;
    final value = nsMatch.group(3)!;
    if (type == 'i') {
      return NodeId.fromNumeric(ns, int.parse(value));
    } else {
      return NodeId.fromString(ns, value);
    }
  }

  /// Formats a [DynamicValue] for display in the detail strip.
  @visibleForTesting
  static String formatDynamicValue(DynamicValue dv) {
    if (dv.isNull) return 'null';
    if (dv.isArray) {
      final list = dv.asArray;
      if (list.length <= 8) {
        return '[${list.map((e) => formatDynamicValue(e)).join(', ')}]';
      }
      return '[${list.take(6).map((e) => formatDynamicValue(e)).join(', ')}, ... (${list.length})]';
    }
    if (dv.isObject) {
      final map = dv.asObject;
      final keys = map.keys.toList();
      if (keys.length <= 4) {
        return '{${keys.map((k) => '$k: ${formatDynamicValue(map[k]!)}').join(', ')}}';
      }
      return '{${keys.take(3).map((k) => '$k: ${formatDynamicValue(map[k]!)}').join(', ')}, ... (${keys.length} fields)}';
    }
    final s = dv.value?.toString() ?? 'null';
    return s.length > 120 ? '${s.substring(0, 117)}...' : s;
  }
}

/// Converts a protocol-agnostic [BrowseNode] back to a [BrowseResultItem]
/// for backward compatibility with callers expecting OPC UA types.
BrowseResultItem _toBrowseResultItem(BrowseNode node) {
  final nodeId = OpcUaBrowseDataSource.parseNodeId(node.id);
  return BrowseResultItem(
    referenceTypeId: NodeId.fromNumeric(0, 0),
    isForward: true,
    nodeId: nodeId,
    browseName: node.metadata['browseName'] ?? node.displayName,
    displayName: node.displayName,
    nodeClass: _reverseMapNodeClass(node.type),
  );
}

NodeClass _reverseMapNodeClass(BrowseNodeType type) {
  switch (type) {
    case BrowseNodeType.folder:
      return NodeClass.UA_NODECLASS_OBJECT;
    case BrowseNodeType.variable:
      return NodeClass.UA_NODECLASS_VARIABLE;
    case BrowseNodeType.method:
      return NodeClass.UA_NODECLASS_METHOD;
    case BrowseNodeType.other:
      return NodeClass.UA_NODECLASS_UNSPECIFIED;
  }
}
