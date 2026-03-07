import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme.dart' show SolarizedColors;

// ---------------------------------------------------------------------------
// Protocol-agnostic browse types
// ---------------------------------------------------------------------------

/// The type of a node in the browse tree.
enum BrowseNodeType { folder, variable, method, other }

/// A protocol-agnostic node in the browse tree.
///
/// For OPC UA: [id] is the NodeId string (e.g. "ns=2;s=MyVar").
/// For UMAS: [id] is the variable path.
class BrowseNode {
  final String id;
  final String displayName;
  final BrowseNodeType type;
  final String? dataType;
  final String? description;
  final Map<String, String> metadata;

  const BrowseNode({
    required this.id,
    required this.displayName,
    required this.type,
    this.dataType,
    this.description,
    this.metadata = const {},
  });

  bool get isExpandable =>
      type == BrowseNodeType.folder || type == BrowseNodeType.variable;
  bool get isVariable => type == BrowseNodeType.variable;
  bool get isFolder => type == BrowseNodeType.folder;
}

/// Detail information about a selected node.
class BrowseNodeDetail {
  final String? description;
  final String? value;
  final String? dataType;
  final List<BrowseNode>? structChildren;

  const BrowseNodeDetail({
    this.description,
    this.value,
    this.dataType,
    this.structChildren,
  });
}

/// Protocol-agnostic data source for the browse panel.
///
/// Implement this for each protocol (OPC UA, UMAS, etc.).
abstract class BrowseDataSource {
  Future<List<BrowseNode>> fetchRoots();
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent);
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node);
}

// ---------------------------------------------------------------------------
// Internal tree node (adds depth + parentId tracking)
// ---------------------------------------------------------------------------

class _TreeNode {
  final BrowseNode node;
  final int depth;
  final String parentId;

  const _TreeNode({
    required this.node,
    required this.depth,
    required this.parentId,
  });

  String get id => node.id;
  String get displayName => node.displayName;
  BrowseNodeType get type => node.type;
  bool get isExpandable => node.isExpandable;
  bool get isVariable => node.isVariable;
}

// ---------------------------------------------------------------------------
// BrowsePanel widget
// ---------------------------------------------------------------------------

/// Shows an address-space browser in a dialog sized at 80% of the screen.
/// Returns the selected [BrowseNode] or null if cancelled.
Future<BrowseNode?> showBrowseDialog({
  required BuildContext context,
  required BrowseDataSource dataSource,
  required String serverAlias,
}) {
  return showDialog<BrowseNode>(
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
            child: BrowsePanel(
              dataSource: dataSource,
              serverAlias: serverAlias,
              onSelected: (node) => Navigator.of(context).pop(node),
              onCancelled: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    },
  );
}

/// Protocol-agnostic browse panel that displays a tree of nodes from a
/// [BrowseDataSource]. This is the panel content -- it does NOT include a
/// Dialog wrapper. Use [showBrowseDialog] for the dialog version, or embed
/// this widget directly.
class BrowsePanel extends StatefulWidget {
  final BrowseDataSource dataSource;
  final String serverAlias;
  final ValueChanged<BrowseNode> onSelected;
  final VoidCallback onCancelled;

  const BrowsePanel({
    super.key,
    required this.dataSource,
    required this.serverAlias,
    required this.onSelected,
    required this.onCancelled,
  });

  @override
  State<BrowsePanel> createState() => BrowsePanelState();
}

@visibleForTesting
class BrowsePanelState extends State<BrowsePanel> {
  List<_TreeNode> _roots = [];
  final Map<String, List<_TreeNode>> _children = {};
  final Set<String> _expanded = {};
  final Set<String> _loading = {};
  _TreeNode? _selected;
  bool _rootLoading = true;
  String? _error;

  // Detail strip state for selected variable
  String? _detailDescription;
  String? _detailValue;
  String? _detailDataType;
  bool _detailLoading = false;
  String? _detailLoadedFor;

