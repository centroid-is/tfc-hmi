// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nav_alarm.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$navigationAlarmsHash() => r'a015dd39b83ff2ba5d1af7add9ec7e7543296110';

/// Live [navigationAlarmLevels] for the navigation bar.
///
/// Recomputed on every change to the active alarm set. Page contents are read
/// fresh each time rather than watched: the page editor mutates
/// `PageManager.pages` in place, so there is no invalidation to listen to, and
/// a beacon added while alarms are quiet is picked up by the next alarm event —
/// which is the only moment its answer could differ.
///
/// Copied from [navigationAlarms].
@ProviderFor(navigationAlarms)
final navigationAlarmsProvider =
    StreamProvider<Map<String, AlarmLevel>>.internal(
  navigationAlarms,
  name: r'navigationAlarmsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$navigationAlarmsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NavigationAlarmsRef = StreamProviderRef<Map<String, AlarmLevel>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
