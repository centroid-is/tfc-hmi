import 'alarm.dart';

/// One group in the alarm tree, named by a segment of [AlarmConfig.group].
///
/// A group is not itself an alarm, with one exception: [bound] is the alarm
/// that *is* this group, the coarse signal for equipment whose finer alarms
/// do not exist yet.
class AlarmGroup {
  /// The last segment of [path]. Empty for the root.
  final String name;

  /// This group's address from the root, outermost first — the value an
  /// [AlarmConfig.group] must carry to land here. Empty for the root.
  final List<String> path;

  final AlarmGroup? parent;

  /// Nested groups, in the order their first alarm appeared in the config.
  final List<AlarmGroup> children = [];

  /// Diagnosis alarms sitting directly in this group, in config order.
  final List<AlarmConfig> alarms = [];

  /// This group's own alarm, when one is bound to it. See
  /// [AlarmConfig.bindToGroup].
  AlarmConfig? bound;

  AlarmGroup._({required this.name, required this.path, this.parent});

  bool get isRoot => path.isEmpty;

  /// Zero for a top-level group; the root itself is -1.
  int get depth => path.length - 1;

  /// Whether expanding this group would reveal anything.
  bool get hasChildren => children.isNotEmpty || alarms.isNotEmpty;

  /// This group's own alarm, its members, and everything nested inside it.
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
  String toString() => 'AlarmGroup(${path.join(' › ')})';
}

/// One line of the timeline's label column, already flattened and indented.
///
/// Exactly one of [group] and [alarm] is set: a group row carries the group,
/// an alarm row carries the alarm.
class AlarmTreeRow {
  /// Set on a group row.
  final AlarmGroup? group;

  /// Set on an alarm row.
  final AlarmConfig? alarm;

  /// True when [alarm] is the bound alarm of the group directly above it, so
  /// the UI can mark it as the branch's own signal rather than a diagnosis.
  final bool isBound;

  /// Indentation, already adjusted for the scope the rows were built with —
  /// the outermost visible row is always zero.
  final int depth;

  const AlarmTreeRow._({
    this.group,
    this.alarm,
    required this.isBound,
    required this.depth,
  });

  bool get isGroup => group != null;

  String get label => group?.name ?? alarm!.title;

  @override
  String toString() => 'AlarmTreeRow(${'  ' * depth}$label)';
}

/// The alarm definitions arranged as a tree by [AlarmConfig.group].
///
/// Building this is the only interpretation step between the alarm system and
/// anything that groups alarms; consumers pick a scope and render the rows.
class AlarmTree {
  final AlarmGroup root;

  AlarmTree._(this.root);

  factory AlarmTree.fromConfigs(Iterable<AlarmConfig> configs) {
    final root = AlarmGroup._(name: '', path: const []);
    for (final config in configs) {
      final group = _groupFor(root, config.group);
      // A bound alarm needs a group to be; at the root there is none, and a
      // group keeps the first alarm claiming it. Either way the alarm becomes
      // an ordinary member rather than disappearing.
      if (config.bindToGroup && !group.isRoot && group.bound == null) {
        group.bound = config;
      } else {
        group.alarms.add(config);
      }
    }
    return AlarmTree._(root);
  }

  static AlarmGroup _groupFor(AlarmGroup root, List<String> path) {
    var current = root;
    for (var i = 0; i < path.length; i++) {
      final segment = path[i];
      var next =
          current.children.where((c) => c.name == segment).firstOrNull;
      if (next == null) {
        next = AlarmGroup._(
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

  /// The group at [path], or null when no alarm is defined in it.
  ///
  /// Returning null rather than an empty group is deliberate: a group that has
  /// stopped matching — because a segment was renamed in the alarm
  /// definitions — should be reportable, not silently drawn as empty.
  AlarmGroup? groupAt(List<String> path) {
    var current = root;
    for (final segment in path) {
      final next = current.children.where((c) => c.name == segment).firstOrNull;
      if (next == null) return null;
      current = next;
    }
    return current;
  }

  /// Rows in display order, showing only [groups].
  ///
  /// [groups] is a list of group addresses — the entire configuration a
  /// stop-timeline asset needs. Empty means the whole tree. Each one is
  /// re-indented so it sits at depth zero, and an address that no longer
  /// matches simply contributes nothing rather than throwing.
  ///
  /// Order within a group is: the group, its own alarm (only when it also has
  /// members — otherwise the group row already is that alarm), then its
  /// nested groups, then its own alarms.
  List<AlarmTreeRow> rows({List<List<String>> groups = const []}) {
    final rows = <AlarmTreeRow>[];
    if (groups.isEmpty) {
      for (final child in root.children) {
        _emit(child, 0, rows);
      }
      // alarms defined with no group at all
      for (final leaf in root.alarms) {
        rows.add(AlarmTreeRow._(alarm: leaf, isBound: false, depth: 0));
      }
      return rows;
    }

    final seen = <AlarmGroup>{};
    for (final address in groups) {
      final group = groupAt(address);
      if (group == null || group.isRoot || !seen.add(group)) continue;
      // a group already covered by a broader address must not repeat
      if (group.ancestors.any(seen.contains)) continue;
      _emit(group, 0, rows);
    }
    return rows;
  }

  void _emit(AlarmGroup group, int depth, List<AlarmTreeRow> out) {
    out.add(AlarmTreeRow._(group: group, isBound: false, depth: depth));
    final bound = group.bound;
    // A group whose only alarm is the bound one is already represented by its
    // own row; repeating it would draw the same lane twice. A group that also
    // has members needs the row, or its lane would show intervals that nothing
    // inside it explains.
    if (bound != null && group.hasChildren) {
      out.add(AlarmTreeRow._(alarm: bound, isBound: true, depth: depth + 1));
    }
    for (final child in group.children) {
      _emit(child, depth + 1, out);
    }
    for (final member in group.alarms) {
      out.add(AlarmTreeRow._(alarm: member, isBound: false, depth: depth + 1));
    }
  }
}

extension on AlarmGroup {
  Iterable<AlarmGroup> get ancestors sync* {
    var current = parent;
    while (current != null) {
      yield current;
      current = current.parent;
    }
  }
}
