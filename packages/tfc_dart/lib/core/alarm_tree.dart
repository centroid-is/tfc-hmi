import 'alarm.dart';

/// One node of the alarm tree — a group named by a segment of
/// [AlarmConfig.path].
///
/// A node is not itself an alarm, with one exception: [bound] is the alarm
/// that *is* this node, the coarse signal for equipment whose finer alarms do
/// not exist yet.
class AlarmNode {
  /// The last segment of [path]. Empty for the root.
  final String name;

  /// Full path from the root, outermost first. Empty for the root.
  final List<String> path;

  final AlarmNode? parent;

  /// Sub-groups, in the order their first alarm appeared in the config.
  final List<AlarmNode> children = [];

  /// Diagnosis alarms hanging directly off this node, in config order.
  final List<AlarmConfig> alarms = [];

  /// This node's own alarm, when one is bound to it. See
  /// [AlarmConfig.bindToPath].
  AlarmConfig? bound;

  AlarmNode._({required this.name, required this.path, this.parent});

  bool get isRoot => path.isEmpty;

  /// Zero for a top-level group; the root itself is -1.
  int get depth => path.length - 1;

  /// Whether expanding this node would reveal anything.
  bool get hasChildren => children.isNotEmpty || alarms.isNotEmpty;

  /// This node's own alarm, its leaves, and everything beneath it.
  ///
  /// This is what a collapsed group lane draws the union of.
  Iterable<AlarmConfig> get subtreeAlarms sync* {
    final b = bound;
    if (b != null) yield b;
    yield* alarms;
    for (final child in children) {
      yield* child.subtreeAlarms;
    }
  }

  @override
  String toString() => 'AlarmNode(${path.join(' › ')})';
}

/// One line of the timeline's label column, already flattened and indented.
///
/// Exactly one of [node] and [alarm] is set: a group row carries the node, an
/// alarm row carries the alarm.
class AlarmTreeRow {
  /// Set on a group row.
  final AlarmNode? node;

  /// Set on an alarm row.
  final AlarmConfig? alarm;

  /// True when [alarm] is the bound alarm of the group directly above it, so
  /// the UI can mark it as the branch's own signal rather than a diagnosis.
  final bool isBound;

  /// Indentation, already adjusted for the scope the rows were built with —
  /// the outermost visible row is always zero.
  final int depth;

  const AlarmTreeRow._({
    this.node,
    this.alarm,
    required this.isBound,
    required this.depth,
  });

  bool get isGroup => node != null;

  String get label => node?.name ?? alarm!.title;

  @override
  String toString() => 'AlarmTreeRow(${'  ' * depth}$label)';
}

/// The alarm definitions arranged as a tree by [AlarmConfig.path].
///
/// Building this is the only interpretation step between the alarm system and
/// anything that groups alarms; consumers pick a scope and render the rows.
class AlarmTree {
  final AlarmNode root;

  AlarmTree._(this.root);

  factory AlarmTree.fromConfigs(Iterable<AlarmConfig> configs) {
    final root = AlarmNode._(name: '', path: const []);
    for (final config in configs) {
      final node = _nodeFor(root, config.path);
      // A bound alarm needs a node to be; at the root there is none, and a
      // node keeps the first alarm claiming it. Either way the alarm becomes
      // an ordinary leaf rather than disappearing.
      if (config.bindToPath && !node.isRoot && node.bound == null) {
        node.bound = config;
      } else {
        node.alarms.add(config);
      }
    }
    return AlarmTree._(root);
  }

  static AlarmNode _nodeFor(AlarmNode root, List<String> path) {
    var current = root;
    for (var i = 0; i < path.length; i++) {
      final segment = path[i];
      var next =
          current.children.where((c) => c.name == segment).firstOrNull;
      if (next == null) {
        next = AlarmNode._(
          name: segment,
          path: List.unmodifiable(path.sublist(0, i + 1)),
          parent: current,
        );
        current.children.add(next);
      }
      current = next;
    }
    return current;
  }

  /// The node at [path], or null when no alarm is defined under it.
  ///
  /// Returning null rather than an empty node is deliberate: a path that has
  /// stopped matching — because a segment was renamed in the alarm
  /// definitions — should be reportable, not silently drawn as empty.
  AlarmNode? nodeAt(List<String> path) {
    var current = root;
    for (final segment in path) {
      final next = current.children.where((c) => c.name == segment).firstOrNull;
      if (next == null) return null;
      current = next;
    }
    return current;
  }

  /// Rows in display order for an asset scoped to [scope].
  ///
  /// [scope] is a list of paths — the entire configuration a stop-timeline
  /// asset needs. Empty means the whole tree. Each scoped subtree is
  /// re-indented so its own node sits at depth zero, and paths that no longer
  /// match simply contribute nothing.
  ///
  /// Order within a node is: the node, its own alarm (only when it also has
  /// children — otherwise the node row already is that alarm), then its
  /// sub-groups, then its own leaf alarms.
  List<AlarmTreeRow> rows({List<List<String>> scope = const []}) {
    final rows = <AlarmTreeRow>[];
    if (scope.isEmpty) {
      for (final child in root.children) {
        _emit(child, 0, rows);
      }
      // alarms defined with no path at all
      for (final leaf in root.alarms) {
        rows.add(AlarmTreeRow._(alarm: leaf, isBound: false, depth: 0));
      }
      return rows;
    }

    final seen = <AlarmNode>{};
    for (final path in scope) {
      final node = nodeAt(path);
      if (node == null || node.isRoot || !seen.add(node)) continue;
      // a node already covered by a broader scope path must not repeat
      if (node.ancestors.any(seen.contains)) continue;
      _emit(node, 0, rows);
    }
    return rows;
  }

  void _emit(AlarmNode node, int depth, List<AlarmTreeRow> out) {
    out.add(AlarmTreeRow._(node: node, isBound: false, depth: depth));
    final bound = node.bound;
    // A branch whose only alarm is the bound one is already represented by its
    // own row; repeating it would be a lane drawn twice. A branch that also
    // has children needs the row, or its lane would show intervals that
    // nothing underneath it explains.
    if (bound != null && node.hasChildren) {
      out.add(AlarmTreeRow._(alarm: bound, isBound: true, depth: depth + 1));
    }
    for (final child in node.children) {
      _emit(child, depth + 1, out);
    }
    for (final leaf in node.alarms) {
      out.add(AlarmTreeRow._(alarm: leaf, isBound: false, depth: depth + 1));
    }
  }
}

extension on AlarmNode {
  Iterable<AlarmNode> get ancestors sync* {
    var current = parent;
    while (current != null) {
      yield current;
      current = current.parent;
    }
  }
}
