import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:open62541/open62541.dart'
    show BrowseResultItem, NodeClass, NodeId, ClientApi, DynamicValue;
import 'package:tfc_dart/core/state_man.dart' show StateMan;

import '../theme.dart' show SolarizedColors;

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

  return showOpcUaBrowseDialog(
    context: context,
    client: client,
    serverAlias: serverAlias ?? stateMan.clients.first.config.endpoint,
  );
}

/// A node in the OPC UA browse tree.
class BrowseTreeNode {
  final BrowseResultItem item;
  final int depth;
  final NodeId parentNodeId;

  const BrowseTreeNode({
    required this.item,
    required this.depth,
    required this.parentNodeId,
  });

  NodeId get nodeId => item.nodeId;
  String get displayName => item.displayName;
  NodeClass get nodeClass => item.nodeClass;

  bool get isExpandable =>
      item.nodeClass == NodeClass.UA_NODECLASS_OBJECT ||
      item.nodeClass == NodeClass.UA_NODECLASS_VIEW;
  bool get isVariable => item.nodeClass == NodeClass.UA_NODECLASS_VARIABLE;
}

/// Shows an [OpcUaBrowsePanel] inside a dialog sized at 80% of the screen.
/// Returns the selected [BrowseResultItem] or null if cancelled.
Future<BrowseResultItem?> showOpcUaBrowseDialog({
  required BuildContext context,
  required ClientApi client,
  required String serverAlias,
}) {
  return showDialog<BrowseResultItem>(
    context: context,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final screenSize = MediaQuery.of(context).size;
      return Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenSize.width * 0.8,
            maxHeight: screenSize.height * 0.8,
            minHeight: 300,
          ),
          child: SizedBox(
            width: screenSize.width * 0.8,
            height: screenSize.height * 0.8,
            child: OpcUaBrowsePanel(
              client: client,
              serverAlias: serverAlias,
              onSelected: (item) => Navigator.of(context).pop(item),
              onCancelled: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    },
  );
}

/// Lazily browses an OPC UA server's address space as a tree and lets the
/// user select a variable node. This widget is the panel content — it does
/// NOT include a Dialog wrapper. Use [showOpcUaBrowseDialog] for the dialog
/// version, or embed this widget directly.
class OpcUaBrowsePanel extends StatefulWidget {
  final ClientApi client;
  final String serverAlias;
  final ValueChanged<BrowseResultItem> onSelected;
  final VoidCallback onCancelled;

  const OpcUaBrowsePanel({
    super.key,
    required this.client,
    required this.serverAlias,
    required this.onSelected,
    required this.onCancelled,
  });

  @override
  State<OpcUaBrowsePanel> createState() => OpcUaBrowsePanelState();
}

@visibleForTesting
class OpcUaBrowsePanelState extends State<OpcUaBrowsePanel> {
  List<BrowseTreeNode> _roots = [];
  final Map<NodeId, List<BrowseTreeNode>> _children = {};
  final Set<NodeId> _expanded = {};
  final Set<NodeId> _loading = {};
  BrowseTreeNode? _selected;
  bool _rootLoading = true;
  String? _error;

  // Detail strip state for selected variable
  String? _detailDescription;
  String? _detailValue;
  String? _detailDataType;
  bool _detailLoading = false;
  NodeId? _detailLoadedFor;

