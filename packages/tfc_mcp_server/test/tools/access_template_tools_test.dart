/// The access-template tools (spec §7c).
///
/// Six tools: two reads, and four that change nothing at all and return a
/// proposal instead. The claims worth asserting here are the ones a reader of
/// the source cannot check by eye:
///
///  * `list_unbound_keys` answers with the **same** definition the key
///    repository renders — `TagBindingResolver.unboundKeys` — so a dangling
///    binding is reported and a live one is not,
///  * a station whose database predates the access tables answers "nothing is
///    gated" rather than failing,
///  * neither new file contains a write verb at all.
///
/// The database is a real in-memory [ServerDatabase] with the two access
/// tables created by hand — `ServerDatabase` mirrors only the tables the MCP
/// server reads, and these two arrive from `tfc_dart`'s migration on a real
/// station. Creating them here with the same DDL is what lets the
/// missing-table case be tested by simply *not* creating them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/services/access_template_service.dart';
import 'package:tfc_mcp_server/src/services/config_service.dart';
import 'package:tfc_mcp_server/src/tools/access_template_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';

void main() {
  late ServerDatabase db;
  late McpServer mcpServer;
  late MockMcpClient client;

  /// The key universe every test shares, in the plant's own convention so the
  /// prefix filter is exercised against the shape it exists for.
  final keyMappings = {
    'nodes': {
      'ST101.CN01': {
        'opcua_node': {'namespace': 2, 'identifier': 'CN01'}
      },
      'ST101.CN02': {
        'opcua_node': {'namespace': 2, 'identifier': 'CN02'}
      },
      'ST201.CN21': {
        'opcua_node': {'namespace': 2, 'identifier': 'CN21'}
      },
      'ST201.PU01': {
        'opcua_node': {'namespace': 2, 'identifier': 'PU01'}
      },
    },
  };

  /// Creates the two access tables with the DDL `tfc_dart`'s migration uses.
  Future<void> createAccessTables() async {
    await db.customStatement('CREATE TABLE IF NOT EXISTS access_template '
        '(name TEXT NOT NULL PRIMARY KEY, rules TEXT NOT NULL, '
        'updated_at TEXT NOT NULL)');
    await db.customStatement('CREATE TABLE IF NOT EXISTS access_key_binding '
        '(key_name TEXT NOT NULL PRIMARY KEY, template_name TEXT NOT NULL, '
        'updated_at TEXT NOT NULL)');
  }

  Future<void> seedTemplate(String name, Map<String, String> rules) async {
    await db.customStatement(
      'INSERT INTO access_template (name, rules, updated_at) VALUES '
      "('$name', '${jsonEncode(rules)}', '2026-08-30T10:00:00.000Z')",
    );
  }

  Future<void> seedBinding(String key, String template) async {
    await db.customStatement(
      'INSERT INTO access_key_binding (key_name, template_name, updated_at) '
      "VALUES ('$key', '$template', '2026-08-30T10:00:00.000Z')",
    );
  }

  /// Everything wired.
  ///
  /// [withTables] false is the station whose schema predates the access
  /// tables: the tools must answer, not throw.
  Future<void> setUpServer({bool withTables = true}) async {
    db = ServerDatabase.inMemory();
    await db.customStatement('SELECT 1');
    if (withTables) await createAccessTables();

    await db.into(db.serverFlutterPreferences).insert(
          ServerFlutterPreferencesCompanion.insert(
            key: 'key_mappings',
            value: Value(jsonEncode(keyMappings)),
            type: 'String',
          ),
        );

    mcpServer = McpServer(
      const Implementation(name: 'test-server', version: '0.1.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );

    final registry = ToolRegistry(
      mcpServer: mcpServer,
      identity:
          EnvOperatorIdentity(environmentProvider: () => {'TFC_USER': 'op1'}),
      auditLogService: AuditLogService(db),
    );

    registerAccessTemplateTools(
      registry: registry,
      service: AccessTemplateService(db),
      configService: ConfigService(db),
    );

    client = await MockMcpClient.connect(mcpServer);
  }

  Future<String> call(String tool,
      [Map<String, dynamic> args = const {}]) async {
    final result = await client.callTool(tool, args);
    return (result.content.first as TextContent).text;
  }

  Future<CallToolResult> callRaw(String tool,
          [Map<String, dynamic> args = const {}]) =>
      client.callTool(tool, args);

  tearDown(() async {
    await client.close();
    await db.close();
  });

  // -------------------------------------------------------------------------
  group('list_access_templates', () {
    test('names each template, its rules and the keys bound to it', () async {
      await setUpServer();
      await seedTemplate('conveyor',
          {'p_cfg_ManualFreq': 'device', 'p_cmd_JogFwd': 'operate'});
      await seedTemplate('recipes', {'*': 'setpoints'});
      await seedBinding('ST101.CN01', 'conveyor');
      await seedBinding('ST101.CN02', 'conveyor');

      final text = await call('list_access_templates');

      expect(text, contains('conveyor'));
      expect(text, contains('p_cfg_ManualFreq'));
      expect(text, contains('device'));
      expect(text, contains('p_cmd_JogFwd'));
      expect(text, contains('operate'));
      expect(text, contains('ST101.CN01'));
      expect(text, contains('ST101.CN02'));
      expect(text, contains('recipes'));
      expect(text, contains('setpoints'));
    });

    test(
        'a database with no access_template table answers empty, not an error',
        () async {
      await setUpServer(withTables: false);

      final result = await callRaw('list_access_templates');

      expect(result.isError, isNot(true),
          reason: 'a station whose schema predates the access tables must be '
              'told nothing is gated, not handed a driver error');
      final text = (result.content.first as TextContent).text;
      expect(text.toLowerCase(), contains('no access_template table'));
      expect(text.toLowerCase(), contains('unrestricted'));
    });

    test('tables present and empty says so in different words', () async {
      await setUpServer();

      final text = await call('list_access_templates');

      expect(text.toLowerCase(), isNot(contains('no access_template table')),
          reason: '"cannot tell you" and "there are none" are different '
              'claims and only one of them is true here');
      expect(text.toLowerCase(), contains('no access templates'));
    });
  });

  // -------------------------------------------------------------------------
  group('list_unbound_keys', () {
    test('includes a dangling binding and excludes a live one', () async {
      await setUpServer();
      await seedTemplate('conveyor', {'*': 'device'});
      await seedBinding('ST101.CN01', 'conveyor');
      await seedBinding('ST101.CN02', 'deleted-template');

      final text = await call('list_unbound_keys');

      expect(text, isNot(contains('ST101.CN01')),
          reason: 'CN01 resolves to a template that exists — it is bound');
      expect(text, contains('ST101.CN02'),
          reason: 'a binding naming a template with no row resolves to no '
              'restriction at all, which is exactly as open as unbound');
      expect(text, contains('deleted-template'),
          reason: 'the dangling name has to be reported, or the agent cannot '
              'tell the two gaps apart and will propose the wrong fix');
      expect(text, contains('ST201.CN21'));
      expect(text, contains('ST201.PU01'));
    });

    test('the prefix filter narrows the answer', () async {
      await setUpServer();

      final all = await call('list_unbound_keys');
      expect(all, contains('ST101.CN01'));
      expect(all, contains('ST201.CN21'));

      final narrowed = await call('list_unbound_keys', {'prefix': 'ST201.'});
      expect(narrowed, contains('ST201.CN21'));
      expect(narrowed, contains('ST201.PU01'));
      expect(narrowed, isNot(contains('ST101.CN01')));
      expect(narrowed, isNot(contains('ST101.CN02')));
    });

    test('limit truncates and says that it did', () async {
      await setUpServer();

      final text = await call('list_unbound_keys', {'limit': 2});

      final named = ['ST101.CN01', 'ST101.CN02', 'ST201.CN21', 'ST201.PU01']
          .where(text.contains)
          .length;
      expect(named, 2);
      expect(text, contains('4'),
          reason: 'a truncated answer that does not say how many there were '
              'lets an agent believe it has swept the plant');
    });

    test(
        'a binding naming a key that no longer exists is not reported as a key',
        () async {
      await setUpServer();
      await seedTemplate('conveyor', {'*': 'device'});
      await seedBinding('ST999.GONE', 'conveyor');

      final text = await call('list_unbound_keys');

      expect(text, isNot(contains('ST999.GONE')),
          reason: 'an orphaned binding row is not a key; reporting it would '
              'have the agent propose a binding for something that cannot be '
              'read or written');
    });

    test('every key is unbound when the tables are not there, and it says why',
        () async {
      await setUpServer(withTables: false);

      final result = await callRaw('list_unbound_keys');

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('ST101.CN01'));
      expect(text, contains('ST201.PU01'));
      expect(text.toLowerCase(), contains('no access_template table'));
    });

    test('a station with no key mappings says so rather than "none unbound"',
        () async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');
      await createAccessTables();
      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity:
            EnvOperatorIdentity(environmentProvider: () => {'TFC_USER': 'op1'}),
        auditLogService: AuditLogService(db),
      );
      registerAccessTemplateTools(
        registry: registry,
        service: AccessTemplateService(db),
        configService: ConfigService(db),
      );
      client = await MockMcpClient.connect(mcpServer);

      final text = await call('list_unbound_keys');

      expect(text.toLowerCase(), contains('no key mappings'),
          reason: '"nothing is unbound" and "there is nothing to bind" are '
              'the same sentence to an agent and different facts');
    });
  });

  // -------------------------------------------------------------------------
  group('the write-nothing property', () {
    test('neither new file contains a write verb', () {
      // T-04-50, as a standing gate rather than a one-time grep. The `users`
      // check lives at the human approval precisely because this package
      // cannot write; a write verb appearing in either file is the moment
      // that argument stops being true.
      for (final path in [
        'lib/src/services/access_template_service.dart',
        'lib/src/tools/access_template_tools.dart',
      ]) {
        final source = File(path)
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        for (final verb in [
          'INSERT',
          'UPDATE ',
          'DELETE ',
          'customStatement',
          'into(',
          'insertOnConflictUpdate',
        ]) {
          expect(source, isNot(contains(verb)),
              reason: '$path contains "$verb". Nothing in tfc_mcp_server may '
                  'write: the users gate is at the approval, in the app, and '
                  'a write here would route around it entirely.');
        }
      }
    });
  });
}
