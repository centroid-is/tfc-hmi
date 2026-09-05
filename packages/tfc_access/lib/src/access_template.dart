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

/// Whether a [TagBindingResolver] has been told what the bindings are.
///
/// **[neverLoaded] answers null, exactly like a snapshot that loaded and found
/// nothing — and the two are still different values.** Both halves of that
/// matter, and they pull in opposite directions:
///
/// *Why [neverLoaded] is permissive.* A conservative floor cannot work here.
/// This object does not know which keys exist — the key universe lives in
/// `stateMan.keyMappings`, which this package cannot see — so "strict until
/// loaded" has no way to be strict about the right things. It would refuse
/// every write on a panel that is merely still booting, and on a station with
/// no database it would refuse them for ever. That is an outage, not a
/// safeguard, and it is the failure spec §7b's fail-open rule exists to avoid.
///
/// *Why the states are nevertheless distinct.* If "nobody has told me yet" and
/// "nothing is bound" were the same value, a station where the load never
/// happened would be byte-identical, from every screen, to one that is
/// deliberately unconfigured — every bound key silently unrestricted, and every
/// test still green. So the distinction is carried by
/// [TagBindingResolver.state] rather than by the answers: plan 04-05 uses it to
/// force the load, and 04-08 renders "bindings not loaded" rather than "no keys
/// bound".
enum TagBindingSnapshotState {
  /// [TagBindingResolver.setSnapshot] has never been called.
  neverLoaded,

  /// A snapshot is in memory and is as fresh as the last load made it.
  loaded,

  /// A snapshot is in memory and a later load failed against it.
  ///
  /// The answers are unchanged — see [TagBindingResolver.markStale]. This says
  /// only that they are older than they should be.
  stale,
}

/// The live answer to "what does writing this member of this key require?".
///
/// Holds a snapshot of `{key -> template name}` and `{template name ->
/// template}` and answers `(key, member)` from memory. [groupFor] is shaped as
/// a [TagBindingLookup] and is handed to `AccessPolicy(tagBindings: ...)`.
///
/// **Why this is mutable, and must stay mutable.** `accessPolicyProvider`
/// (`lib/providers/access_policy.dart`) is `keepAlive` and deliberately pure —
/// it holds no connection and nothing can invalidate it — and
/// `stateManProvider` **reads** it once and holds the resulting
/// `GuardedStateMan` for the life of the panel. If a template edit rebuilt the
/// policy it would rebuild `stateManProvider` and drop every OPC UA connection
/// on the station. So the policy captures one callback on one long-lived
/// object, and a template edit replaces this object's snapshot instead of
/// replacing this object. Making this an immutable value and rebuilding the
/// policy on every edit is the change that must not happen; the
/// `identical(before, after)` test in `test/access_template_test.dart` is what
/// says so out loud (T-04-05).
///
/// **[groupFor] is synchronous by signature, and that is load-bearing.** Spec
/// §7b argued for tap-time resolution *from* the binding already being loaded
/// as `keyMappings.nodes[key]`; the 2026-08-30 ruling moved the binding to its
/// own `users`-gated table, because `key_mappings` is `configure`-classified and
/// a binding is authorization data. The synchronous requirement did not move —
/// the prompt still appears when a control is **tapped**, not when a write
/// fails — so what used to be free now has to be made true here: the bindings
/// are loaded once into this snapshot and answered from memory. An `await`
/// anywhere in this chain would pass every functional test and silently end
/// tap-time elevation.
///
/// **Deliberately no broadcast mechanism, no notifier and no listener list.**
/// The snapshot's consumers are a Riverpod provider (04-05) and the guard's
/// callback; a second notification path inside a pure-Dart value holder is how
/// two sources for one truth start.
class TagBindingResolver {
  Map<String, String> _keyToTemplate = const <String, String>{};
  Map<String, AccessTemplate> _templates = const <String, AccessTemplate>{};
  TagBindingSnapshotState _state = TagBindingSnapshotState.neverLoaded;

  /// Whether the snapshot has been loaded, and how fresh it is.
  ///
  /// See [TagBindingSnapshotState] — this is the only thing that distinguishes
  /// "nobody has told me yet" from "nothing is bound".
  TagBindingSnapshotState get state => _state;

  /// Replace both halves of the snapshot atomically and move [state] to
  /// [TagBindingSnapshotState.loaded].
  ///
  /// Both maps are **copied**: the caller is 04-03's store handing over what it
  /// just read, and a write-path decision must not move when somebody else
  /// mutates the map they passed.
  ///
  /// The two halves come from two tables — `access_template` and
  /// `access_key_binding` — and are set together on purpose. Applying one
  /// without the other would leave a window in which every binding dangles.
  void setSnapshot({
    required Map<String, String> keyToTemplate,
    required Map<String, AccessTemplate> templates,
  }) {
    _keyToTemplate = Map<String, String>.unmodifiable(keyToTemplate);
    _templates = Map<String, AccessTemplate>.unmodifiable(templates);
    _state = TagBindingSnapshotState.loaded;
  }

