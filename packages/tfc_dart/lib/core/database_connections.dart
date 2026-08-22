/// Connection lifetime around bringing the database up, and a census of who is
/// holding what.
///
/// On 2026-08-21 Postgres refused every write with `53300: sorry, too many
/// clients already`. Saving a page failed; so did opening a psql session,
/// because even the superuser reserved slots were gone. Three separate
/// defects combined:
///
///   1. Every process asked for a pool of **20** connections. The postgres
///      package's own default is 1, and one is what a UI client actually
///      needs. Five processes at 20 exhaust a default server between them.
///   2. `connectWithRetry` built a database, and if opening it threw, looped
///      without disposing what it built -- every two seconds, forever. Each
///      abandoned pool keeps a health-monitor connection open by design, so a
///      failed attempt costs a server slot permanently.
///   3. `probe` raced `Connection.open` against a timeout. The open keeps
///      running after the timeout gives up, handing back a live connection
///      nobody closes.
///
/// Together they are self-reinforcing: the tighter the pool, the slower the
/// opens, the more orphans get made.
library;

import 'dart:async';

// -- pool sizing ------------------------------------------------------------

/// Ceiling on a single process's *work* budget, so a mistyped config cannot
/// exhaust the server on its own.
///
/// The ceiling on the pool, full stop. [poolConnectionCount] used to add the
/// health monitor's standing connection on top, making the widest pool one
/// more than this; the monitor no longer holds a connection, so the work
/// budget and the pool size are now the same number.
const int kMaxPoolConnections = 16;

/// Connections a process should pool, given what it asked for.
///
/// Unconfigured means one -- the postgres package's default, and all a UI
/// client needs for occasional reads and preference writes. A collector sets
/// this explicitly: roughly one per upstream server it drains.
int resolvePoolSize(int? configured) {
  if (configured == null || configured < 1) return 1;
  return configured > kMaxPoolConnections ? kMaxPoolConnections : configured;
}

/// Connections to open the pool with.
///
/// This used to be the work budget **plus one**, and the `+1` is now gone.
/// It existed because the health monitor sat inside `pool.withConnection` for
/// the pool's whole life, awaiting the connection's `closed` future: the slot
/// was gone for good, so the budget had to be raised to compensate. A pool of
/// exactly one could not even open -- the monitor took the only connection and
/// drift's opening query waited out the pool lock and threw `Failed to acquire
/// pool lock`.
///
/// The monitor now borrows for the length of a `SELECT 1` and lets go, so
/// there is nothing to compensate for. Dropping the spare is not a tidy-up: it
/// is where the connection saving actually comes from. Releasing the borrow
/// alone changes nothing a server can see, because a pool keeps its sockets
/// open between borrows -- measured against a real Postgres, a database still
/// sat on two. Sizing the pool back down is what takes it to one, and on the
/// collector's eight databases that is 16 connections down to 8.
///
/// What it costs: on a pool sized exactly to its workload the beat and the
/// work now take turns. A `SELECT 1` every [kHealthBeatInterval] is a
/// sub-millisecond wait for whichever arrives second, against a permanently
/// occupied slot before.
int poolConnectionCount(int? configured) => resolvePoolSize(configured);

/// Environment variable a process uses to raise its pool above the default.
///
/// Named for the field it fills, and for the other non-libpq setting beside it
/// (`CENTROID_DB_DEBUG`); the `CENTROID_PG*` variables all mirror a libpq one,
/// and there is no libpq variable for this.
const String kMaxPoolConnectionsEnv = 'CENTROID_DB_MAX_POOL_CONNECTIONS';

/// The work budget [env] asks for, or null for the default of one.
///
/// The collector is the one process that genuinely drains several sources at
/// once, and it is configured entirely from the environment. Without this
/// there was no way to reach `DatabaseConfig.maxPoolConnections` at all: the
/// field documented an escape hatch that nothing could open.
///
/// A value that is not a number is treated as absent rather than fatal. A
/// typo in a collector's environment should cost it the raise, not its start;
/// [resolvePoolSize] caps whatever does parse.
int? maxPoolConnectionsFromEnv(Map<String, String> env) {
  final raw = env[kMaxPoolConnectionsEnv];
  if (raw == null) return null;
  return int.tryParse(raw.trim());
}

// -- shutdown ---------------------------------------------------------------

/// Longest either half of a pool close may take before it is given up on.
const Duration kPoolCloseTimeout = Duration(seconds: 5);

