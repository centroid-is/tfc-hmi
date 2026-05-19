// UMAS-related Riverpod providers.
//
// Today this file exposes the *per-connection* bit-alias decoder used by
// FB-binding assets (e.g. `ConveyorFbConfig`) to render located-bit /
// boolean-alias indicators. The decoder is keyed by Modbus `serverAlias`
// because different PLCs publish different alias maps:
//
//   * Each `ModbusDeviceClientAdapter` owns ONE long-lived `UmasClient`
//     (see `umas-fb-freeze-loop` debug session — duplicating the client
//     breaks the M580's single-session-per-TCP invariant).
//   * Each `UmasClient` lazily builds and caches a `UmasBitAliasMap`
//     for its paired PLC project (see `UmasClient.ensureBitAliasMap`).
//   * We surface that map through `umasBitAliasMapProvider(serverAlias)`
//     and wrap it in a `BitAliasDecoder` via
//     `bitAliasDecoderProvider(serverAlias)`.
//
// Design notes:
//   * Per-connection (not global). Different PLCs, different maps.
//     A Conveyor FB asset bound to PLC A must NOT decode bits using
//     PLC B's map — bit offsets would mismatch silently.
//   * Failure-tolerant. When UMAS isn't enabled, the connection is
//     down, or `ensureBitAliasMap` throws, the decoder provider returns
//     `StubBitAliasDecoder` (everything -> null -> "?" in UI). The
//     conveyor indicators degrade visibly rather than crash.
//   * `null` serverAlias is treated as "no connection known yet" and
//     also yields the stub decoder. Useful during preview / config
//     where the asset hasn't been wired to a key mapping yet.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:tfc_dart/core/state_man.dart' show StateMan;
import 'package:tfc_dart/core/umas_bit_alias.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';

import 'state_man.dart';

/// Returns the live [UmasBitAliasMap] for the Modbus server identified
/// by [serverAlias].
///
/// Returns `null` when:
///   * [serverAlias] is `null` or empty.
///   * No `ModbusDeviceClientAdapter` exists for that alias.
///   * The adapter has no active `UmasClient` (connection down or
///     `umasEnabled == false`).
///   * `ensureBitAliasMap()` throws (logged via `stderr.writeln`).
///
/// Otherwise returns the cached `UmasBitAliasMap` built from the
/// paired project's DD02 short records + browse tree.
///
/// This provider is `autoDispose`-free: the map is small (typically a
/// few hundred entries) and rebuilding it is expensive, so we let it
/// stay alive for the lifetime of the StateMan.
final umasBitAliasMapProvider =
    FutureProvider.family<UmasBitAliasMap?, String?>((ref, serverAlias) async {
  if (serverAlias == null || serverAlias.isEmpty) return null;

  final StateMan stateMan;
  try {
    stateMan = await ref.watch(stateManProvider.future);
  } catch (_) {
    return null;
  }

  // Find the ModbusDeviceClientAdapter for this alias.
  ModbusDeviceClientAdapter? adapter;
  for (final dc
      in stateMan.deviceClients.whereType<ModbusDeviceClientAdapter>()) {
    if (dc.serverAlias == serverAlias) {
      adapter = dc;
      break;
    }
  }
  if (adapter == null) return null;

  final client = adapter.umasClient;
  if (client == null) return null;

  try {
    return await client.ensureBitAliasMap();
  } catch (e) {
    stderr.writeln(
      'umasBitAliasMapProvider("$serverAlias"): ensureBitAliasMap failed: $e',
    );
    return null;
  }
});

/// Synchronous decoder lookup. Resolves the bit-alias map for
/// [serverAlias] (via [umasBitAliasMapProvider]) and wraps it in a
/// [UmasBitAliasDecoder]. Falls back to [StubBitAliasDecoder] when the
/// map is unavailable (connection down, UMAS disabled,
/// `ensureBitAliasMap` failed, or [serverAlias] is null/empty).
///
/// Consumers (e.g. `ConveyorFb`) treat the returned decoder as the
/// single source of truth:
///   * `null` from `decodeBit` -> render "?" placeholder.
///   * `true`/`false` -> render lit / dim.
///
/// The provider deliberately returns a real `BitAliasDecoder` even on
/// error so call sites stay declarative — they never have to check
/// `AsyncValue.when` to render an indicator.
final bitAliasDecoderProvider =
    Provider.family<BitAliasDecoder, String?>((ref, serverAlias) {
  // While the future is loading or has errored, fall through to stub.
  // Once the map is ready, swap in the real decoder.
  final asyncMap = ref.watch(umasBitAliasMapProvider(serverAlias));
  final map = asyncMap.valueOrNull;
  if (map == null) return const StubBitAliasDecoder();
  return UmasBitAliasDecoder(map);
});
