import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase;

import 'sql_dialect.dart';

/// Read-only access to the two authorization tables, for the MCP tools.
///
/// `access_template` says which permission each struct member of a key needs;
/// `access_key_binding` says which template each key resolves through. Both
/// are written **only** by `lib/core/access_template_store.dart` in the app,
/// behind the `users` gate. This service reads them and nothing else.
///
/// ## There is no write method here, and there must never be one
///
/// Not a public one and not a private one. `tfc_mcp_server` has no session: it
/// is a separate package, deliberately free of `tfc_dart`'s Flutter and FFI
/// graph, and it cannot know who is standing at the panel. That is why spec
/// §7c's `users` gate lives at the **approval**, in the app, rather than in
/// the tool handler — the tools emit proposals and a person with `users`
/// applies them through the store. The whole of that argument rests on this
/// package being unable to write, so a write method sitting here unused is the
/// thing somebody calls later, and the gate quietly stops existing.
/// `test/tools/access_template_tools_test.dart` greps this file for write
/// verbs so the property is enforced rather than asserted.
///
/// ## Raw SQL, like [ConfigService] and for the same reason
///
/// These tables live in `tfc_dart`'s `AppDatabase` and are absent from
/// `ServerDatabase`, which mirrors only what the MCP server reads. Reading
/// them through drift's generated accessors would need the table classes in
/// this package; raw SQL through [McpDatabase.customSelect] works against both
/// databases. [adaptSql] handles the `?` -> `$N` difference on Postgres,
/// exactly as `ConfigService._sql` does — though nothing here binds a variable
/// today, and the call is kept so that the first `WHERE` added does not have
/// to remember.
///
/// ## A station whose schema predates the tables
///
/// Answering a driver error there would make "no templates" and "this station
/// cannot tell you" the same failure. Both reads catch and report
/// [AccessTemplateSnapshot.tablesPresent] instead, and the tools say which
/// case they are in. The distinction is the same one the key repository's
/// section makes on screen.
///
/// ## Nothing is cached, deliberately
///
/// [ConfigService] caches preference blobs for five minutes, and that is right
/// for page layouts. It is wrong here. An agent's whole use of this service is
/// a sweep — read the gaps, propose the bindings, wait for a person to approve
/// them, read again — and there is no path by which an approval in the app
/// could invalidate a cache held in this object: the accept goes through
/// `AccessTemplateStore`, which has never heard of `tfc_mcp_server`. A cached
/// answer would therefore disagree with the key repository for as long as the
/// TTL, at exactly the moment the agent is checking its own work. Two indexed
/// selects against small tables, at human pace, is the cheaper mistake.
///
/// (The **key universe** behind `list_unbound_keys` still comes from
/// `ConfigService`'s five-minute cache of the `key_mappings` preference. That
/// is fine and is not the same problem: keys change when somebody edits the
/// repository, not when a proposal is approved.)
class AccessTemplateService {
  /// Creates a service reading [db].
  AccessTemplateService(this._db) : _isPostgres = isPostgresDb(_db);

  final McpDatabase _db;
  final bool _isPostgres;

  String _sql(String query) => adaptSql(query, isPostgres: _isPostgres);

  /// Both tables in one value, or [AccessTemplateSnapshot.missing] when the
  /// schema does not have them.
  ///
  /// Read together on purpose: a template list applied without its bindings
  /// describes a plant in which nothing is bound, which is a different plant.
  Future<AccessTemplateSnapshot> snapshot() async {
    final templates = await _templates();
    if (templates == null) return AccessTemplateSnapshot.missing;
    final bindings = await _bindings();
    if (bindings == null) return AccessTemplateSnapshot.missing;
    return AccessTemplateSnapshot(
      templates: templates,
      bindings: bindings,
      tablesPresent: true,
    );
  }

  /// Every row of `access_template`, ordered by name, or null when the table
  /// is not there.
  Future<List<AccessTemplateRecord>?> _templates() async {
    try {
      final rows = await _db
          .customSelect(_sql(
              'SELECT name, rules, updated_at FROM access_template '
              'ORDER BY name'))
          .get();
      return [
        for (final row in rows)
          AccessTemplateRecord(
            template: AccessTemplate(
              name: row.data['name'] as String? ?? '',
              // Forgiving on purpose — see `AccessTemplate.decodeRules`. A
              // rules blob written by a newer build naming a group this one
              // does not know costs that one rule, never the list.
              rules: AccessTemplate.decodeRules(
                  row.data['rules'] as String? ?? ''),
            ),
            // Stringified rather than parsed: Postgres stores this column as
            // TEXT and drift's SQLite schema as an integer, and this value is
            // only ever shown to a reader.
            updatedAt: row.data['updated_at']?.toString(),
          ),
      ];
    } on Object {
      // The table is absent, or the read failed. Both are "cannot tell you",
      // and the caller says so rather than pretending the plant is ungated.
      return null;
    }
  }

  /// Every row of `access_key_binding` as key -> template name, or null when
  /// the table is not there.
  ///
  /// The value may name a template with no row. That is a **dangling**
  /// binding, it resolves to no restriction at all, and it is reported rather
  /// than filtered — hiding it here would hide the gap `list_unbound_keys`
  /// exists to surface.
  Future<Map<String, String>?> _bindings() async {
    try {
      final rows = await _db
          .customSelect(_sql(
              'SELECT key_name, template_name FROM access_key_binding'))
          .get();
      return {
        for (final row in rows)
          (row.data['key_name'] as String? ?? ''):
              (row.data['template_name'] as String? ?? ''),
      };
    } on Object {
      return null;
    }
  }
}

/// One `access_template` row: the value type, plus when it last changed.
class AccessTemplateRecord {
  const AccessTemplateRecord({required this.template, this.updatedAt});

  final AccessTemplate template;

  /// As stored, not parsed. See [AccessTemplateService].
  final String? updatedAt;
}

/// Both authorization tables as of one read.
class AccessTemplateSnapshot {
  const AccessTemplateSnapshot({
    required this.templates,
    required this.bindings,
    required this.tablesPresent,
  });

  /// A station whose schema predates the access tables — or one whose
  /// database would not answer. Nothing is gated, and the tools say which.
  static const AccessTemplateSnapshot missing = AccessTemplateSnapshot(
    templates: <AccessTemplateRecord>[],
    bindings: <String, String>{},
    tablesPresent: false,
  );

  final List<AccessTemplateRecord> templates;

  /// key -> template name. The name may have no row; see
  /// `AccessTemplateService._bindings`.
  final Map<String, String> bindings;

  final bool tablesPresent;

  /// The template named [name], or null.
  AccessTemplateRecord? named(String name) {
    for (final record in templates) {
      if (record.template.name == name) return record;
    }
    return null;
  }

  /// The keys naming [name], sorted. Dangling names included, for the same
  /// reason `TagBindingResolver.keysBoundTo` includes them.
  List<String> keysBoundTo(String name) {
    final keys = [
      for (final entry in bindings.entries)
        if (entry.value == name) entry.key,
    ]..sort();
    return keys;
  }

  /// The snapshot as the app's own resolver, so "unbound" has exactly **one**
  /// definition across the two front ends.
  ///
  /// This is the point of `tfc_access` being a dependency of this package
  /// rather than the rule being re-implemented here: an agent sweeping a plant
  /// and an operator reading the key repository must not be able to disagree
  /// about which keys nobody bound (T-04-46).
  TagBindingResolver get resolver => TagBindingResolver()
    ..setSnapshot(
      keyToTemplate: bindings,
      templates: {
        for (final record in templates) record.template.name: record.template,
      },
    );
}