  /// Record that a reload failed against the snapshot already in memory.
  ///
  /// **Changes no answer.** A load that fails keeps answering from what it
  /// already has (04-05's T-04-26) — dropping the snapshot on a failed refresh
  /// would unrestrict every bound key on the plant the moment the database
  /// blinked. Marking it stale is what makes that keep-the-previous-snapshot
  /// rule real rather than cosmetic: the answers survive and a caller can still
  /// see that they are older than they should be.
  ///
  /// A no-op on a [TagBindingSnapshotState.neverLoaded] resolver — there is
  /// nothing to be stale about, and moving it to [TagBindingSnapshotState.stale]
  /// would claim a snapshot that does not exist.
  void markStale() {
    if (_state == TagBindingSnapshotState.neverLoaded) return;
    _state = TagBindingSnapshotState.stale;
  }

  /// The group required to write [member] of [key], or **null for
  /// unrestricted**. Assignable to [TagBindingLookup] with no adapter.
  ///
  /// A [member] of null asks about the whole key.
  ///
  /// **A dangling binding — a key naming a template that has no row — answers
  /// null.** This is the fail-open half again, and it is a decision rather than
  /// an oversight: from here, a key naming a template somebody deleted is
  /// indistinguishable from a key nobody ever bound, and spec §7b says the
  /// second is unrestricted. Answering "locked" instead would mean a row
  /// removed in `psql` silently freezes a conveyor, with no screen able to
  /// explain why.
  ///
  /// Plan 04-03 is what makes a dangling binding unlikely — the template delete
  /// is blocked while keys still reference it (spec §7d). This is the belt to
  /// that pair of braces, for the row somebody removes by hand, and
  /// [unboundKeys] is what surfaces it (T-04-03).
  /// Never null since the 2026-09-02 operate-floor ruling: an unbound key, a
  /// dangling binding, a never-loaded snapshot and a member no bound template
  /// mentions all answer [AccessGroup.operate]. Bindings **raise** the
  /// requirement above the floor; nothing lowers it. The plant stays usable
  /// because the anonymous session maps to the Operator role, which holds
  /// `operate` — what the floor removes is the free pass an account
  /// deliberately stripped of `operate` used to get on every unbound key.
  AccessGroup groupFor(String key, String? member) {
    final templateName = _keyToTemplate[key];
    if (templateName == null) return AccessGroup.operate;
    final template = _templates[templateName];
    if (template == null) return AccessGroup.operate;
    return template.groupFor(member) ?? AccessGroup.operate;
  }

  /// The template **name** [key] names, or null when nothing is bound.
  ///
  /// Unlike [templateForKey] this answers for a **dangling** binding too: the
  /// name is in the table, the row it names is not. From [templateForKey] the
  /// two gaps are the same null, which is right for the write path — spec §7b
  /// says both are unrestricted — and wrong for a screen, because "nobody
  /// bound this" and "somebody bound this to a template that has since gone"
  /// need different words and different fixes.
  ///
  /// So this is a **rendering** accessor and nothing else. It must not become
  /// an input to [groupFor]: answering "locked" for a name with no rules would
  /// mean a row removed in `psql` silently freezes a conveyor, with no screen
  /// able to explain why (see [groupFor]'s own note).
  String? boundTemplateName(String key) => _keyToTemplate[key];

  /// The template bound to [key], or null when nothing is bound **or** the
  /// bound name has no row. Both gaps read the same from here; see [groupFor].
  AccessTemplate? templateForKey(String key) {
    final templateName = _keyToTemplate[key];
    if (templateName == null) return null;
    return _templates[templateName];
  }

  /// Every key naming [templateName], in sorted order.
  ///
  /// The in-memory answer the key repository renders. Insertion-ordered, built
  /// from a sorted list, so iteration is stable and a rebuilt list does not
  /// reshuffle under the reader.
  ///
  /// **This is not the answer that blocks a template delete.** 04-03's store has
  /// a method of the same name that reads `access_key_binding` directly, because
  /// a delete must not decide on a snapshot that may be a second stale. This one
  /// is for rendering.
  ///
  /// Answers for a dangling name too — a key bound to a template that no longer
  /// exists is still a key naming it, and hiding it here would hide the gap.
  Set<String> keysBoundTo(String templateName) {
    final matches = <String>[
      for (final entry in _keyToTemplate.entries)
        if (entry.value == templateName) entry.key,
    ]..sort();
    return Set<String>.unmodifiable(matches);
  }

  /// Every key in [keys], **in the order given**, that has no binding or is
  /// bound to a template that does not exist.
  ///
  /// Both are gaps and both must surface: a key nobody bound is the fail-open
  /// hole spec §7b makes visible instead of closing, and a dangling binding is
  /// the same hole wearing a template name.
  ///
  /// The key universe is passed in rather than held because it still comes from
  /// `stateMan.keyMappings`, which this pure-Dart package cannot see. Note the
  /// asymmetry the 2026-08-30 ruling created: the **bindings** moved to a table
  /// and the **keys** did not, so a binding row can now outlive the key it
  /// names. Such an orphan never appears here — nobody passes that key — and
  /// showing it is 04-08's surface, not this class's to clean up.
  Iterable<String> unboundKeys(Iterable<String> keys) =>
      keys.where((key) => templateForKey(key) == null);

  /// How many keys carry a binding row, dangling ones included.
  ///
  /// Counts what the table says rather than what resolves. A summary that
  /// quietly excluded the dangling rows would hide exactly the gap the key
  /// repository exists to make visible.
  int get boundKeyCount => _keyToTemplate.length;

  /// How many templates the snapshot knows.
  int get templateCount => _templates.length;
}
