/// SKELETON — 11-01 task 2's RED. The declarations exist so the cases can be
/// named; nothing here judges anything yet.
library;

// ignore_for_file: unused_field

/// Monotonic elapsed time and the run's declared duration. Nothing else.
final class SoakClock {
  SoakClock({required this.declaredDuration})
      : _stopwatch = Stopwatch()..start(),
        _frozenAt = null;

  SoakClock.frozenAt(Duration elapsed, {required this.declaredDuration})
      : _stopwatch = Stopwatch(),
        _frozenAt = elapsed;

  final Stopwatch _stopwatch;
  final Duration? _frozenAt;

  final Duration declaredDuration;

  Duration get elapsed => throw UnimplementedError('SoakClock.elapsed');
}

/// One recorded breach.
final class SoakViolation {
  const SoakViolation({
    required this.checker,
    required this.monotonic,
    required this.scheduleOffset,
    required this.detail,
    this.panel,
    this.key,
    this.observed,
    this.expected,
  });

  final String checker;
  final Duration monotonic;
  final Duration? scheduleOffset;
  final String detail;
  final String? panel;
  final String? key;
  final Object? observed;
  final Object? expected;
}

/// `+MM:SS.mmm`.
String formatSoakOffset(Duration offset) =>
    throw UnimplementedError('formatSoakOffset');

/// How many violations one checker retains before it starts counting instead.
const int violationLogCapacity = 200;

/// A bounded violation list with an overflow count.
final class ViolationLog {
  ViolationLog({this.capacity = violationLogCapacity});

  final int capacity;

  void add(SoakViolation violation) =>
      throw UnimplementedError('ViolationLog.add');

  List<SoakViolation> get entries => const <SoakViolation>[];

  int get overflow => 0;

  int get total => 0;

  bool get isEmpty => true;
}

/// One continuously-checked property of the pipe under the storm.
abstract interface class InvariantChecker {
  String get name;

  void sample(SoakClock clock);

  int get judgedSamples;

  int get minimumSamplesForAVerdict;

  List<SoakViolation> get violations;
}

/// Turns a throw inside a checker into a recorded violation.
mixin GuardedSampling implements InvariantChecker {
  ViolationLog get violationLog;

  void takeReading(SoakClock clock);

  @override
  void sample(SoakClock clock) => throw UnimplementedError('sample');

  @override
  List<SoakViolation> get violations => violationLog.entries;
}

/// `perMinute` readings for every declared minute, floored at one.
int minimumSamplesForDuration({
  required int perMinute,
  required Duration declared,
}) =>
    throw UnimplementedError('minimumSamplesForDuration');

/// Fails the run for any checker that did not take enough judgeable readings.
void assertNoVacuousVerdict(List<InvariantChecker> checkers) {}

/// Fails the run for any checker registered under a name nobody declared.
void assertEveryCheckerIsDeclared(
  List<InvariantChecker> checkers,
  List<String> declared,
) {}
