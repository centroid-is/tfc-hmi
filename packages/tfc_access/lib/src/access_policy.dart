import 'package:meta/meta.dart';

import 'access_group.dart';

/// The write surfaces the policy can be asked about.
///
/// The wire names are fixed strings rather than [Enum.name] because spec §2's
/// `surface` column is stored data — it lands in every audit row and is read
/// back by the trail. Renaming a value here must not silently rewrite what a
/// year of rows mean, so the mapping is written down.
///
/// The column and this enum are **not the same set**. §2 also carries
/// `'auth'`, which records a sign-in or sign-out. That is an event, not a
/// write somebody could be authorized for, so it is deliberately absent here
/// and [byWireName] answers null for it.
enum AccessSurface {
  /// A process tag written through `StateMan`.
  tag('tag'),

  /// A configuration key written through `PreferencesApi`.
  pref('pref'),

  /// A navigation destination.
  route('route');

  const AccessSurface(this.wireName);

  /// The string written into an audit row's `surface` column.
  final String wireName;

  /// The surface whose [wireName] equals [wireName], or null when unrecognised.
  ///
  /// The match is exact — no case folding, no trimming. Callers pass a
  /// constant, and a value that has been mangled in transit is exactly the
  /// case that must not resolve to a real surface.
  static AccessSurface? byWireName(String wireName) {
    for (final surface in values) {
      if (surface.wireName == wireName) return surface;
    }
    return null;
  }
}

/// The seam Phase 4's access templates plug into.
///
/// Answers the group required to write [member] of tag [key], or null when
/// nothing has been bound. **Null means unrestricted** — this is the
/// fail-open half of the policy, and spec §7b is why: binding is explicit per
/// key, with no inference from asset type and no pattern matching on key
/// names, so a key nobody has bound has no group by construction rather than
/// by omission. A [member] of null asks about the whole key.
///
/// Phase 3 ships no implementation. The constructor default answers null for
/// everything, which is the shipped behaviour until templates land.
typedef TagBindingLookup = AccessGroup? Function(String key, String? member);

/// How a [kPrefAccessRules] entry matches a preference key.
///
/// **The declaration order of these values is the precedence order** —
/// [AccessPolicy.groupForPref] walks `PrefRuleKind.values` in order and takes
/// the first match, so `exact` beats `prefix` beats `suffix`, and anything
/// unmatched falls to `administer`.
///
/// Prefix outranks suffix deliberately. The only suffix rule (`.recipes` →
/// `setpoints`) is the most permissive rule in the table, while the prefix
/// rules (`database`, `network`, `ip_`, `hostname`, `mcp.`, `llm.` →
/// `administer`) are the most restrictive. Were suffix to win, a future key
/// named `network.recipes` or `llm.recipes` would resolve to `setpoints` and
/// hand a restricted surface to a Shift Leader. No key in the tree collides
/// today, which is precisely why this is fixed by ordering rather than left to
/// the no-double-match test — that test passes right up until somebody adds
/// the key.
///
/// Reordering these values changes who may write what.
/// `test/access_policy_test.dart` asserts the order so that it fails the build
/// rather than shipping quietly.
enum PrefRuleKind { exact, prefix, suffix }

/// A single classification rule for a preference key.
typedef PrefAccessRule = ({PrefRuleKind kind, String match, AccessGroup group});

/// The declared group for each preference key, in precedence order.
///
/// Precedence is **exact, then prefix, then suffix, then the `administer`
/// default** — see [PrefRuleKind], which carries that order. The list is
/// grouped the same way for readability, but the list order is not what
/// decides: [AccessPolicy.groupForPref] iterates by kind, so inserting a rule
/// in the wrong block cannot change precedence.
const List<PrefAccessRule> kPrefAccessRules = <PrefAccessRule>[
  // Task 2 of this plan fills this list, from key expressions resolved to
  // their literals. Empty here on purpose: with no rules every key falls to
  // the `administer` default, which is the fail-closed behaviour this file
  // ships and the thing Task 1's tests pin.
];

