/// Argon2id parameter sweep, run by hand on the hardware the panel runs on.
///
/// ## What this is for
///
/// Phase 7 replaces PBKDF2-200k with Argon2id, and all four core Argon2id
/// parameters are required with no defaults, so somebody has to choose them.
/// OWASP's numbers (m = 19 MiB, t = 2, p = 1) assume a native implementation.
/// `cryptography_flutter` does not accelerate Argon2 — grepping its lib for the
/// name returns nothing — so on the panel this derivation runs pure Dart, and a
/// login runs on a screen with a live process behind it. The six numbers this
/// tool exists to choose therefore have to come from a measurement taken on
/// panel hardware rather than from a table.
///
/// ## What this is not
///
/// It is not a test. Nothing here asserts, CI never runs it, and its output is
/// recorded in a plan summary rather than in an expectation. It is run by hand:
///
///     dart run tool/argon2_bench.dart              # full two-pass sweep
///     dart run tool/argon2_bench.dart --quick      # pass 1 only, 3 runs
///     dart run tool/argon2_bench.dart --knobs=4,65536,3   # knob sweep, one core set
///     dart run tool/argon2_bench.dart --help
///
/// `--quick` exists because pass 1 alone is 18 candidates at up to 64 MiB of
/// pure-Dart mixing, and in JIT on a developer machine that can outlive a
/// command timeout and turn a proof-of-life check into a stall. The panel gets
/// the full grid. A developer machine gets `--quick`, and what it produces is a
/// baseline for comparison, never the answer.
///
/// `--knobs=p,memory,iterations` runs the knob sweep alone against one core set
/// named on the command line. Pass 2 sweeps the knobs against whichever core
/// sets came out fastest, and the row worth shipping is not always one of them —
/// a row proposed for its strength then needs its own missed-frame line rather
/// than one borrowed from a lighter core set. It is also how the next person
/// re-checks a shipped parameter set on a different panel without waiting for
/// the whole grid.
///
/// ## What it reports, and why two numbers and not one
///
/// Wall time cannot see `blocksPerProcessingChunk`: the derivation takes about
/// the same time whether it hands the event loop back nine times or never. So
/// every measurement also arms a 16 ms ticker and reports how badly that ticker
/// was starved while the derivation ran. That is the proxy for the screen
/// freezing behind the login, and it is the only column that knob shows up in.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:cryptography/dart.dart';

/// The strength floor, in 1 KiB blocks.
///
/// This is OWASP's memory for Argon2id. It is a floor and not a target: below
/// this line a memory-hard algorithm is weaker than the PBKDF2-200k it would
/// replace, and it would ship under a better algorithm's name. A candidate
/// under the floor is ineligible however fast it is.
const int floorMemoryKib = 19456;

/// The strength floor, in passes. OWASP's time cost, same reasoning.
const int floorIterations = 2;

/// The stored hash width in bytes. Fixed, and deliberately not swept.
///
/// `PasswordHash` stores a 256-bit hash today, and
/// `PasswordHasher.constantTimeEquals` documents that "the hash is always 32
/// bytes". Changing the width is a different decision than this one.
const int hashLengthBytes = 32;

/// Salt width in bytes — `PasswordHasher.saltBytes`, so the benchmark measures
/// the same work the implementation will do.
const int saltBytes = 16;

/// The package's own default for `maxIsolates`, quoted so the computed isolate
/// count below matches what the package will actually do.
const int packageDefaultMaxIsolates = 8;

/// The package's own default for `minBlocksPerSliceForEachIsolate`.
const int packageDefaultMinBlocksPerSlice = 200;

/// The package's own default for `blocksPerProcessingChunk`.
const int packageDefaultBlocksPerChunk = 500;

/// A fixed passphrase: the point is to compare parameters, so nothing else may
/// vary between runs.
const String benchPassphrase = 'correct-horse-battery-staple-07';

/// One parameter set to measure.
class Candidate {
  const Candidate({
    required this.label,
    required this.parallelism,
    required this.memory,
    required this.iterations,
    this.maxIsolates,
    this.blocksPerProcessingChunk,
  });

  /// How the row is named in the report.
  final String label;

