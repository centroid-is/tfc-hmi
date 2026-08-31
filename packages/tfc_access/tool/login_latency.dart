/// Sign-in latency at the shipped constants, run by hand on panel hardware.
///
/// ## What this is for
///
/// `tool/argon2_bench.dart` swept parameters and chose six of them. This
/// measures the code that shipped, at those six, on the machine an operator
/// signs in on. The two are deliberately different measurements: the sweep
/// built its own derivation so it could vary knobs the public API does not
/// expose, and a harness that re-derives the parameters is measuring the
/// harness. Everything here goes through [PasswordHasher.hash] and
/// [PasswordHasher.verify] — the same two calls the login path makes — so if
/// somebody changes a constant, this number moves with it.
///
/// ## The three shapes, and why three
///
/// A login is not one cost. It is three, and reporting one figure for all of
/// them either flatters the change or slanders it:
///
///  1. **steady state** — verify against an `argon2id` row. This is what
///     signing in costs from the second login onward, forever, for everybody.
///     It is the only one of the three that belongs in a sentence about how
///     fast the login is.
///  2. **migrating (one-time)** — verify against a `pbkdf2-sha256` row, then
///     hash the same password again to write back. This is the transparent
///     migration: PBKDF2 at the count in the row plus one Argon2id derivation.
///     It happens **once per user, ever**, on their first sign-in after the
///     change. It is the slowest row here and it is allowed to be. It is not
///     the sign-in latency and must not be quoted as one, nor used to argue
///     the parameters down.
///  3. **second login** — verify against the row shape 2 just produced. This
///     is how "one-time" is shown to be one-time rather than asserted: it
///     should land on top of shape 1.
///
/// ## What it cannot tell you
///
/// Wall time cannot see whether the screen froze. So every shape also arms a
/// 16 ms ticker and reports how badly it was starved — the same jank proxy
/// `argon2_bench.dart` uses, and for the same reason. But that proxy runs in a
/// bare Dart isolate with nothing else to do, and the thing actually at risk is
/// a panel with a live process behind the login. **A person watching that
/// screen while somebody signs in is the only confirmation of it**, and this
/// tool does not replace one. The rig can be screenshotted; it cannot be typed
/// at.
///
/// This also measures the derivation and nothing around it: no database round
/// trip, no session write, no frame. An operator's wait is this number plus
/// those.
///
/// ## Running it
///
///     dart run tool/login_latency.dart            # 5 runs per shape
///     dart run tool/login_latency.dart --runs=3
///     dart run tool/login_latency.dart --help
///
/// It is not a test. Nothing here asserts, and CI never runs it. It does refuse
/// to print a table it cannot stand behind: if a verification that must succeed
/// returns false, or if the parameters in view are not the production ones, it
/// writes to stderr and exits non-zero rather than reporting a fast number for
/// the wrong work.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tfc_access/tfc_access.dart';

/// A fixed password: the point is to compare shapes, so nothing else may vary
/// between runs. Length and content are irrelevant to the cost — both
/// algorithms here are fixed-cost in the input.
const String benchPassword = 'correct-horse-battery-staple-07';

/// Salt width in bytes, matching [PasswordHasher.saltBytes], so the legacy row
/// built below is the shape a real one has.
const int saltBytes = 16;

/// Runs per shape when `--runs=` is not given.
const int defaultRuns = 5;

/// The exit code for a bad command line, per `sysexits.h` `EX_USAGE`.
const int exitUsage = 64;

/// The exit code used when a measurement cannot be trusted.
const int exitUnsound = 70;

/// Build the `pbkdf2-sha256` row a user carried over from before the change
/// has in the database.
///
/// Assembled here from [Pbkdf2Kdf.deriveKey] and the plain [PasswordHash]
/// constructor rather than from a library helper, because there deliberately is
/// no helper that *writes* the retired algorithm — plan 07-15's tests build
/// their fixture the same way, for the same reason. A function that produces
/// PBKDF2 password rows is one import away from a caller that produces them for
/// real, and the whole point of the migration is that nothing does.
///
/// The salt is deterministic so that two runs of this tool measure the same
/// work; the production path takes a random one from [PasswordHasher.hash].
Future<PasswordHash> legacyPbkdf2Row(String password) async {
  final salt = List<int>.generate(saltBytes, (i) => (i * 37 + 11) & 0xFF);
  final key = await Pbkdf2Kdf.deriveKey(
    passphrase: password,
    salt: salt,
    // The count a row written before the change carries. It travels with the
    // hash, and verification uses the row's count rather than this one — which
    // is the property that keeps existing users signing in.
    iterations: Pbkdf2Kdf.defaultIterations,
    bits: 256,
  );
  final bytes = await key.extractBytes();
  return PasswordHash(
    hashB64: base64Encode(bytes),
    saltB64: base64Encode(salt),
    iterations: Pbkdf2Kdf.defaultIterations,
  );
}