/// How often the health monitor proves the database is still reachable.
///
/// Sized against `Database.healthTimeout`, which is 30 seconds: a beat every
/// 10 gives three per window, so a single slow or dropped beat cannot make a
/// healthy database look dead, and two consecutive failures still report
/// within the window.
///
/// It also sets the worst case for *noticing* a death. The monitor used to sit
/// inside `withConnection` awaiting `conn.closed`, which fired the moment the
/// socket died; now that it lets go between beats, a database that dies just
/// after a good beat is not noticed until the next one. Ten seconds is the
/// price of not holding a connection per database, and it is affordable
/// precisely because a released beat costs a `SELECT 1` rather than a slot.
const Duration kHealthBeatInterval = Duration(seconds: 10);

/// Floor for the wait in [monitorStopTimeout], and the value to use when the
/// pool's connect timeout is unknown.
///
/// Every *wait* inside the monitor is raced against its stop signal. Since the
/// monitor now lets go between beats, the only borrow a close can land on is
/// the one inside a single `SELECT 1`, so it lets go in milliseconds.
const Duration kMonitorStopTimeout = Duration(seconds: 2);

/// Hard ceiling on the same wait. A close must not hang, however patiently
/// configured the pool is.
const Duration kMonitorStopCeiling = Duration(seconds: 15);

/// Slack on top of [connectTimeout], for the callback to run and the borrow to
/// be handed back once the acquire lands.
const Duration kMonitorStopSlack = Duration(seconds: 1);

/// Longest to wait for the health monitor to hand its connection back, given
/// how long the pool may take to hand it one.
///
/// Not a flat constant, because the thing being waited for is not flat. The
/// monitor races its waits against the stop signal, but it cannot race
/// `pool.withConnection`'s *acquire*: the stop flag is only read inside the
/// callback, which does not run until the connection is open. So a monitor
/// asked to stop mid-acquire takes as long as that acquire takes, and the
/// longest that can legitimately be is the pool's [connectTimeout].
///
/// Waiting less than that is what leaked. The close gave up after a flat two
/// seconds, swallowed the timeout, and force-closed the pool with an acquire
/// still in flight; the socket then landed untracked by a pool that was
/// already gone, and nothing ever closed it. On a fast machine the acquire
/// always won that race, which is why it only ever showed up on CI.
Duration monitorStopTimeout(Duration connectTimeout) {
  final wanted = connectTimeout + kMonitorStopSlack;
  if (wanted < kMonitorStopTimeout) return kMonitorStopTimeout;
  if (wanted > kMonitorStopCeiling) return kMonitorStopCeiling;
  return wanted;
}

/// Releases a pool: politely if it can, forcibly if it must.
///
/// [close] is `pg.Pool.close`. The graceful call is tried first because of what
/// it does on the wire -- returning a connection closes it with a Terminate,
/// and the backend exits immediately. Forcing destroys the socket instead and
/// leaves the server to work out that the peer is gone, which it does in its
/// own time. That difference does not show up on a quiet machine, where both
/// look instant, but it is the whole point on a loaded one: this code exists
/// because a Postgres ran out of connection slots, and a slot released only
/// when the server notices a dead socket is a slot still taken.
///
/// The graceful call only works because the caller stops the health monitor
/// first: it waits for every borrowed connection to come back, and the
/// monitor's is borrowed for the pool's whole life. If anything is still
/// holding one, the graceful close cannot finish, the timeout fires, and the
/// forced call guarantees the pool goes away regardless.
///
/// Bounded and swallowing throughout, because `connectWithRetry` calls this on
/// every attempt it throws away. A close that hung there would stall the retry
/// loop against an already-unreachable database; a close that threw would
/// leave the same orphaned pool the close exists to prevent.
Future<void> releasePool(
  Future<void> Function({bool force}) close, {
  Duration timeout = kPoolCloseTimeout,
  void Function(Object error)? onError,
}) async {
  try {
    await close(force: false).timeout(timeout);
    return;
  } catch (error) {
    onError?.call(error);
  }
  // Forced only when the polite close could not finish.
  //
  // This briefly forced unconditionally, on the theory that a graceful close
  // reporting success was not the same claim as every socket being shut. The
  // four backends that theory was aimed at turned out to come from somewhere
  // else entirely -- `_startup` timing out with the socket already connected
  // and never closing it, fixed in the postgres fork -- and forcing on top
  // never made any difference to them. It is removed rather than left in as
  // insurance, because an unconditional force undoes the reason the polite
  // call is made first: a returned connection goes with a Terminate and the
  // backend exits on the spot.
  try {
    await close(force: true).timeout(timeout);
  } catch (error) {
    onError?.call(error);
  }
}

// -- retry ------------------------------------------------------------------

/// Longest wait between connection attempts.
const Duration kMaxConnectBackoff = Duration(seconds: 30);

/// Wait before attempt [attempt] (1-based), growing then flattening.
///
/// The old loop waited a flat two seconds and never gave up, so one
/// unreachable database produced eighteen hundred connection attempts an hour.
Duration backoffForAttempt(int attempt) {
  if (attempt < 1) return Duration.zero;
  final seconds = 1 << (attempt - 1 > 5 ? 5 : attempt - 1);
  final capped =
      seconds > kMaxConnectBackoff.inSeconds ? kMaxConnectBackoff.inSeconds : seconds;
  return Duration(seconds: capped);
}