  /// Lanes. Not pinned at OWASP's 1: the package caps its isolate count at
  /// this value, so p = 1 forfeits the isolate spread entirely.
  final int parallelism;

  /// Memory as a count of 1 KiB blocks — the unit the package takes.
  final int memory;

  /// Passes over the memory.
  final int iterations;

  /// null means the package default of [packageDefaultMaxIsolates]; 0 means
  /// isolates off.
  final int? maxIsolates;

  /// null means the package default of [packageDefaultBlocksPerChunk]; -1
  /// means never yield to the event loop.
  final int? blocksPerProcessingChunk;

  /// Whether this candidate is eligible at all.
  bool get meetsFloor =>
      memory >= floorMemoryKib && iterations >= floorIterations;

  /// The number of blocks the package will actually allocate.
  ///
  /// RFC 9106's m' = 4p * floor(m / 4p), quoted from
  /// `src/dart/argon2.dart:168-172`.
  int get blockCount => 4 * parallelism * (memory ~/ (4 * parallelism));

  /// How many isolates the package will spawn for this candidate.
  ///
  /// **Computed, not observed.** This is `isolateCount` from
  /// `src/dart/argon2_impl_default.dart:54-66` evaluated here, so the report
  /// can show when a candidate is silently single-isolate. Note the
  /// `min(parallelism, maxIsolates)` cap: at p = 1 this is zero however high
  /// `maxIsolates` is set, which is why the two are chosen together and never
  /// independently.
  int get computedIsolates {
    var limit = maxIsolates ?? packageDefaultMaxIsolates;
    if (limit < 1) {
      return 0;
    }
    limit = min(parallelism, limit);
    final blocksPerSlice = blockCount ~/ 4;
    return min(limit, blocksPerSlice ~/ packageDefaultMinBlocksPerSlice);
  }

  /// Construct `DartArgon2id` directly, from `package:cryptography/dart.dart`.
  ///
  /// Not the `Argon2id` factory constructor in `algorithms.dart:503`: that one
  /// routes through `Cryptography.instance` and accepts only the four core
  /// parameters, which puts `maxIsolates` and `blocksPerProcessingChunk` — the
  /// isolate knob and the UI-jank knob, the two this sweep exists to choose —
  /// out of reach entirely. This is not a verbosity to simplify away later; the
  /// shorter spelling cannot express half of what is being measured here.
  DartArgon2id build() => DartArgon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: iterations,
        hashLength: hashLengthBytes,
        maxIsolates: maxIsolates,
        blocksPerProcessingChunk: blocksPerProcessingChunk,
      );

  /// A copy with the two optional knobs replaced. Used to build pass 2.
  Candidate withKnobs({
    required String label,
    required int? maxIsolates,
    required int? blocksPerProcessingChunk,
  }) =>
      Candidate(
        label: label,
        parallelism: parallelism,
        memory: memory,
        iterations: iterations,
        maxIsolates: maxIsolates,
        blocksPerProcessingChunk: blocksPerProcessingChunk,
      );
}

/// What one candidate measured.
class Measurement {
  const Measurement({
    required this.candidate,
    required this.runs,
    required this.medianMs,
    required this.minMs,
    required this.missedIntervals,
    required this.worstIntervalMs,
    required this.droppedFrames,
  });

  final Candidate candidate;

  /// Every run's wall time in milliseconds, in the order they were taken.
  /// Nothing is discarded — an outlier is information, not noise.
  final List<double> runs;

  final double medianMs;
  final double minMs;

  /// Median across runs of the number of ticker intervals longer than 32 ms —
  /// one missed frame. This is the jank proxy the knob is chosen from.
  final double missedIntervals;

  /// The single worst gap between ticker fires, across every run. At
  /// `blocksPerProcessingChunk: -1` this approaches the whole derivation time,
  /// because nothing hands the event loop back at all.
  final double worstIntervalMs;

