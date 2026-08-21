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

/// Ceiling on a single process's pool, so a mistyped config cannot exhaust the
/// server on its own.
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