/// What one shape measured.
class Measurement {
  const Measurement({
    required this.label,
    required this.note,
    required this.runs,
    required this.medianMs,
    required this.minMs,
    required this.missedIntervals,
    required this.worstIntervalMs,
    required this.droppedFrames,
  });

  /// How the row is named in the report.
  final String label;

  /// The one-line caveat printed under the table. Empty for a shape that needs
  /// none.
  final String note;

  /// Every run's wall time in milliseconds, in the order they were taken.
  /// Nothing is discarded — an outlier is information, not noise.
  final List<double> runs;

  /// Median wall time across [runs].
  final double medianMs;

  /// Fastest of [runs].
  final double minMs;

  /// Median across runs of the number of 16 ms ticker intervals longer than
  /// 32 ms — one missed frame.
  final double missedIntervals;

  /// The single worst gap between ticker fires, across every run.
  final double worstIntervalMs;

  /// Median across runs of how many 16 ms frames the ticker's gaps account for
  /// in total. It separates one long stall from many short ones, where the
  /// interval count alone cannot.
  final double droppedFrames;
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final n = sorted.length;
  if (n.isOdd) {
    return sorted[n ~/ 2];
  }
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Measure [body] [runs] times, timing it and watching a 16 ms ticker across
/// it.
///
/// The ticker is armed before the work starts and cancelled before the run is
/// scored, and the gap still open when the work finishes is scored explicitly:
/// a body that never yields leaves a stall the ticker has had no chance to
/// report, and dropping it would make the worst case look like the best one.
Future<Measurement> measure({
  required String label,
  required String note,
  required int runs,
  required Future<void> Function() body,
}) async {
  final wallMs = <double>[];
  final missed = <double>[];
  final dropped = <double>[];
  var worstMs = 0.0;

  for (var run = 0; run < runs; run++) {
    final ticker = Stopwatch()..start();
    var previousUs = ticker.elapsedMicroseconds;
    var runMissed = 0;
    var runDropped = 0.0;
    final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final nowUs = ticker.elapsedMicroseconds;
      final gapMs = (nowUs - previousUs) / 1000.0;
      previousUs = nowUs;
      if (gapMs > 32.0) {
        runMissed++;
      }
      if (gapMs > worstMs) {
        worstMs = gapMs;
      }
      final frames = (gapMs / 16.0) - 1.0;
      if (frames > 0) {
        runDropped += frames;
      }
    });

    final watch = Stopwatch()..start();
    await body();
    watch.stop();

    final tailMs = (ticker.elapsedMicroseconds - previousUs) / 1000.0;
    timer.cancel();
    if (tailMs > 32.0) {
      runMissed++;
    }
    if (tailMs > worstMs) {
      worstMs = tailMs;
    }
    final tailFrames = (tailMs / 16.0) - 1.0;
    if (tailFrames > 0) {
      runDropped += tailFrames;
    }

    wallMs.add(watch.elapsedMicroseconds / 1000.0);
    missed.add(runMissed.toDouble());
    dropped.add(runDropped);
  }

  return Measurement(
    label: label,
    note: note,
    runs: wallMs,
    medianMs: _median(wallMs),
    minMs: wallMs.reduce(min),
    missedIntervals: _median(missed),
    worstIntervalMs: worstMs,
    droppedFrames: _median(dropped),
  );
}

String _pad(String value, int width) => value.padRight(width);
String _padLeft(String value, int width) => value.padLeft(width);
String _ms(double value) => value.toStringAsFixed(1);

const String _tableHeader = '  shape                 '
'  median ms   min ms   missed  worst ms  dropped';
const String _tableRule = '  ----------------------'
'  ---------  -------  -------  --------  -------';

void printRow(Measurement m) {
  stdout.writeln(
    '  ${_pad(m.label, 22)}'
    '  ${_padLeft(_ms(m.medianMs), 9)}'
    ' ${_padLeft(_ms(m.minMs), 8)}'
    ' ${_padLeft(m.missedIntervals.toStringAsFixed(0), 8)}'
    ' ${_padLeft(_ms(m.worstIntervalMs), 9)}'
    ' ${_padLeft(m.droppedFrames.toStringAsFixed(0), 8)}',
  );
}