  /// Median across runs of how many 16 ms frames the ticker's gaps account for
  /// in total. A derived figure: it is what the missed-interval count would be
  /// if a starved ticker still fired once per frame, and it separates "one long
  /// stall" from "many short ones" where the interval count alone cannot.
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

/// Measure one candidate [runs] times.
///
/// Each run arms a periodic 16 ms `Timer` before the derivation starts and
/// records the real gap between fires. Two things are counted from those gaps:
/// intervals over 32 ms (a missed frame), and the total number of 16 ms frames
/// the gaps account for. The timer is cancelled before the run is scored.
Future<Measurement> measure(Candidate candidate, int runs) async {
  final salt = List<int>.generate(saltBytes, (i) => (i * 37 + 11) & 0xFF);
  final secretKey = SecretKey(utf8.encode(benchPassphrase));
  final kdf = candidate.build();

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
    await kdf.deriveKey(secretKey: secretKey, nonce: salt);
    watch.stop();

    // Score the tail of the derivation too. A run that never yielded leaves a
    // gap the ticker has had no chance to report, and dropping it would make
    // the worst case look like the best one.
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
    candidate: candidate,
    runs: wallMs,
    medianMs: _median(wallMs),
    minMs: wallMs.reduce(min),
    missedIntervals: _median(missed),
    worstIntervalMs: worstMs,
    droppedFrames: _median(dropped),
  );
}

/// Pass 1: the three core parameters, both optional knobs at their defaults.
///
/// Memory starts at [floorMemoryKib] — 19456 KiB — and only goes up from there.
/// There is deliberately no sub-floor row in the grid: the failure mode this
/// whole exercise invites is picking the fastest row, so a fast weak row is the
/// one thing the measurement must not be able to recommend.
List<Candidate> pass1Grid() {
  final candidates = <Candidate>[];
  for (final parallelism in <int>[1, 2, 4]) {
    for (final memory in <int>[floorMemoryKib, 32768, 65536]) {
      for (final iterations in <int>[2, 3]) {
        candidates.add(Candidate(
          label: 'p=$parallelism m=$memory t=$iterations',
          parallelism: parallelism,
          memory: memory,
          iterations: iterations,
        ));
      }
    }
  }
  return candidates;
}

/// Pass 2: the two knobs, against the fastest floor-meeting core sets only.
///
/// The full cross product is 108 candidates at up to a second each, five times
/// over, which is not a sweep anybody waits for. Sweeping in two passes costs
/// the interaction between the core parameters and the knobs, which is a real
/// loss but a small one — neither knob changes how much mixing happens.
List<Candidate> pass2Grid(List<Measurement> pass1, {int coreSets = 3}) {
  final eligible = pass1.where((m) => m.candidate.meetsFloor).toList()
    ..sort((a, b) => a.medianMs.compareTo(b.medianMs));
  return [
    for (final m in eligible.take(coreSets)) ...knobGridFor(m.candidate),
  ];
}

/// The six knob combinations, against one core set.
List<Candidate> knobGridFor(Candidate core) {
  final candidates = <Candidate>[];
  for (final maxIsolates in <int?>[null, 0]) {
    for (final chunk in <int?>[null, 128, -1]) {
      final isolateLabel = maxIsolates == null ? 'iso=def' : 'iso=off';
      final chunkLabel = chunk == null ? 'chunk=def' : 'chunk=$chunk';
      candidates.add(core.withKnobs(
        label: '${core.label} $isolateLabel $chunkLabel',
        maxIsolates: maxIsolates,
        blocksPerProcessingChunk: chunk,
      ));
    }
  }
  return candidates;
}

/// Parse `--knobs=p,memory,iterations` into the core set it names.
///
/// Returns null and writes to stderr if the value is not three positive
/// integers the package will accept — `DartArgon2id` asserts
/// `memory >= 8 * parallelism`, and an assert that only fires in a debug build
/// is not a diagnostic anybody wants from a tool that is usually run AOT.
Candidate? parseKnobsCore(String value) {
  final parts = value.split(',');
  if (parts.length != 3) {
    stderr.writeln('argon2_bench: --knobs takes three values: '
        'parallelism,memory,iterations (e.g. --knobs=4,65536,3)');
    return null;
  }
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((n) => n == null || n < 1)) {
    stderr.writeln('argon2_bench: --knobs values must be positive integers, '
        'got "$value"');
    return null;
  }
  final parallelism = numbers[0]!;
  final memory = numbers[1]!;
  final iterations = numbers[2]!;
  if (memory < 8 * parallelism) {
    stderr.writeln('argon2_bench: memory must be at least 8 * parallelism '
        '(${8 * parallelism}), got $memory');
    return null;
  }
  return Candidate(
    label: 'p=$parallelism m=$memory t=$iterations',
    parallelism: parallelism,
    memory: memory,
    iterations: iterations,
  );
}