/// Builds and opens a database, retrying until it succeeds.
///
/// The point of this function is the `catch`: anything [build] produced is
/// handed to [dispose] before the next attempt. Skipping that is what turned a
/// busy database into an unreachable one, because the abandoned pool went on
/// holding a connection.
///
/// [dispose] failing is not fatal -- a half-open database can fail to close,
/// and giving up there would strand the caller with no database at all.
Future<T> retryUntilOpen<T>({
  required Future<void> Function() probe,
  required Future<T> Function() build,
  required Future<void> Function(T) open,
  required Future<void> Function(T) dispose,
  required Duration Function(int attempt) delay,
  required Future<void> Function(Duration) sleep,
  void Function(Object error, int attempt)? onError,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      await probe();
      final built = await build();
      try {
        await open(built);
      } catch (_) {
        try {
          await dispose(built);
        } catch (_) {
          // Nothing useful to do: we are already on the failure path, and the
          // caller still needs us to keep trying.
        }
        rethrow;
      }
      return built;
    } catch (error) {
      onError?.call(error, attempt);
      await sleep(delay(attempt));
    }
  }
}

// -- probe ------------------------------------------------------------------

/// Waits [timeout] for [pending], and closes whatever it eventually yields.
///
/// `Connection.open` does not stop when we stop waiting on it. Without the
/// close scheduled up front, a server too slow to answer inside [timeout]
/// still opens the connection, and it holds a slot until the backend notices.
/// That is how a slow database becomes an exhausted one.
Future<void> openThenClose<T>(
  Future<T> pending,
  Future<void> Function(T) close, {
  required Duration timeout,
}) async {
  unawaited(pending.then((value) async {
    try {
      await close(value);
    } catch (_) {
      // A close that fails leaves the server to reap it; there is no caller
      // left to tell.
    }
  }).catchError((Object _) {
    // The open failed, so there is nothing to close. The error is surfaced
    // below, on the future the caller is actually awaiting.
  }));
  await pending.timeout(timeout);
}

// -- census -----------------------------------------------------------------

/// One client's share of the server's connections.
class PeerConnections {
  final String peer;
  final String app;
  final int count;
  const PeerConnections(
      {required this.peer, required this.app, required this.count});
}

/// Who is holding connections, and how close the server is to full.
class ConnectionCensus {
  final int total;
  final int max;
  final List<PeerConnections> peers;
  const ConnectionCensus(
      {required this.total, required this.max, required this.peers});

  /// Holders biggest first. During the incident the answer was a single row --
  /// the backend on 75 of 100 -- and it was only obvious once the list was
  /// ordered by share rather than by address.
  List<PeerConnections> get peersByShare =>
      [...peers]..sort((a, b) => b.count.compareTo(a.count));

  int get percentUsed => max > 0 ? (total * 100 / max).round() : 0;
}

/// Fraction of the server's connections in use, above which the census is
/// worth shouting about.
const double kCensusAlarmFraction = 0.8;

bool censusIsAlarming(ConnectionCensus c) =>
    c.max > 0 && c.total >= c.max * kCensusAlarmFraction;

/// Counts connections per client, so the answer names the process that is
/// leaking rather than only reporting that something is.
///
/// The totals come from scalar subqueries so they repeat on every row; that is
/// the price of getting the whole picture from one round trip, which matters
/// when connections are the scarce thing.
const String connectionCensusSql = '''
SELECT coalesce(host(client_addr), 'local') AS peer,
       coalesce(nullif(application_name, ''), '-') AS app,
       count(*)::int AS n,
       (SELECT count(*)::int FROM pg_stat_activity) AS total,
       current_setting('max_connections')::int AS max_conn
FROM pg_stat_activity
GROUP BY 1, 2
ORDER BY 3 DESC
''';

int _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

/// Reads the rows [connectionCensusSql] returns.
///
/// No rows would mean the server counted not even the connection asking, so
/// the totals are reported as zero rather than guessed at -- a census that
/// invents numbers is worse than one that admits it has none.
ConnectionCensus parseConnectionCensus(Iterable<Map<String, Object?>> rows) {
  final peers = <PeerConnections>[];
  var total = 0;
  var max = 0;
  for (final row in rows) {
    total = _asInt(row['total']);
    max = _asInt(row['max_conn']);
    peers.add(PeerConnections(
      peer: (row['peer'] as String?) ?? 'local',
      app: (row['app'] as String?) ?? '-',
      count: _asInt(row['n']),
    ));
  }
  return ConnectionCensus(total: total, max: max, peers: peers);
}
