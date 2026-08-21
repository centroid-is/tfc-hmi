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
/// Not the ceiling on the pool itself: [poolConnectionCount] adds the health
/// monitor's standing connection on top of whatever [resolvePoolSize] allows,
/// so the widest pool this code will ever open is one more than this --
/// [kMaxPoolConnections] + [kHealthMonitorConnections]. The extra one is the
/// point of that function and is deliberately outside the cap; capping the
/// total instead would silently take a connection away from the work.
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

/// Connections the pool keeps for itself, on top of the work budget.
///
/// The pool health monitor sits inside `pool.withConnection` for as long as
/// the pool is open -- awaiting the connection's `closed` future is how it
/// notices a socket dying. It hands that connection back only on the way out,
/// so for sizing purposes the pool never gets it.
const int kHealthMonitorConnections = 1;

/// Connections to open the pool with: the work budget plus the monitor's.
///
/// Sizing the pool to the work alone leaves nothing to do the work with. A
/// pool of exactly one gave the monitor the only connection there was, and the
/// first query -- drift asking Postgres its version while opening -- waited
/// out the pool lock and threw `Failed to acquire pool lock`, so the database
/// never opened at all.
int poolConnectionCount(int? configured) =>
    resolvePoolSize(configured) + kHealthMonitorConnections;

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

/// Floor for the wait in [monitorStopTimeout], and the value to use when the
/// pool's connect timeout is unknown.
///
/// Every *wait* inside the monitor is raced against its stop signal, so a
/// monitor that already holds its connection lets go in milliseconds.
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
