/// The fixed permission groups.
///
/// Groups are defined in code and referenced by assets and routes; roles are
/// customer data that map onto them. That split is the whole point of the
/// model: a customer can invent a role without a schema change, but cannot
/// invent a capability the code does not already understand.
///
/// `users` is deliberately separate from `configure`. Fold them together and
/// anyone who can edit a page can grant themselves everything.
///
/// **Exactly these seven.** An eighth value is a decision, not an edit — it
/// changes what every role in the field can be granted, and every deployed
/// station's stored role rows are written in terms of these names.
/// `test/access_group_test.dart` asserts the count and order exactly so that
/// adding one fails the build rather than shipping quietly.
enum AccessGroup {
  /// Start/stop/jog, gates, alarm acknowledge.
  operate,

  /// Targets, limits, recipes.
  setpoints,

  /// Drive parameters, calibration, scaling.
  device,

  /// Forced I/O and overrides.
  force,

  /// Page editor, alarm rules, key mappings.
  configure,

  /// Server config, database, network, updates.
  administer,

  /// Managing roles and users.
  users;

  /// The value whose [name] equals [name], or null when unrecognised.
  ///
  /// Returns null rather than throwing: a station running a newer build may
  /// have written a group name this one has never heard of into
  /// `AppRole.groups`, and the right answer to that is "not granted", not a
  /// crash on read.
  ///
  /// The match is exact — no case folding, no trimming. These names are stored
  /// data, written by `AccessRole.encodeGroups`, not user input.
  static AccessGroup? byName(String name) {
    for (final group in values) {
      if (group.name == name) return group;
    }
    return null;
  }
}