/// True when this binary was compiled ahead of time.
///
/// `dart compile exe` produces a product-mode snapshot and `dart run` does not.
/// It matters: the shipped app runs AOT, so a JIT figure is the pessimistic
/// case rather than the one an operator feels.
const bool isAotProductBuild = bool.fromEnvironment('dart.vm.product');

void printPreamble({required int runsPerShape}) {
  stdout.writeln('Sign-in latency at the shipped Argon2id constants');
  stdout.writeln('  taken at:     ${DateTime.now().toIso8601String()}');
  stdout.writeln('  host:         ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}');
  stdout.writeln('  processors:   ${Platform.numberOfProcessors}');
  stdout.writeln('  dart:         ${Platform.version}');
  stdout.writeln('  compiled:     '
      '${isAotProductBuild ? 'AOT (product mode)' : 'JIT (dart run)'}');
  stdout.writeln('  runs:         $runsPerShape per shape');
  final params = Argon2idKdf.productionParams;
  stdout.writeln('  argon2id:     m=${params.memoryKib} KiB, '
      't=${params.iterations}, p=${params.parallelism}, '
      'hashLength=${params.hashLength}, '
      'maxIsolates=${Argon2idKdf.maxIsolates}, '
      'chunk=${Argon2idKdf.blocksPerProcessingChunk}');
  stdout.writeln('  legacy row:   pbkdf2-sha256 at '
      '${Pbkdf2Kdf.defaultIterations} iterations');
  stdout.writeln();
}

void printUsage() {
  stdout.writeln('Sign-in latency for tfc_access, at the shipped constants.');
  stdout.writeln();
  stdout.writeln('  dart run tool/login_latency.dart');
  stdout.writeln('      Measure the three login shapes — steady state, '
      'migrating (one-time) and');
  stdout.writeln('      second login — $defaultRuns runs each, through '
      'PasswordHasher.hash and');
  stdout.writeln('      PasswordHasher.verify. Run this on panel hardware; a '
      'developer machine is');
  stdout.writeln('      roughly twice as fast and its figures are a baseline, '
      'never the answer.');
  stdout.writeln();
  stdout.writeln('  dart run tool/login_latency.dart --runs=3');
  stdout.writeln('      Fewer runs per shape. Three is enough for a '
      'proof-of-life check.');
  stdout.writeln();
  stdout.writeln('  dart run tool/login_latency.dart --help');
  stdout.writeln('      This text.');
  stdout.writeln();
  stdout.writeln('It reports wall time and a missed-frame proxy. Neither '
      'answers whether the panel');
  stdout.writeln('stays responsive during a real sign-in — that needs somebody '
      'watching the screen.');
}