String _pad(String value, int width) => value.padRight(width);
String _padLeft(String value, int width) => value.padLeft(width);
String _ms(double value) => value.toStringAsFixed(1);

const String _tableHeader = '  candidate                                 '
    ' iso  median ms   min ms   missed  worst ms  dropped  floor';
const String _tableRule = '  -----------------------------------------'
    ' ---  ---------  -------  -------  --------  -------  -----';

void printRow(Measurement m) {
  final c = m.candidate;
  stdout.writeln(
    '  ${_pad(c.label, 41)}'
    ' ${_padLeft('${c.computedIsolates}', 3)}'
    '  ${_padLeft(_ms(m.medianMs), 9)}'
    ' ${_padLeft(_ms(m.minMs), 8)}'
    ' ${_padLeft(m.missedIntervals.toStringAsFixed(0), 8)}'
    ' ${_padLeft(_ms(m.worstIntervalMs), 9)}'
    ' ${_padLeft(m.droppedFrames.toStringAsFixed(0), 8)}'
    '  ${c.meetsFloor ? 'ok' : 'INELIGIBLE'}',
  );
}

/// True when this binary was compiled ahead of time.
///
/// `dart compile exe` produces a product-mode snapshot and `dart run` does not,
/// so this separates the two. It matters: the shipped app runs AOT, and a JIT
/// number is the pessimistic case rather than the one an operator will feel.
const bool isAotProductBuild = bool.fromEnvironment('dart.vm.product');

void printPreamble({required String sweep, required int runsPerCandidate}) {
  stdout.writeln('Argon2id parameter sweep (pure Dart, DartArgon2id)');
  stdout.writeln('  taken at:     ${DateTime.now().toIso8601String()}');
  stdout.writeln('  host:         ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}');
  stdout.writeln('  processors:   ${Platform.numberOfProcessors}');
  stdout.writeln('  dart:         ${Platform.version}');
  stdout.writeln('  compiled:     '
      '${isAotProductBuild ? 'AOT (product mode)' : 'JIT (dart run)'}');
  stdout.writeln('  mode:         $sweep, $runsPerCandidate runs per candidate');
  stdout.writeln('  hash length:  $hashLengthBytes bytes (fixed, not swept)');
  stdout.writeln('  salt:         $saltBytes bytes (fixed, not swept)');
  stdout.writeln('  floor:        memory >= $floorMemoryKib KiB and '
      'iterations >= $floorIterations');
  stdout.writeln();
  stdout.writeln('A row marked INELIGIBLE is out of the running whatever its '
      'time says: the floor is');
  stdout.writeln('not negotiable downward to hit a latency target. "iso" is '
      'the isolate count the');
  stdout.writeln('package will compute for the row, derived here rather than '
      'observed. "missed" is');
  stdout.writeln('16 ms ticker intervals over 32 ms; "dropped" is the frames '
      'those gaps account for.');
  stdout.writeln();
}

