// Moving a proposal out of `pending` never worked against Postgres.
//
// On 2026-08-21 the `mcp_proposal` table held **1018 rows, every one
// `pending`** — nothing had ever been marked accepted, rejected or notified,
// across weeks of use. Accepting a batch applied its mappings and left every
// proposal pending, so the same batch came back on the next load. That is the
// "proposals are flaky, I keep seeing multiples" report.
//
// The cause is one line, twice:
//
//     'UPDATE mcp_proposal SET status = ? WHERE id = ?'
//
// SQLite binds with `?`; Postgres binds with `$1`, `$2`. Drift passes custom
// SQL to the engine verbatim — its own `adaptSql` helper says so — so against
// Postgres this is a syntax error, confirmed directly on the server:
//
//     ERROR:  syntax error at or near "WHERE"
//     LINE 1: UPDATE mcp_proposal SET status = ? WHERE id = ?
//
// And both call sites wrapped it in `catch (_) {}`, so the failure was
// invisible for as long as it has existed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/proposal_sql.dart';

void main() {
  group('proposalStatusUpdate', () {
    test('binds Postgres-style when the backend is Postgres', () {
      final sql = proposalStatusUpdate(isPostgres: true);
      expect(sql, contains(r'$1'));
      expect(sql, contains(r'$2'));
      expect(sql, isNot(contains('?')),
          reason: 'a single ? left behind is a syntax error on Postgres');
    });

    test('leaves SQLite binding alone', () {
      expect(proposalStatusUpdate(isPostgres: false),
          'UPDATE mcp_proposal SET status = ? WHERE id = ?');
    });

    test('numbers the placeholders in the order they appear', () {
      // status is set before id is matched; swapping them would update the
      // wrong row rather than fail loudly.
      final sql = proposalStatusUpdate(isPostgres: true);
      expect(sql.indexOf(r'$1'), lessThan(sql.indexOf(r'$2')));
      expect(sql, 'UPDATE mcp_proposal SET status = \$1 WHERE id = \$2');
    });
  });

  group('proposalPollQuery', () {
    test('binds Postgres-style so the watcher can read at all', () {
      final sql = proposalPollQuery(isPostgres: true);
      expect(sql, contains(r'$1'));
      expect(sql, contains(r'$2'));
      expect(sql, isNot(contains('?')));
    });

    test('still filters on the watermark and pending status', () {
      final sql = proposalPollQuery(isPostgres: true);
      expect(sql, contains('WHERE id > '));
      expect(sql, contains('status = '));
      expect(sql, contains('ORDER BY id ASC'));
    });
  });

  group('both writers go through it', () {
    late String state;
    late String watcher;

    setUpAll(() {
      state = File('lib/providers/proposal_state.dart').readAsStringSync();
      watcher = File('lib/providers/proposal_watcher.dart').readAsStringSync();
    });

    test('no raw statement is left in either provider', () {
      for (final source in [state, watcher]) {
        expect(source,
            isNot(contains("'UPDATE mcp_proposal SET status = ? WHERE id = ?'")),
            reason: 'the literal is a Postgres syntax error');
      }
    });

    test('each builds its statement from the dialect helper', () {
      expect(state, contains('proposalStatusUpdate('));
      expect(watcher, contains('proposalStatusUpdate('));
      expect(watcher, contains('proposalPollQuery('),
          reason: 'the poll had the same defect as the writes');
    });

    test('no raw poll query is left either', () {
      expect(watcher, isNot(contains('FROM mcp_proposal WHERE id > ?')));
    });

    test('a failed database call is reported, not swallowed', () {
      // Swallowing is why a total failure read as flakiness for weeks. Scoped
      // to the three database paths — the Beamer route lookup in
      // showProposalToast is a different, legitimate swallow.
      String body(String source, String signature) {
        final start = source.indexOf(signature);
        expect(start, greaterThan(-1), reason: 'missing $signature');
        return source.substring(start, source.indexOf('\n  }', start));
      }

      final paths = [
        body(state, 'Future<void> _updateStatus('),
        body(watcher, 'Future<void> markNotified('),
        body(watcher, 'Future<void> _poll('),
      ];
      for (final path in paths) {
        expect(path, isNot(contains('catch (_)')));
        expect(path, contains('debugPrint('));
      }
    });
  });
}