/// The single place that answers "what does writing *this* require?".
///
/// Both guards (plans 03-04 and 03-05) consult one instance of this class. If
/// the answer lived in the guards there would be two copies of the fail-open /
/// fail-closed rule, and the interesting failure of this phase is the silent
/// one: a wrong answer looks identical to a right one from every screen.
///
/// **The asymmetry is the point.** [groupForTag] returns `AccessGroup?` and
/// [groupForPref] returns a non-nullable `AccessGroup`. Tags fail open,
/// config keys fail closed, and the type system carries that so a later edit
/// cannot quietly collapse it into one default.
@immutable
class AccessPolicy {
  /// [tagBindings] is Phase 4's access-template lookup; the default answers
  /// null for everything, which ships gating no tag at all.
  ///
  /// [routes] mirrors the app package's `kRaisedRoutes`. It is passed in
  /// rather than imported: `tfc_access` is pure Dart and must not reach into
  /// the Flutter app for a route table. Plan 03-06 supplies it.
  const AccessPolicy({
    TagBindingLookup? tagBindings,
    Map<String, AccessGroup> routes = const <String, AccessGroup>{},
  })  : _tagBindings = tagBindings,
        _routes = routes;

  final TagBindingLookup? _tagBindings;
  final Map<String, AccessGroup> _routes;

  /// The group required to write [member] of tag [key], or **null for
  /// unrestricted**.
  ///
  /// Null is the shipped answer for every key until Phase 4 binds access
  /// templates (spec §7b). This is the fail-open half: a strict default would
  /// lock every control on the plant on the day the guards merge, and a
  /// wrongly-open setpoint is a nuisance where a wrongly-open config write is
  /// a broken plant.
  AccessGroup? groupForTag(String key, {String? member}) {
    final lookup = _tagBindings;
    if (lookup == null) return null;
    try {
      return lookup(key, member);
    } on Object {
      // Deliberately swallowed, and deliberately not logged — this package has
      // no logger and must not grow one.
      //
      // The fail-open half must not become fail-closed because a template
      // table is unreadable. This runs on the write path of every jog, start
      // and alarm ack; a guard that threw here because Postgres was down would
      // take the plant's controls down with it. An unreadable binding source
      // is indistinguishable from an unbound key, and both mean unrestricted.
      return null;
    }
  }

  /// The group required to write preference [key]. **Never null.**
  ///
  /// Walks [kPrefAccessRules] by [PrefRuleKind] in precedence order — exact,
  /// then prefix, then suffix — and answers [AccessGroup.administer] when
  /// nothing matches. Matching is case-sensitive and exact; `Page_editor_data`
  /// and `xpage_editor_data` are not `page_editor_data`.
  ///
  /// There is no "unrestricted" answer here by design. §7's config default is
  /// closed, and a nullable return would let a future edit reopen it silently.
  AccessGroup groupForPref(String key) {
    for (final kind in PrefRuleKind.values) {
      for (final rule in kPrefAccessRules) {
        if (rule.kind != kind) continue;
        final matched = switch (kind) {
          PrefRuleKind.exact => key == rule.match,
          PrefRuleKind.prefix => key.startsWith(rule.match),
          PrefRuleKind.suffix => key.endsWith(rule.match),
        };
        if (matched) return rule.group;
      }
    }
    return AccessGroup.administer;
  }

  /// The group required to reach [path], defaulting to [AccessGroup.operate].
  ///
  /// Matches the Phase 2 registry default: a route nobody raised is an
  /// operator route.
  AccessGroup groupForRoute(String? path) {
    if (path == null) return AccessGroup.operate;
    return _routes[path] ?? AccessGroup.operate;
  }

  /// The group required to write [key] on [surface], where [surface] is a wire
  /// name from spec §2's `surface` column.
  ///
  /// **This is the entry point the decorators call, not a convenience
  /// wrapper.** Plans 03-04 and 03-05 pass the same `surface` string they
  /// write into the audit row's `surface` column, so the group that was
  /// checked and the surface that was recorded cannot disagree. A reader who
  /// "simplifies" the decorators to call [groupForTag] / [groupForPref]
  /// directly deletes the unmapped branch's only caller and with it the one
  /// test that proves an unknown surface fails closed.
  ///
  /// Returns null only for `'tag'`, where null means unrestricted. `'pref'`
  /// and `'route'` always answer a group, and so does the unmapped branch.
  AccessGroup? groupForWireSurface(String surface, String key,
      {String? member}) {
    return switch (AccessSurface.byWireName(surface)) {
      AccessSurface.tag => groupForTag(key, member: member),
      AccessSurface.pref => groupForPref(key),
      AccessSurface.route => groupForRoute(key),
      // A surface string this file does not know is either a new write surface
      // nobody classified or a typo. Both should land on the strictest answer
      // rather than the most permissive, so an unclassified surface is a
      // denial waiting to be noticed rather than a hole nobody sees.
      //
      // Deliberately not a throw: the guards call this on the write path, and
      // an ArgumentError there would be an outage rather than a denial.
      null => AccessGroup.administer,
    };
  }
}
