/// The reference implementation the contract suite is developed against.
///
/// It is not a mock. It is a real, in-memory `StateManApi` backed by the same
/// [ValueStore] the server and client implementations use, with a control
/// surface ([StateManHarness]) standing in for the plant. Two jobs follow from
/// that: it proves a case is satisfiable before any production code exists, and
/// it is the honest baseline the deliberately damaged variants in
/// `broken_subscribe.dart` are measured against.
///
/// It lives under `lib/testing/` rather than `lib/src/` because the server and
/// client packages import it — a Phase 3 test that needs a state source with a
/// known value in it should not have to build one.
///
/// Members outside this plan's slice throw [UnimplementedError] naming the plan
/// that fills them. That is deliberate: an area nobody has contracted yet must
/// fail loudly if something starts depending on it, rather than return a
/// plausible empty answer.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../src/harness.dart';

/// An in-memory state source with a lever for everything the plant would do.
class FakeStateMan implements StateManApi, StateManHarness {
  FakeStateMan();

  // ------------------------------------------------------------- value path

  @override
  ValueListenable<DynamicValue> listen(String key) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  Stream<DynamicValue> subscribe(String key) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  DynamicValue? read(String key) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  List<String> get keys =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  Future<void> dispose() =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  // --------------------------------------------------------- control surface

  @override
  void setValue(String key, Object? value,
          {Quality quality = Quality.good, DateTime? sourceTime}) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  void setValues(Map<String, Object?> values) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  void setQuality(String key, Quality quality) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  @override
  void dropKey(String key) =>
      throw UnimplementedError('value path: plan 01-06 task 2');

  // ----------------------------------------------------- other slices' areas

  @override
  Future<DynamicValue> readFresh(String key) =>
      throw UnimplementedError('freshness and reads: plan 01-07');

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) =>
      throw UnimplementedError('freshness and reads: plan 01-07');

  @override
  Future<WriteResult> write(String key, Object? value, {Object? expect}) =>
      throw UnimplementedError('writes: plan 01-08');

  @override
  BrowseApi get browse => throw UnimplementedError('data services: plan 01-09');

  @override
  TimeseriesApi get timeseries =>
      throw UnimplementedError('data services: plan 01-09');

  @override
  HistoryViewApi get historyViews =>
      throw UnimplementedError('data services: plan 01-09');

  @override
  PreferencesApi get preferences =>
      throw UnimplementedError('data services: plan 01-09');
}
