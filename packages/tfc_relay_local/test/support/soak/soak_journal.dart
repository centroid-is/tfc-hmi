/// SKELETON — 11-01 task 3's RED. The declarations exist so the cases can be
/// named; nothing here reaches disk yet.
library;

import 'dart:io';

import 'invariant.dart';

/// Where the journal writes, relative to the package root.
const String defaultSoakJournalDir = 'build/soak';

/// How many inbound frames each panel's ring retains.
const int frameRingCapacity = 200;

/// How many checkpoints the trip record quotes inline.
const int metricsTailCapacity = 20;

/// Prints the seed, before anything else does anything.
void announceSoakSeed(int seed, {required Duration declaredDuration}) {}

/// The exact command that reproduces a run.
String soakReproductionCommand(int seed) =>
    throw UnimplementedError('soakReproductionCommand');

/// One inbound frame, as much of it as a trip record needs.
final class JournalledFrame {
  const JournalledFrame({
    required this.arrival,
    required this.seq,
    required this.summary,
  });

  final Duration arrival;
  final int? seq;
  final String summary;

  Map<String, Object?> toJson() => throw UnimplementedError('toJson');
}

/// A fixed-capacity ring of the most recent frames for one panel.
final class FrameRing {
  FrameRing({this.capacity = frameRingCapacity});

  final int capacity;

  void add(JournalledFrame frame) => throw UnimplementedError('FrameRing.add');

  List<JournalledFrame> get entries => const <JournalledFrame>[];

  int get evicted => 0;

  int get length => 0;
}

/// Streams the run's forensics to `build/soak/`.
final class SoakJournal {
  SoakJournal._(this.seed, this.directory);

  factory SoakJournal.open({
    required int seed,
    String path = defaultSoakJournalDir,
  }) =>
      SoakJournal._(seed, Directory(path));

  final int seed;
  final Directory directory;

  void writeReproLog(String reproLog) =>
      throw UnimplementedError('writeReproLog');

  void writeConfig(Map<String, Object?> config) =>
      throw UnimplementedError('writeConfig');

  void checkpoint(SoakClock clock, Map<String, Object?> metrics) =>
      throw UnimplementedError('checkpoint');

  void event(SoakClock clock, Map<String, Object?> entry) =>
      throw UnimplementedError('event');

  void frame(String panel, JournalledFrame frame) =>
      throw UnimplementedError('frame');

  void writeTrip(
    SoakViolation violation, {
    required List<String> armedModes,
  }) =>
      throw UnimplementedError('writeTrip');

  Map<String, int> get retainedInventory => const <String, int>{};

  int get retainedObjects => 0;

  int get checkpointCount => 0;

  int get eventCount => 0;

  int get tripCount => 0;

  Future<void> close() async {}
}