  @visibleForTesting
  BrowseTreeNode? get selected => _selected;
  @visibleForTesting
  List<BrowseTreeNode> get roots => _roots;
  @visibleForTesting
  bool get rootLoading => _rootLoading;
  @visibleForTesting
  String? get error => _error;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    try {
      final results = await widget.client.browse(NodeId.objectsFolder);
      if (!mounted) return;
      final roots = results
          .map((item) => BrowseTreeNode(
                item: item,
                depth: 0,
                parentNodeId: NodeId.objectsFolder,
              ))
          .toList();
      setState(() {
        _roots = roots;
        _rootLoading = false;
      });
      _prefetchChildren(roots);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _rootLoading = false;
      });
    }
  }

  Future<void> _loadChildren(NodeId nodeId, int parentDepth) async {
    if (_loading.contains(nodeId)) return;
    setState(() => _loading.add(nodeId));
    try {
      final results = await widget.client.browse(nodeId);
      if (!mounted) return;
      final nodes = results
          .map((item) => BrowseTreeNode(
                item: item,
                depth: parentDepth + 1,
                parentNodeId: nodeId,
              ))
          .toList();
      setState(() {
        _children[nodeId] = nodes;
        _expanded.add(nodeId);
        _loading.remove(nodeId);
      });
      _prefetchChildren(nodes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading.remove(nodeId);
        _children[nodeId] = [];
      });
    }
  }

  void _prefetchChildren(List<BrowseTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isExpandable && !_children.containsKey(node.nodeId)) {
        _prefetchSingle(node.nodeId, node.depth);
      }
    }
  }

  Future<void> _prefetchSingle(NodeId nodeId, int parentDepth) async {
    if (_children.containsKey(nodeId)) return;
    try {
      final results = await widget.client.browse(nodeId);
      if (!mounted) return;
      if (_children.containsKey(nodeId)) return;
      setState(() {
        _children[nodeId] = results
            .map((item) => BrowseTreeNode(
                  item: item,
                  depth: parentDepth + 1,
                  parentNodeId: nodeId,
                ))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadVariableDetails(NodeId nodeId) async {
    if (_detailLoadedFor == nodeId) return;
    setState(() {
      _detailLoading = true;
      _detailDescription = null;
      _detailValue = null;
      _detailDataType = null;
      _detailLoadedFor = nodeId;
    });
    try {
      final val = await widget.client.read(nodeId);
      if (!mounted || _detailLoadedFor != nodeId) return;
      setState(() {
        _detailValue = formatDynamicValue(val);
        if (val.description != null && val.description!.value.isNotEmpty) {
          _detailDescription = val.description!.value;
        }
        if (val.typeId != null) {
          _detailDataType = val.typeId.toString();
        }
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted || _detailLoadedFor != nodeId) return;
      setState(() {
        _detailValue = 'Error: $e';
        _detailLoading = false;
      });
    }
  }

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

  void _toggleExpand(BrowseTreeNode node) {
    if (!node.isExpandable) return;
    final nodeId = node.nodeId;
    if (_expanded.contains(nodeId)) {
      setState(() => _expanded.remove(nodeId));
    } else if (_children.containsKey(nodeId)) {
      setState(() => _expanded.add(nodeId));
    } else {
      _loadChildren(nodeId, node.depth);
    }
  }

  void _onTapNode(BrowseTreeNode node) {
    if (node.isVariable) {
      if (_selected?.nodeId == node.nodeId) {
        widget.onSelected(node.item);
      } else {
        setState(() => _selected = node);
        _loadVariableDetails(node.nodeId);
      }
    } else if (node.isExpandable) {
      _toggleExpand(node);
    }
  }

  void _onDoubleTapNode(BrowseTreeNode node) {
    if (node.isVariable) {
      widget.onSelected(node.item);
    }
  }

  @visibleForTesting
  List<BrowseTreeNode> flattenTree() {
    final flat = <BrowseTreeNode>[];
    void walk(List<BrowseTreeNode> nodes) {
      for (final node in nodes) {
        flat.add(node);
        if (node.isExpandable &&
            _expanded.contains(node.nodeId) &&
            _children.containsKey(node.nodeId)) {
          walk(_children[node.nodeId]!);
        }
      }
    }
    walk(_roots);
    return flat;
  }

  List<String> _buildBreadcrumb() {
    if (_selected == null) return ['Objects'];
    final path = <String>['Objects'];
    BrowseTreeNode? current = _selected;
    final segments = <String>[];
    while (current != null) {
      segments.insert(0, current.displayName);
      final parentId = current.parentNodeId;
      if (parentId == NodeId.objectsFolder) break;
      BrowseTreeNode? parent;
      for (final root in _roots) {
        parent = _findNode(root, parentId);
        if (parent != null) break;
      }
      current = parent;
    }
    path.addAll(segments);
    return path;
  }

  BrowseTreeNode? _findNode(BrowseTreeNode node, NodeId targetId) {
    if (node.nodeId == targetId) return node;
    final kids = _children[node.nodeId];
    if (kids == null) return null;
    for (final child in kids) {
      final found = _findNode(child, targetId);
      if (found != null) return found;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final flatNodes = flattenTree();
    final breadcrumb = _buildBreadcrumb();
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          child: Row(
            children: [
              FaIcon(FontAwesomeIcons.sitemap,
                  size: 14, color: cs.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browse: ${widget.serverAlias}',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onCancelled,
                child: Icon(Icons.close, size: 18, color: cs.secondary),
              ),
            ],
          ),
        ),
        // Breadcrumb
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: cs.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < breadcrumb.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_right,
                          size: 14, color: cs.secondary),
                    ),
                  Text(
                    breadcrumb[i],
                    style: TextStyle(
                      color: i == breadcrumb.length - 1
                          ? cs.onSurface
                          : cs.secondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Divider(height: 1, color: cs.surfaceContainerLow),
        // Tree
        Expanded(
          child: _rootLoading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SolarizedColors.cyan,
                    ),
                  ),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Error: $_error',
                          style:
                              TextStyle(color: cs.secondary, fontSize: 12),
                        ),
                      ),
                    )
                  : flatNodes.isEmpty
                      ? Center(
                          child: Text(
                            'No nodes found',
                            style: TextStyle(
                                color: cs.secondary, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          itemCount: flatNodes.length,
                          itemBuilder: (context, index) {
                            final node = flatNodes[index];
                            return BrowseNodeTile(
                              node: node,
                              isSelected:
                                  _selected?.nodeId == node.nodeId,
                              isExpanded:
                                  _expanded.contains(node.nodeId),
                              isLoading:
                                  _loading.contains(node.nodeId),
                              onTap: () => _onTapNode(node),
                              onDoubleTap: () =>
                                  _onDoubleTapNode(node),
                              onToggleExpand: () =>
                                  _toggleExpand(node),
                            );
                          },
                        ),
        ),
        if (_selected != null && _selected!.isVariable)
          VariableDetailStrip(
            node: _selected!,
            description: _detailDescription,
            value: _detailValue,
            dataType: _detailDataType,
            isLoading: _detailLoading,
          ),
        Divider(height: 1, color: cs.surfaceContainerLow),
        // Actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: cs.surfaceContainerLow,
          child: Row(
            children: [
              TextButton(
                onPressed: widget.onCancelled,
                child:
                    const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              TextButton(
                onPressed: _selected != null && _selected!.isVariable
                    ? () => widget.onSelected(_selected!.item)
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: SolarizedColors.cyan,
                ),
                child:
                    const Text('Select', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BrowseNodeTile extends StatelessWidget {
  final BrowseTreeNode node;
  final bool isSelected;
  final bool isExpanded;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleExpand;

  const BrowseNodeTile({
    super.key,
    required this.node,
    required this.isSelected,
    required this.isExpanded,
    required this.isLoading,
    required this.onTap,
    required this.onDoubleTap,
    required this.onToggleExpand,
  });

  Widget _buildIcon(ColorScheme cs) {
    switch (node.nodeClass) {
      case NodeClass.UA_NODECLASS_OBJECT:
        return const Icon(Icons.folder_outlined,
            size: 16, color: SolarizedColors.yellow);
      case NodeClass.UA_NODECLASS_VARIABLE:
        return const FaIcon(FontAwesomeIcons.tag,
            size: 12, color: SolarizedColors.green);
      case NodeClass.UA_NODECLASS_METHOD:
        return Icon(Icons.play_arrow,
            size: 16, color: cs.primary.withAlpha(120));
      default:
        return Icon(Icons.circle, size: 8, color: cs.secondary);
    }
  }

  Widget _buildExpandWidget(ColorScheme cs) {
    if (!node.isExpandable) {
      return const SizedBox(width: 18);
    }
    if (isLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: Padding(
          padding: EdgeInsets.all(3),
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: SolarizedColors.cyan),
        ),
      );
    }
    return GestureDetector(
      onTap: onToggleExpand,
      child: SizedBox(
        width: 18,
        child: AnimatedRotation(
          turns: isExpanded ? 0.25 : 0,
          duration: Duration.zero,
          child: Icon(Icons.chevron_right, size: 16, color: cs.secondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMethod = node.nodeClass == NodeClass.UA_NODECLASS_METHOD;
    final textColor = isMethod ? cs.secondary : cs.onSurface;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: 36,
        padding: EdgeInsets.only(left: node.depth * 20.0 + 4, right: 8),
        color: isSelected
            ? SolarizedColors.cyan.withAlpha(25)
            : Colors.transparent,
        child: Row(
          children: [
            _buildExpandWidget(cs),
            const SizedBox(width: 4),
            _buildIcon(cs),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.displayName,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight:
                      node.isVariable ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              node.nodeId.toString(),
              style: TextStyle(
                color: cs.secondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VariableDetailStrip extends StatelessWidget {
  final BrowseTreeNode node;
  final String? description;
  final String? value;
  final String? dataType;
  final bool isLoading;

  const VariableDetailStrip({
    super.key,
    required this.node,
    this.description,
    this.value,
    this.dataType,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border:
            Border(top: BorderSide(color: SolarizedColors.cyan.withAlpha(40))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              FaIcon(FontAwesomeIcons.tag,
                  size: 10, color: SolarizedColors.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.nodeId.toString(),
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (dataType != null) ...[
                const SizedBox(width: 12),
                Text(
                  dataType!,
                  style: TextStyle(color: cs.secondary, fontSize: 10),
                ),
              ],
              if (isLoading) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: SolarizedColors.cyan,
                  ),
                ),
              ],
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(color: cs.secondary, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (value != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('val ',
                    style: TextStyle(color: cs.secondary, fontSize: 10)),
                Expanded(
                  child: Text(
                    value!,
                    style: TextStyle(
                      color: SolarizedColors.cyan,
                      fontSize: 11,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