  @visibleForTesting
  BrowseNode? get selected => _selected?.node;
  @visibleForTesting
  List<BrowseNode> get roots => _roots.map((t) => t.node).toList();
  @visibleForTesting
  bool get rootLoading => _rootLoading;
  @visibleForTesting
  String? get error => _error;

  static const String _rootParentId = '__root__';

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    try {
      final results = await widget.dataSource.fetchRoots();
      if (!mounted) return;
      final roots = results
          .map((node) => _TreeNode(
                node: node,
                depth: 0,
                parentId: _rootParentId,
              ))
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
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

  Future<void> _loadChildren(String nodeId, BrowseNode browseNode,
      int parentDepth) async {
    if (_loading.contains(nodeId)) return;
    setState(() => _loading.add(nodeId));
    try {
      final results = await widget.dataSource.fetchChildren(browseNode);
      if (!mounted) return;
      final nodes = results
          .map((node) => _TreeNode(
                node: node,
                depth: parentDepth + 1,
                parentId: nodeId,
              ))
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
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

  void _prefetchChildren(List<_TreeNode> nodes) {
    for (final node in nodes) {
      if (node.isExpandable && !_children.containsKey(node.id)) {
        _prefetchSingle(node);
      }
    }
  }

  Future<void> _prefetchSingle(_TreeNode treeNode) async {
    if (_children.containsKey(treeNode.id)) return;
    try {
      final results = await widget.dataSource.fetchChildren(treeNode.node);
      if (!mounted) return;
      if (_children.containsKey(treeNode.id)) return;
      setState(() {
        _children[treeNode.id] = results
            .map((node) => _TreeNode(
                  node: node,
                  depth: treeNode.depth + 1,
                  parentId: treeNode.id,
                ))
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
      });
    } catch (_) {}
  }

  Future<void> _loadVariableDetails(_TreeNode treeNode) async {
    final nodeId = treeNode.id;
    if (_detailLoadedFor == nodeId) return;
    setState(() {
      _detailLoading = true;
      _detailDescription = null;
      _detailValue = null;
      _detailDataType = null;
      _detailLoadedFor = nodeId;
    });
    try {
      final detail = await widget.dataSource.fetchDetail(treeNode.node);
      if (!mounted || _detailLoadedFor != nodeId) return;
      setState(() {
        _detailValue = detail.value;
        _detailDescription = detail.description;
        _detailDataType = detail.dataType;
        _detailLoading = false;

        // Synthesize children from struct fields when the data source provides
        // them and the browse tree has no children yet.
        if (detail.structChildren != null &&
            detail.structChildren!.isNotEmpty &&
            (!_children.containsKey(nodeId) ||
                _children[nodeId]!.isEmpty)) {
          final depth = treeNode.depth;
          _children[nodeId] = detail.structChildren!
              .map((child) => _TreeNode(
                    node: child,
                    depth: depth + 1,
                    parentId: nodeId,
                  ))
              .toList();
          _expanded.add(nodeId);
        }
      });
    } catch (e) {
      if (!mounted || _detailLoadedFor != nodeId) return;
      setState(() {
        _detailValue = 'Error: $e';
        _detailLoading = false;
      });
    }
  }

  void _toggleExpand(_TreeNode treeNode) {
    if (!treeNode.isExpandable) return;
    final nodeId = treeNode.id;
    if (_expanded.contains(nodeId)) {
      setState(() => _expanded.remove(nodeId));
    } else if (_children.containsKey(nodeId)) {
      setState(() => _expanded.add(nodeId));
    } else {
      _loadChildren(nodeId, treeNode.node, treeNode.depth);
    }
  }

  void _onTapNode(_TreeNode treeNode) {
    if (treeNode.isVariable) {
      if (_selected?.id == treeNode.id) {
        widget.onSelected(treeNode.node);
      } else {
        setState(() => _selected = treeNode);
        _loadVariableDetails(treeNode);
      }
    } else if (treeNode.isExpandable) {
      _toggleExpand(treeNode);
    }
  }

  void _onDoubleTapNode(_TreeNode treeNode) {
    if (treeNode.isVariable) {
      widget.onSelected(treeNode.node);
    }
  }

  @visibleForTesting
  List<_TreeNode> flattenTree() {
    final flat = <_TreeNode>[];
    void walk(List<_TreeNode> nodes) {
      for (final node in nodes) {
        flat.add(node);
        if (node.isExpandable &&
            _expanded.contains(node.id) &&
            _children.containsKey(node.id)) {
          walk(_children[node.id]!);
        }
      }
    }
    walk(_roots);
    return flat;
  }

  List<String> _buildBreadcrumb() {
    if (_selected == null) return ['Root'];
    final path = <String>['Root'];
    _TreeNode? current = _selected;
    final segments = <String>[];
    while (current != null) {
      segments.insert(0, current.displayName);
      final parentId = current.parentId;
      if (parentId == _rootParentId) break;
      _TreeNode? parent;
      for (final root in _roots) {
        parent = _findNode(root, parentId);
        if (parent != null) break;
      }
      current = parent;
    }
    path.addAll(segments);
    return path;
  }

  _TreeNode? _findNode(_TreeNode node, String targetId) {
    if (node.id == targetId) return node;
    final kids = _children[node.id];
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
                            final treeNode = flatNodes[index];
                            final kids = _children[treeNode.id];
                            return BrowseNodeTile(
                              node: treeNode,
                              isSelected:
                                  _selected?.id == treeNode.id,
                              isExpanded:
                                  _expanded.contains(treeNode.id),
                              isLoading:
                                  _loading.contains(treeNode.id),
                              hasChildren:
                                  kids != null && kids.isNotEmpty,
                              onTap: () => _onTapNode(treeNode),
                              onDoubleTap: () =>
                                  _onDoubleTapNode(treeNode),
                              onToggleExpand: () =>
                                  _toggleExpand(treeNode),
                            );
                          },
                        ),
        ),
        if (_selected != null && _selected!.isVariable)
          VariableDetailStrip(
            displayName: _selected!.displayName,
            nodeId: _selected!.id,
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
                    ? () => widget.onSelected(_selected!.node)
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

// ---------------------------------------------------------------------------
// BrowseNodeTile
// ---------------------------------------------------------------------------

class BrowseNodeTile extends StatelessWidget {
  final _TreeNode node;
  final bool isSelected;
  final bool isExpanded;
  final bool isLoading;
  final bool hasChildren;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleExpand;

  const BrowseNodeTile({
    super.key,
    required this.node,
    required this.isSelected,
    required this.isExpanded,
    required this.isLoading,
    required this.hasChildren,
    required this.onTap,
    required this.onDoubleTap,
    required this.onToggleExpand,
  });

  Widget _buildIcon(ColorScheme cs) {
    switch (node.type) {
      case BrowseNodeType.folder:
        return const Icon(Icons.folder_outlined,
            size: 16, color: SolarizedColors.yellow);
      case BrowseNodeType.variable:
        return const FaIcon(FontAwesomeIcons.tag,
            size: 12, color: SolarizedColors.green);
      case BrowseNodeType.method:
        return Icon(Icons.play_arrow,
            size: 16, color: cs.primary.withAlpha(120));
      case BrowseNodeType.other:
        return Icon(Icons.circle, size: 8, color: cs.secondary);
    }
  }

  Widget _buildExpandWidget(ColorScheme cs) {
    if (!node.isExpandable || (node.isVariable && !hasChildren)) {
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
    final isMethod = node.type == BrowseNodeType.method;
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
              node.id,
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

// ---------------------------------------------------------------------------
// VariableDetailStrip
// ---------------------------------------------------------------------------

class VariableDetailStrip extends StatelessWidget {
  final String displayName;
  final String nodeId;
  final String? description;
  final String? value;
  final String? dataType;
  final bool isLoading;

  const VariableDetailStrip({
    super.key,
    required this.displayName,
    required this.nodeId,
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
                  nodeId,
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