void printUsage() {
  stdout.writeln('Argon2id parameter sweep for tfc_access.');
  stdout.writeln();
  stdout.writeln('  dart run tool/argon2_bench.dart');
  stdout.writeln('      Full two-pass sweep, 5 runs per candidate. Pass 1 '
      'varies the three core');
  stdout.writeln('      parameters with both optional knobs at their package '
      'defaults; pass 2 varies');
  stdout.writeln('      maxIsolates and blocksPerProcessingChunk against the '
      'fastest floor-meeting');
  stdout.writeln('      core sets from pass 1. This is the run to take on '
      'panel hardware.');
  stdout.writeln();
  stdout.writeln('  dart run tool/argon2_bench.dart --quick');
  stdout.writeln('      Pass 1 only, 3 runs per candidate. A proof-of-life run '
      'for a developer');
  stdout.writeln('      machine. Its numbers are a baseline for comparison and '
      'never the answer:');
  stdout.writeln('      the parameters are chosen from the panel measurement.');
  stdout.writeln();
  stdout.writeln('  dart run tool/argon2_bench.dart --knobs=4,65536,3');
  stdout.writeln('      The knob sweep alone, against the one core set named as '
      'parallelism,memory,');
  stdout.writeln('      iterations. Use it when the row worth shipping is not '
      'one of the fastest');
  stdout.writeln('      core sets pass 2 picks up, and to re-check a shipped '
      'parameter set on new');
  stdout.writeln('      hardware without waiting for the whole grid. Honours '
      '--quick for run count.');
  stdout.writeln();
  stdout.writeln('  dart run tool/argon2_bench.dart --help');
  stdout.writeln('      This text.');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    printUsage();
    return;
  }
  final unknown = args
      .where((a) =>
          a != '--quick' &&
          a != '-h' &&
          a != '--help' &&
          !a.startsWith('--knobs='))
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('argon2_bench: unrecognised argument(s): '
        '${unknown.join(', ')}');
    stderr.writeln('Try --help.');
    exitCode = 64;
    return;
  }

  final quick = args.contains('--quick');
  final runsPerCandidate = quick ? 3 : 5;

  final knobsArg =
      args.where((a) => a.startsWith('--knobs=')).lastOrNull?.substring(8);
  if (knobsArg != null) {
    final core = parseKnobsCore(knobsArg);
    if (core == null) {
      exitCode = 64;
      return;
    }
    printPreamble(
      sweep: 'knob sweep only, core set ${core.label}',
      runsPerCandidate: runsPerCandidate,
    );
    stdout.writeln('KNOB SWEEP — maxIsolates and blocksPerProcessingChunk '
        'against ${core.label} only.');
    stdout.writeln('Read blocksPerProcessingChunk out of the "missed" and '
        '"worst" columns, not out');
    stdout.writeln('of "median": wall time barely moves with it.');
    stdout.writeln();
    stdout.writeln(_tableHeader);
    stdout.writeln(_tableRule);
    for (final candidate in knobGridFor(core)) {
      printRow(await measure(candidate, runsPerCandidate));
    }
    return;
  }

  printPreamble(
    sweep: quick ? '--quick, pass 1 only' : 'full two-pass sweep',
    runsPerCandidate: runsPerCandidate,
  );

  stdout.writeln('PASS 1 — core parameters, maxIsolates and '
      'blocksPerProcessingChunk at package');
  stdout.writeln('defaults ($packageDefaultMaxIsolates capped by parallelism, '
      'and $packageDefaultBlocksPerChunk blocks between yields).');
  stdout.writeln();
  stdout.writeln(_tableHeader);
  stdout.writeln(_tableRule);

  final pass1 = <Measurement>[];
  for (final candidate in pass1Grid()) {
    final measurement = await measure(candidate, runsPerCandidate);
    pass1.add(measurement);
    printRow(measurement);
  }
  stdout.writeln();

  if (quick) {
    stdout.writeln('--quick: pass 2 skipped. Run without --quick on the panel '
        'for the knob sweep.');
    return;
  }

  stdout.writeln('PASS 2 — maxIsolates and blocksPerProcessingChunk against '
      'the fastest');
  stdout.writeln('floor-meeting core sets from pass 1. Read '
      'blocksPerProcessingChunk out of the');
  stdout.writeln('"missed" and "worst" columns, not out of "median": wall time '
      'barely moves with it.');
  stdout.writeln();
  stdout.writeln(_tableHeader);
  stdout.writeln(_tableRule);

  for (final candidate in pass2Grid(pass1)) {
    printRow(await measure(candidate, runsPerCandidate));
  }
  stdout.writeln();
  stdout.writeln('Done. Record the chosen row, both knob columns for it, and '
      'the computed isolate');
  stdout.writeln('count in the plan summary — six named constants, each with a '
      'row behind it.');
}