/// Parse `--runs=N`. Returns null and writes to stderr if it is not a positive
/// integer.
int? parseRuns(String value) {
  final runs = int.tryParse(value);
  if (runs == null || runs < 1) {
    stderr.writeln('login_latency: --runs must be a positive integer, '
        'got "$value"');
    return null;
  }
  return runs;
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    return;
  }
  final unknown = args
      .where((a) => a != '-h' && a != '--help' && !a.startsWith('--runs='))
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('login_latency: unrecognised argument(s): '
        '${unknown.join(', ')}');
    stderr.writeln('Try --help.');
    exitCode = exitUsage;
    return;
  }

  var runsPerShape = defaultRuns;
  final runsArg =
      args.where((a) => a.startsWith('--runs=')).lastOrNull?.substring(7);
  if (runsArg != null) {
    final parsed = parseRuns(runsArg);
    if (parsed == null) {
      exitCode = exitUsage;
      return;
    }
    runsPerShape = parsed;
  }

  printPreamble(runsPerShape: runsPerShape);

  // Setup, outside every measured body: an argon2id row as the login path
  // writes one, and a pbkdf2-sha256 row as a carried-over user has one.
  final argon2idRow = await PasswordHasher.hash(benchPassword);
  final legacyRow = await legacyPbkdf2Row(benchPassword);

  // Refuse to print a table that is measuring the wrong thing. The test cost
  // hook is a dial over both algorithms, and a run with it set would produce a
  // very fast, very meaningless number; rather than read that hook — it is
  // visible for testing and this is not a test — check the parameters that came
  // out of the hash against the production ones, which catches the same
  // mistake and anything else that moved them.
  const expected = Argon2idKdf.productionParams;
  final producedHashLength = base64Decode(argon2idRow.hashB64).length;
  if (argon2idRow.memoryKib != expected.memoryKib ||
      argon2idRow.iterations != expected.iterations ||
      argon2idRow.parallelism != expected.parallelism ||
      producedHashLength != expected.hashLength) {
    stderr.writeln('login_latency: refusing to report. A fresh hash came out '
        'at m=${argon2idRow.memoryKib}, t=${argon2idRow.iterations}, '
        'p=${argon2idRow.parallelism}, hashLength=$producedHashLength — not '
        'the production parameters $expected.');
    exitCode = exitUnsound;
    return;
  }

  // And refuse to time work that did not do what a login does. A verify that
  // returns false is a fast verify.
  final soundness = <String, bool>{
    'the argon2id row verifies':
        await PasswordHasher.verify(password: benchPassword,
            stored: argon2idRow),
    'the pbkdf2-sha256 row verifies':
        await PasswordHasher.verify(password: benchPassword, stored: legacyRow),
    'a wrong password is rejected': !await PasswordHasher.verify(
        password: '$benchPassword-wrong', stored: argon2idRow),
    'the pbkdf2-sha256 row is due a rewrite':
        PasswordHasher.needsRehash(legacyRow),
    'the argon2id row is not': !PasswordHasher.needsRehash(argon2idRow),
  };
  final failed = soundness.entries.where((e) => !e.value).map((e) => e.key);
  if (failed.isNotEmpty) {
    stderr.writeln('login_latency: refusing to report. These did not hold: '
        '${failed.join('; ')}.');
    exitCode = exitUnsound;
    return;
  }

  stdout.writeln('  stored rows:  $argon2idRow');
  stdout.writeln('                $legacyRow');
  stdout.writeln();

  final results = <Measurement>[];

  // 1. Steady state. What every sign-in costs from the second one onward.
  results.add(await measure(
    label: 'steady state',
    note: '',
    runs: runsPerShape,
    body: () async {
      await PasswordHasher.verify(password: benchPassword,
          stored: argon2idRow);
    },
  ));

  // 2. Migrating. Verify the old row, then hash again for the write-back —
  // the two derivations LocalAuthProvider.authenticate does on a carried-over
  // user's first successful login, and only that one.
  PasswordHash? rewritten;
  results.add(await measure(
    label: 'migrating (one-time)',
    note: 'once per user, ever — not the sign-in latency',
    runs: runsPerShape,
    body: () async {
      await PasswordHasher.verify(password: benchPassword, stored: legacyRow);
      rewritten = await PasswordHasher.hash(benchPassword);
    },
  ));

  // 3. Second login, against the row shape 2 actually wrote — not a freshly
  // made one. This is what makes "one-time" a measurement rather than a claim.
  final rewrittenRow = rewritten;
  if (rewrittenRow == null) {
    stderr.writeln('login_latency: the migrating shape produced no row.');
    exitCode = exitUnsound;
    return;
  }
  if (rewrittenRow.algorithm != PasswordHashAlgorithm.argon2id) {
    stderr.writeln('login_latency: the migrating shape wrote back a '
        '${rewrittenRow.algorithm.tag} row, not argon2id.');
    exitCode = exitUnsound;
    return;
  }
  results.add(await measure(
    label: 'second login',
    note: 'against the row the migrating shape wrote back',
    runs: runsPerShape,
    body: () async {
      await PasswordHasher.verify(password: benchPassword,
          stored: rewrittenRow);
    },
  ));

  stdout.writeln(_tableHeader);
  stdout.writeln(_tableRule);
  for (final m in results) {
    printRow(m);
  }
  stdout.writeln();
  for (final m in results.where((m) => m.note.isNotEmpty)) {
    stdout.writeln('  ${m.label}: ${m.note}');
  }
  stdout.writeln();
  for (final m in results) {
    stdout.writeln('  ${_pad('${m.label}:', 22)} '
        'runs ${m.runs.map(_ms).join(', ')} ms');
  }
  stdout.writeln();
  stdout.writeln('"missed" is 16 ms ticker intervals over 32 ms; "worst" is '
      'the longest single gap;');
  stdout.writeln('"dropped" is the frames those gaps account for. This is a '
      'bare isolate with');
  stdout.writeln('nothing else to do — it is a proxy for the screen freezing '
      'behind a login, and');
  stdout.writeln('not a substitute for somebody watching that screen while '
      'somebody signs in.');
  stdout.writeln();
  stdout.writeln('These are derivation times only: no database round trip, no '
      'session write, no');
  stdout.writeln('frame. An operator waits for this plus those.');
}
