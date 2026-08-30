import 'package:mcp_dart/mcp_dart.dart';

import '../services/alarm_service.dart';
import 'tool_registry.dart';

/// Registers the alarm-tree MCP tool.
///
/// Alarms are grouped by `AlarmConfig.group` — an address read outermost
/// first, like a package name — and the stop timeline renders that tree
/// directly. A model asked to add or move an alarm needs to see the tree
/// first, or it invents a near-duplicate group name ("Line3", "Line 3 ") and
/// silently splits a machine's history in two.
void registerAlarmTreeTools(ToolRegistry registry, AlarmService alarmService) {
  registry.registerTool(
    name: 'get_alarm_tree',
    description: 'Show how alarms are grouped, as an indented tree. '
        'Call this before create_alarm or before moving an alarm with '
        'update_alarm, so the `group` you pass reuses a name that already '
        'exists instead of creating a near-duplicate.',
    inputSchema: JsonSchema.object(
      properties: {
        'group': JsonSchema.array(
          description: 'Show only this subtree, outermost first -- '
              '["Line 3"]. Omit for the whole tree.',
          items: JsonSchema.string(),
        ),
      },
    ),
    handler: (arguments, extra) async {
      final scope = (arguments['group'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];

      final configs = alarmService.getAllAlarmConfigs();
      final tree = buildAlarmGroupTree(configs);
      final rendered = renderAlarmGroupTree(tree, scope: scope);

      if (rendered.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: scope.isEmpty
                  ? 'No alarms are configured.'
                  : 'No alarms are grouped under ${scope.join(' > ')}.',
            )
          ],
        );
      }
      return CallToolResult(content: [TextContent(text: rendered)]);
    },
  );
}

/// A group in the alarm tree, built from alarm config maps.
///
/// The MCP server cannot use tfc_dart's `AlarmTree`: it lives beside
/// `AlarmConfig`, which reaches open62541 through the expression types, and
/// this package deliberately stays free of FFI. Grouping strings into a trie
/// is small enough to be worth repeating rather than dragging that in.
class AlarmGroupNode {
  AlarmGroupNode(this.name);

  final String name;

  /// Nested groups, keyed by name, in first-appearance order.
  final Map<String, AlarmGroupNode> children = {};

  /// Titles of alarms sitting directly in this group.
  final List<String> alarms = [];

  /// The title of the alarm bound to this group, when one is.
  String? bound;

  /// Alarms here and everywhere nested inside.
  int get total =>
      alarms.length +
      (bound == null ? 0 : 1) +
      children.values.fold(0, (n, c) => n + c.total);
}

/// Groups alarm config maps into a tree by their `group` address.
AlarmGroupNode buildAlarmGroupTree(List<Map<String, dynamic>> configs) {
  final root = AlarmGroupNode('');
  for (final config in configs) {
    final address = (config['group'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final title = config['title'] as String? ?? config['uid'] as String? ?? '?';

    var current = root;
    for (final segment in address) {
      current = current.children.putIfAbsent(
          segment, () => AlarmGroupNode(segment));
    }
    // Binding to the root is meaningless, and a group keeps the first alarm
    // claiming it -- the rest stay ordinary members rather than vanishing.
    if (config['bindToGroup'] == true &&
        address.isNotEmpty &&
        current.bound == null) {
      current.bound = title;
    } else {
      current.alarms.add(title);
    }
  }
  return root;
}

/// Renders [root] as an indented tree, optionally only the [scope] subtree.
String renderAlarmGroupTree(
  AlarmGroupNode root, {
  List<String> scope = const [],
}) {
  var start = root;
  for (final segment in scope) {
    final next = start.children[segment];
    if (next == null) return '';
    start = next;
  }

  final buffer = StringBuffer();
  if (scope.isNotEmpty) {
    _write(buffer, start, 0, isScopeRoot: true);
  } else {
    for (final child in start.children.values) {
      _write(buffer, child, 0);
    }
    for (final alarm in start.alarms) {
      buffer.writeln('- $alarm  (ungrouped)');
    }
  }
  return buffer.toString().trimRight();
}

void _write(StringBuffer out, AlarmGroupNode group, int depth,
    {bool isScopeRoot = false}) {
  final pad = '  ' * depth;
  out.writeln('$pad${group.name}  (${group.total})');
  if (group.bound != null) {
    out.writeln('$pad  * ${group.bound}   <- this alarm IS the group');
  }
  for (final child in group.children.values) {
    _write(out, child, depth + 1);
  }
  for (final alarm in group.alarms) {
    out.writeln('$pad  - $alarm');
  }
  if (isScopeRoot) return;
}
