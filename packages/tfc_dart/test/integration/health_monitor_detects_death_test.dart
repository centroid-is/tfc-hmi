// The health monitor still notices a database that has gone away.
//
// This exists because of what the monitor gave up. It used to sit inside
// `pool.withConnection` for the pool's whole life, awaiting `conn.closed` --
// a live signal that fired the instant the socket died. That is also what made
// it hold one connection per database forever, which is the thing that was
// fixed: it now runs `SELECT 1` per beat and lets go in between.
//
// The cost of letting go is that death is discovered by the next beat failing
// rather than the moment it happens. That is a real behavioural change to the
// one thing this signal exists for -- an operator on a plant workstation
// learning the HMI has lost its database -- so it is asserted here against a
// genuinely severed socket rather than argued about.
//
// The severing is done with the TCP proxy the other integration tests use, so
// what is being cut is a real connection, not a mock.

import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_connections.dart';

import 'docker_compose.dart';

void main() {
  group('health monitor (integration)', () {
    late Database database;

    setUpAll(() async {
      await startDockerCompose();
      await waitForDatabaseReady();
    });

    tearDownAll(() async {
      await stopDockerCompose();
    });

    setUp(() async {
      database = await connectToDatabase();
    });

    tearDown(() async {
      await database.dispose();
      await database.close();
      // Every test in here cuts the proxy; the next one needs it back.
      await startTimescaleDb();
    });

    test('reports false once the database stops answering', () async {
      // Budget: a beat every [kHealthBeatInterval], so a death just after a
      // good beat is noticed on the next one. Allow a couple of beats plus the
      // query timeout for the failing round trip, and stay well inside the
      // 30 second `healthTimeout` -- if this only passed by waiting out that
      // timeout it would be proving the fallback, not the monitor.
      final budget = kHealthBeatInterval * 2 + const Duration(seconds: 8);
      expect(budget, lessThan(const Duration(seconds: 30)),
          reason: 'the monitor must beat the health timeout to its own '
              'conclusion, otherwise this test cannot tell the two apart');

      final wentUnhealthy = database.connectionState
          .firstWhere((healthy) => !healthy)
          .timeout(budget);

      // Sever it. The proxy destroys the live sockets and refuses new ones,
      // which is what a database going away looks like from in here.
      await stopTimescaleDb();

      await expectLater(wentUnhealthy, completion(isFalse),
          reason: 'the monitor let go of its connection between beats, so it '
              'no longer has conn.closed to tell it the socket died -- the '
              'failing beat has to be what reports it');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('reports true again once the database comes back', () async {
      // Recovery matters as much as detection: a monitor that latched
      // unhealthy would leave the HMI showing a dead database forever, which
      // is the failure mode operators actually complain about.
      await stopTimescaleDb();
      await database.connectionState
          .firstWhere((healthy) => !healthy)
          .timeout(kHealthBeatInterval * 2 + const Duration(seconds: 8));

      final recovered = database.connectionState
          .firstWhere((healthy) => healthy)
          .timeout(kHealthBeatInterval * 2 + const Duration(seconds: 8));

      await startTimescaleDb();

      await expectLater(recovered, completion(isTrue),
          reason: 'the pool hands out a fresh connection on the next beat, '
              'which is how the monitor is supposed to recover');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
