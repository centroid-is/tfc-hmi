import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'preferences.dart';
import 'collector.dart';

part 'state_man.g.dart';

Future<KeyMappings> fetchKeyMappings(PreferencesApi prefs) async {
  var keyMappingsJson = await prefs.getString('key_mappings');
  if (keyMappingsJson == null) {
    final defaultKeyMappings = KeyMappings(nodes: {
      "exampleKey": KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 42, identifier: "identifier"))
    });
    keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
    await prefs.setString('key_mappings', keyMappingsJson);
  }
  return KeyMappings.fromJson(jsonDecode(keyMappingsJson));
}

@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  // Use ref.read instead of ref.watch to break the reactive dependency chain.
  // StateMan reads config once at init; DB reconnects should NOT cascade here
  // and destroy all OPC-UA connections/isolates.
  final prefs = await ref.read(preferencesProvider.future);
  final config = await StateManConfig.fromPrefs(prefs);

  final keyMappings = await fetchKeyMappings(prefs);

  // Watch for changes in specific preferences.
  //
  // A key_mappings save is applied incrementally: unchanged keys keep their
  // connections and subscriptions untouched, edited OPC UA keys are
  // re-pointed live, and only edits the adapters cannot absorb in place
  // (classic-Modbus register specs, M2400 extraction) fall back to a full
  // provider rebuild — the old "whole world awakens" path.
  //
  // Applications are serialized through [pendingApply] so two rapid saves
  // cannot interleave their diffs out of order.
  var pendingApply = Future<void>.value();
  final listener = prefs.onPreferencesChanged.listen(
    (key) {
      if (key == 'key_mappings') {
        pendingApply = pendingApply.then((_) async {
          try {
            final stateMan = await ref.read(stateManProvider.future);
            final newPrefs = await ref.read(preferencesProvider.future);
            final result =
                stateMan.updateKeyMappings(await fetchKeyMappings(newPrefs));
            if (result.requiresReload) {
              stderr.writeln('key_mappings: full reload required '
                  '(${result.reloadReasons.join('; ')})');
              ref.invalidateSelf();
            }
          } catch (error) {
            stderr.writeln('Failed to apply key_mappings change: $error');
          }
        });
      }
    },
    onError: (error) {
      stderr.writeln('Error in preferences listener: $error');
    },
  );

  try {
    final m2400Clients = createM2400DeviceClients(config.jbtm);
    final modbusClients = buildModbusDeviceClients(config.modbus, keyMappings);
    final deviceClients = [...m2400Clients, ...modbusClients];
    final stateMan = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        deviceClients: deviceClients);

    // Initialize collector
    ref.read(collectorProvider.future);

    ref.onDispose(() async {
      listener.cancel();
      await stateMan.close();
    });
    return stateMan;
  } catch (e) {
    listener.cancel();
    stderr.writeln('Error parsing key mappings: $e');
    rethrow;
  }
}

final substitutionsChangedProvider =
    StreamProvider<Map<String, String>>((ref) async* {
  final sm = await ref.watch(stateManProvider.future);
  yield* sm.substitutionsChanged;
});

/// The live value of one key, as a stream that outlives the widgets watching
/// it.
///
/// Assets used to build their subscriptions inside `build`, which handed
/// `StreamBuilder` a new stream object on every rebuild — and a new object
/// means cancel the old subscription and open a fresh one. Resizing a window
/// or dragging an asset around the page editor rebuilds continuously, so
/// every asset on the page dropped and re-made its subscriptions once a
/// frame. Measured on the plant HMI that cost ~130 KiB of log a second, kept
/// StateMan's retry ladder permanently reset to its first step, and left the
/// window visibly lagging the mouse.
///
/// Reading through this instead, the subscription belongs to the *key* rather
/// than to whoever happens to be drawing it. A rebuild re-listens to a
/// [BehaviorSubject] that is already open and already holds the latest value;
/// nothing reaches StateMan at all. Two assets bound to the same key share one
/// subscription instead of opening two, and the value they show is the same
/// value by construction.
///
/// Auto-disposed, so leaving a page releases what that page was reading. A
/// rebuild does not: the watching element re-establishes its subscription
/// within the same frame, so the listener count never reaches zero.
final keyStreamProvider =
    Provider.autoDispose.family<Stream<DynamicValue>, String>((ref, key) {
  // Rebuilt if the connection is replaced, so the streams handed out are
  // always the current StateMan's. Until one exists there is nothing to
  // subscribe to, and an empty stream leaves each asset showing the same
  // "no value yet" it shows while waiting for a first reading.
  final stateMan = ref.watch(stateManProvider).valueOrNull;
  if (stateMan == null) return const Stream<DynamicValue>.empty();

  // A subject rather than the raw stream: it is broadcast, so a rebuild may
  // re-listen freely, and it replays the last value, so an asset that
  // re-listens shows what it last knew instead of blanking.
  final subject = BehaviorSubject<DynamicValue>();
  StreamSubscription<DynamicValue>? subscription;
  var disposed = false;

  Future<void> open() async {
    try {
      final values = await stateMan.subscribe(key);
      if (disposed) return;
      subscription = values.listen(subject.add, onError: subject.addError);
    } catch (error, stackTrace) {
      // Reported to whoever is watching rather than swallowed: an asset bound
      // to a key the PLC does not serve should show that, and StateMan does
      // its own retrying underneath.
      if (!disposed) subject.addError(error, stackTrace);
    }
  }

  unawaited(open());
  ref.onDispose(() {
    disposed = true;
    subscription?.cancel();
    subject.close();
  });

  return subject.stream;
});
