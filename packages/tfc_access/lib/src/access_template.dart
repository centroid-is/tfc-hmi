import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'access_group.dart';

/// The reserved member name standing for the key as a whole.
///
/// `*` is not a legal IEC 61131-3 identifier — those are letters, digits and
/// underscores starting with a letter or underscore — so this row can never
/// collide with a struct member read off a PLC. That is asserted by a test
/// rather than left as a claim (T-04-04).
const String kWholeKeyMember = '*';

/// A user-defined, named set of member-to-group rules (spec §7b).
///
/// Templates are **not defined in code**; the app ships none and the
/// commissioning engineer creates them. This class is only the shape: a name
/// and a map from struct member name — or [kWholeKeyMember] — to the
/// [AccessGroup] a write to that member requires.
///
/// It exists because one conveyor key carries both `p_cmd_JogFwd` and
/// `p_cfg_ManualFreq` through a single `stateMan.write(key, wholeStruct)`. A
/// group per *asset* cannot separate jogging from changing drive frequency; a
/// group per *member* can.
@immutable
class AccessTemplate {
  /// Builds a template over a **copy** of [rules].
  ///
  /// The copy matters: the caller is usually a store handing over the map it
  /// just decoded from a row, and a template whose answers change when
  /// somebody else's map is mutated is a write-path decision that moves under
  /// its reader.
  factory AccessTemplate({
    required String name,
    required Map<String, AccessGroup> rules,
  }) =>
      AccessTemplate._(
        name: name,
        rules: Map<String, AccessGroup>.unmodifiable(rules),
      );

  const AccessTemplate._({required this.name, required this.rules});

  /// The template's name, and its primary key in the `access_template` table.
  final String name;

  /// Member name to required group. Unmodifiable.
  ///
  /// [kWholeKeyMember] is a legal key here and means the key as a whole; see
  /// [groupFor].
  final Map<String, AccessGroup> rules;

  /// The group required to write [member], or **null for unrestricted**.
  ///
  /// A [member] of null asks about the whole key — a scalar write, where there
  /// is no member to name.
  ///
  /// **Resolution order:** an explicit rule for [member], then the
  /// [kWholeKeyMember] row, then null.
  ///
  /// **The one ambiguity in spec §7d, and how this file reads it.** §7d calls
  /// the whole-key row "a special row for scalar keys", which leaves open
  /// whether it also applies to a struct member the template does not mention.
  /// This file reads it as **yes**: [kWholeKeyMember] is the key-level default,
  /// applied to a scalar write *and* to any member without its own rule.
  ///
  /// The reading being rejected is that the row answers **only** when the write
  /// has no member — scalars and nothing else. Rejected because it would make a
  /// template unable to say "this whole conveyor needs `device` except
  /// jogging", which is the shape a commissioning engineer actually wants and
  /// the only shape that scales past the four struct-writing assets: under the
  /// narrow reading every member of every bound key would have to be enumerated
  /// by hand, and a member added to the PLC later would silently arrive
  /// unrestricted.
  ///
  /// Null wherever nobody has said otherwise. Spec §7b: "No template means no
  /// restriction", and so does a member no bound template mentions.
  AccessGroup? groupFor(String? member) {
    if (member != null) {
      final explicit = rules[member];
      if (explicit != null) return explicit;
    }
    return rules[kWholeKeyMember];
  }

  /// The `access_template.rules` TEXT column: a JSON object of
  /// `member -> AccessGroup.name`, **sorted by member name**.
  ///
  /// Sorted so two equal templates encode byte-identically — a save that
  /// changes nothing must not look like a change — and so a diff of the stored
  /// blob is readable by a person. Same reasoning as
  /// `AccessRole.encodeGroups`, which emits in enum order for the same reason.
  static String encodeRules(Map<String, AccessGroup> rules) {
    final sorted = <String, String>{};
    for (final member in rules.keys.toList()..sort()) {
      sorted[member] = rules[member]!.name;
    }
    return jsonEncode(sorted);
  }

  /// Read an `access_template.rules` column back into a rule map.
  ///
  /// **Forgiving on purpose, and it must not become fail-closed.** A name this
  /// build does not recognise costs that one rule; a malformed blob costs the
  /// whole rule set; neither throws. This value is read on the write path of
  /// every jog, start and alarm ack, and a rules blob written by a newer build
  /// naming a group this one does not have must cost that one rule, never the
  /// plant's controls.
  ///
  /// This is the same judgement as `AccessPolicy.groupForTag`'s swallow-to-null
  /// arm one file over, applied one level down — see the comment there rather
  /// than a restatement here. Note the direction: a dropped rule makes a member
  /// *less* restricted, which is the fail-open half of spec §7b working as
  /// designed, and the visibility requirement (§7b, §7d) is what covers it.
  static Map<String, AccessGroup> decodeRules(String json) {
    if (json.isEmpty) return const <String, AccessGroup>{};
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const <String, AccessGroup>{};
    }
    if (decoded is! Map) return const <String, AccessGroup>{};
    final rules = <String, AccessGroup>{};
    decoded.forEach((member, value) {
      if (member is! String || value is! String) return;
      final group = AccessGroup.byName(value);
      if (group != null) rules[member] = group;
    });
    return rules;
  }

  /// True when [name] is usable as a template name.
  ///
  /// Non-empty, already trimmed, and at most 64 characters — the column width.
  /// A **predicate the callers use**, not a constructor precondition: the UI
  /// and the MCP tools validate before writing, while a row already in the
  /// database must still load into an object even if it was written by
  /// something less careful. A throwing constructor would turn one bad row into
  /// a station that cannot read its bindings at all.
  static bool isValidTemplateName(String name) =>
      name.isNotEmpty && name.trim() == name && name.length <= 64;

  static const MapEquality<String, AccessGroup> _ruleEquality =
      MapEquality<String, AccessGroup>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccessTemplate &&
          other.name == name &&
          _ruleEquality.equals(other.rules, rules);

  @override
  int get hashCode => Object.hash(name, _ruleEquality.hash(rules));

  @override
  String toString() => 'AccessTemplate($name, ${encodeRules(rules)})';
}
