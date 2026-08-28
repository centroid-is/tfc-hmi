/// Access control wiring: the repository, the auth provider, the audit sink,
/// the station name, the device-local inactivity timeout, and the session
/// itself.
///
/// Everything in `packages/tfc_access` and `tfc_dart/core/access` is testable
/// in isolation and does nothing on its own. This is the file that puts it in
/// front of the operator.
///
/// **Phase 1 gates nothing.** Nothing here denies anything: `can()` is
/// vocabulary the Phase 3 guards will consult, and no route, asset or write
/// path changes behaviour because of this file.
library;

import 'dart:io' as io;

import 'package:logger/logger.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';
import 'package:tfc_dart/core/access/drift_audit_sink.dart';
import 'package:tfc_dart/core/access/local_auth_provider.dart';

import 'database.dart';
import 'preferences.dart';

part 'access.g.dart';

/// The device-local preference key holding the serialised session.
///
/// A constant rather than a literal so the login surface (plan 01-08) and the
/// first-user screen (plan 01-09) name the same key as the tests do.
const String kAccessSessionPrefKey = 'access.session';

/// The device-local preference key holding the inactivity timeout, in minutes.
const String kAccessInactivityMinutesPrefKey =
    'access.inactivity_timeout_minutes';

/// Spec §5: fifteen minutes unless the station says otherwise.
const Duration kDefaultInactivityTimeout = Duration(minutes: 15);

/// The narrowest inactivity timeout a station may configure.
///
/// Below a minute the timeout stops being an inactivity guard and starts being
/// a fault: an operator reading a trend for ninety seconds would be signed out
/// mid-glance.
const Duration kMinInactivityTimeout = Duration(minutes: 1);

/// The widest inactivity timeout a station may configure.
///
/// Eight hours is a shift. Beyond that "times out on inactivity" is no longer
/// true in any useful sense, and a station left elevated overnight is exactly
/// the accident this phase exists to make less likely.
const Duration kMaxInactivityTimeout = Duration(hours: 8);

/// Reads and writes for `app_role` and `app_user`, or null when this station
/// has no database.
///
/// Null is a normal state, not an error: `databaseProvider` yields null when
/// no Postgres is configured, and again during the boot window before the
/// connection opens. Every provider below survives that.
@Riverpod(keepAlive: true)
Future<AccessRepository?> accessRepository(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  if (db == null) return null;
  return AccessRepository(db.db);
}

/// The authentication seam.
///
/// Named for the interface it provides rather than for [LocalAuthProvider],
/// the implementation behind it today. When OIDC lands it becomes an override
/// of this provider rather than a rename of every call site — which is the
/// whole reason `AuthProvider` is an interface.
@Riverpod(keepAlive: true)
Future<AuthProvider?> authProvider(Ref ref) async {
  final repo = await ref.watch(accessRepositoryProvider.future);
  if (repo == null) return null;
  return LocalAuthProvider(repo);
}

/// Where audit rows go.
///
/// [NullAuditSink] when there is no database. That covers two real cases: the
/// boot window before the connection is open, and a station commissioned with
/// no Postgres at all. Losing the trail there is preferable to failing to
/// boot — an HMI that will not start because it cannot write an audit row is a
/// stopped line.
///
/// But it **is** a gap, and it is the kind of gap nobody notices, because a
/// missing row looks exactly like an action that never happened. What makes it
/// visible is the sink's own error logging: [DriftAuditSink] names every row it
/// loses. [NullAuditSink] is silent by design, so a station running without a
/// database is knowingly running without a trail.
@Riverpod(keepAlive: true)
Future<AuditSink> auditSink(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  if (db == null) return const NullAuditSink();
  return DriftAuditSink(db.db);
}

/// The hostname of this panel.
///
/// This is the `station` column of every audit row, and it is what lets the
/// plant manager be shown *which panel* a setpoint was changed from. A trail
/// that records who and when but not where cannot answer "was that the packing
/// hall or the freezer?", which on a plant with identical screens in eight
/// rooms is most of the question.
///
/// `'unknown'` rather than a throw if the platform will not say: a nameless
/// station still writes rows, and a row with a vague station beats no row.
@Riverpod(keepAlive: true)
String stationName(Ref ref) {
  try {
    return io.Platform.localHostname;
  } on Object catch (e) {
    Logger().w('Could not read the local hostname for audit rows: $e');
    return 'unknown';
  }
}

/// How long a quiet panel keeps an elevated session, from device-local
/// preferences.
///
/// **Device-local on purpose.** The timeout is a property of the panel, not of
/// the plant: stations on one database front different equipment, and the
/// screen bolted to a packing line in constant use wants a different number
/// from the one in a locked electrical room. Storing it in the shared
/// `preferencesProvider` would let one station's setting decide another's.
///
/// Clamped to [kMinInactivityTimeout]..[kMaxInactivityTimeout] and logged when
/// it clamps — a stray `0` or a fat-fingered `10000` in the preferences file
/// must not turn into a session that ends instantly or never.
@Riverpod(keepAlive: true)
Future<Duration> inactivityTimeout(Ref ref) async {
  final local = ref.watch(localPreferencesProvider);

  int? minutes;
  try {
    minutes = await local.getInt(kAccessInactivityMinutesPrefKey);
  } on Object catch (e) {
    // A mangled value costs the station its custom timeout, never its boot.
    Logger().w(
      'Could not read "$kAccessInactivityMinutesPrefKey" — falling back to '
      'the ${kDefaultInactivityTimeout.inMinutes}-minute default: $e',
    );
    return kDefaultInactivityTimeout;
  }

  if (minutes == null) return kDefaultInactivityTimeout;

  final requested = Duration(minutes: minutes);
  if (requested < kMinInactivityTimeout) {
    Logger().w(
      'Inactivity timeout of $minutes minute(s) is below the '
      '${kMinInactivityTimeout.inMinutes}-minute floor — clamping.',
    );
    return kMinInactivityTimeout;
  }
  if (requested > kMaxInactivityTimeout) {
    Logger().w(
      'Inactivity timeout of $minutes minute(s) is above the '
      '${kMaxInactivityTimeout.inHours}-hour ceiling — clamping.',
    );
    return kMaxInactivityTimeout;
  }
  return requested;
}

/// Whether the first account may still be created.
///
/// False when there is no database, and false when the question cannot be
/// asked. An unreachable database must not look like an open commissioning
/// window: the screen behind this flag creates an Engineering account with no
/// credential required beyond reaching the screen, so the failure direction is
/// "closed".
///
/// This is a convenience for the UI, not the guard. The real check runs inside
/// `AccessRepository.createFirstUser`'s transaction.
@Riverpod(keepAlive: true)
Future<bool> firstUserWindowOpen(Ref ref) async {
  final repo = await ref.watch(accessRepositoryProvider.future);
  if (repo == null) return false;
  try {
    return await repo.isUserTableEmpty;
  } on Object catch (e) {
    Logger().w(
      'Could not count app_user — treating the first-user window as closed: '
      '$e',
    );
    return false;
  }
}
