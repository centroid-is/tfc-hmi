/// The Session card on the access admin page: the inactivity timeout as a
/// knob instead of a hand-edited preference.
///
/// The value it edits — `access.inactivity_timeout_minutes` — always
/// existed and always worked; what was missing was any surface an
/// administrator could reach it from. It is **device-local on purpose**
/// (`inactivityTimeout`'s own doc says why: stations sharing one database
/// keep their own pace), so the card says "this station" out loud rather
/// than letting the edit read as fleet-wide.
///
/// ## Why the audit row is written here
///
/// Every shared-config write goes through `GuardedPreferences` and records
/// itself. A device-local write does not — there is no guard on that store —
/// and the inactivity timeout is exactly the kind of change the trail must
/// not miss: it is the width of the elevation window, and quietly widening
/// it on one panel is invisible everywhere else. So the section records one
/// row per change itself, through the same sink the guards use, with the
/// same no-op suppression: an unchanged value writes nothing.
///
/// ## Applying live
///
/// `AccessSessionController.build` watches `inactivityTimeoutProvider`, so
/// invalidating it after the write re-arms the monitor with the new value —
/// no restart, and the currently signed-in session keeps its identity (the
/// controller re-resolves it from the persisted session).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_access/tfc_access.dart';

import '../providers/access.dart';
import '../providers/access_policy.dart';
import '../providers/preferences.dart';
import '../providers/state_man.dart';

/// The card, for tests to find.
const Key kAccessSessionSectionKey = Key('access-session-section');

/// The minutes field.
const Key kAccessSessionTimeoutFieldKey = Key('access-session-timeout-field');

/// The save affordance.
const Key kAccessSessionSaveKey = Key('access-session-save');

/// The never-expire switch row.
const Key kAccessSessionNeverExpireSwitchKey =
    Key('access-session-never-expire');

/// The card's title.
const String kAccessSessionTitle = 'Session';

/// What the number means, and its scope. "This station" is load-bearing:
/// the value is device-local and the sentence is what stops the edit from
/// reading as fleet-wide.
const String kAccessSessionExplainer =
    'Signed-in sessions end after this much inactivity — on this station '
    'only. Each station keeps its own value.';

/// The switch's label and its consequence, in one breath. "Until an
/// explicit sign-out" is the load-bearing half: it is what the panel-PC
/// commissioning wants and what a shared human panel must hear as a warning.
const String kAccessSessionNeverExpireLabel = 'Sessions never expire';
const String kAccessSessionNeverExpireNote =
    'For panels that live signed in as a station account. Anyone at this '
    'panel keeps the signed-in permissions until an explicit sign-out.';

/// Shown when the input cannot be saved.
final String kAccessSessionRangeError =
    'Enter ${kMinInactivityTimeout.inMinutes} to '
    '${kMaxInactivityTimeout.inMinutes} minutes.';

/// The parts of the audit row only a provider `Ref` can supply — the same
/// bridge shape `tagRefusalSinkProvider` is, because the same two types
/// ([RefAuditSink], `stationNameProvider`) sit behind it. Overridden whole
/// in tests.
final accessSessionAuditProvider =
    Provider<({String station, AuditSink audit})>(
  (ref) => (
    station: ref.read(stationNameProvider),
    audit: RefAuditSink(ref),
  ),
);

/// The stored minutes, independent of the disable flag: what the field
/// shows under a greyed expiry, because it is what turning the switch back
/// off restores.
final _storedMinutesProvider = FutureProvider<int?>((ref) => ref
    .watch(localPreferencesProvider)
    .getInt(kAccessInactivityMinutesPrefKey));

/// One card: the effective timeout in a bounded minutes field, saved on the
/// button or the keyboard's done action.
class AccessSessionSection extends ConsumerStatefulWidget {
  const AccessSessionSection({super.key});

  @override
  ConsumerState<AccessSessionSection> createState() =>
      _AccessSessionSectionState();
}

class _AccessSessionSectionState extends ConsumerState<AccessSessionSection> {
  final TextEditingController _minutes = TextEditingController();

  /// Whether [_minutes] has been seeded from the provider. Once the operator
  /// can have typed, the provider resolving again must not clobber the field.
  bool _seeded = false;

  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _setNeverExpires(bool next) async {
    final prefs = ref.read(localPreferencesProvider);
    final current =
        await prefs.getBool(kAccessInactivityDisabledPrefKey) ?? false;
    if (next == current) return;
    await prefs.setBool(kAccessInactivityDisabledPrefKey, next);
    await _recordChange(
      itemKey: kAccessInactivityDisabledPrefKey,
      oldValue: current.toString(),
      newValue: next.toString(),
    );
    ref.invalidate(inactivityTimeoutProvider);
  }

  Future<void> _recordChange({
    required String itemKey,
    required String oldValue,
    required String newValue,
  }) async {
    final bridge = ref.read(accessSessionAuditProvider);
    final session =
        ref.read(accessSessionProvider).valueOrNull ?? kSessionWhileLoading;
    try {
      await bridge.audit.record(AuditRecord(
        at: DateTime.now(),
        who: session.user?.username ?? 'anonymous',
        station: bridge.station,
        roleName: session.roleName,
        surface: AccessSurface.pref.wireName,
        itemKey: itemKey,
        member: null,
        oldValue: oldValue,
        newValue: newValue,
        groupRequired: AccessGroup.operate.name,
        allowed: true,
        actionId: newActionId(),
      ));
    } on Object {
      // A trail that is down is logged loudly elsewhere; it must not undo a
      // saved change or leave the operator staring at a control that
      // "failed".
    }
  }

  Future<void> _save() async {
    final parsed = int.tryParse(_minutes.text.trim());
    if (parsed == null ||
        parsed < kMinInactivityTimeout.inMinutes ||
        parsed > kMaxInactivityTimeout.inMinutes) {
      // The provider clamps as a backstop against a hand-edited store; the
      // knob refuses instead, because it can still ask for a better number.
      setState(() => _error = kAccessSessionRangeError);
      return;
    }
    setState(() => _error = null);

    // Null when expiry is disabled — unreachable from the UI (the field is
    // greyed) but not from a race; the stored minutes are then the honest
    // "old".
    final effective = await ref.read(inactivityTimeoutProvider.future);
    final oldMinutes = effective?.inMinutes ??
        await ref
            .read(localPreferencesProvider)
            .getInt(kAccessInactivityMinutesPrefKey) ??
        kDefaultInactivityTimeout.inMinutes;
    if (parsed == oldMinutes) return;

    final prefs = ref.read(localPreferencesProvider);
    await prefs.setInt(kAccessInactivityMinutesPrefKey, parsed);

    // The row before the invalidate, same order the guards use: the evidence
    // of the change must exist even if the re-arm never happens.
    await _recordChange(
      itemKey: kAccessInactivityMinutesPrefKey,
      oldValue: oldMinutes.toString(),
      newValue: parsed.toString(),
    );

    ref.invalidate(inactivityTimeoutProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = ref.watch(inactivityTimeoutProvider);

    // Resolved (with a value or the disabled null) versus still loading:
    // the switch and the field both seed from the answer, not its absence.
    final resolved = effective.hasValue;
    final neverExpires = resolved && effective.value == null;

    final stored = ref.watch(_storedMinutesProvider);
    if (!_seeded && resolved && stored.hasValue) {
      // Under a disabled expiry the effective answer is null; the field then
      // shows the STORED minutes — the number the switch restores — and only
      // a station that never chose one shows the default.
      final minutes = effective.value?.inMinutes ??
          stored.value ??
          kDefaultInactivityTimeout.inMinutes;
      _minutes.text = minutes.toString();
      _seeded = true;
    }

    return Card(
      key: kAccessSessionSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kAccessSessionTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(kAccessSessionExplainer, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: kAccessSessionTimeoutFieldKey,
                    controller: _minutes,
                    enabled: !neverExpires,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Inactivity timeout',
                      suffixText: 'minutes',
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  key: kAccessSessionSaveKey,
                  onPressed: neverExpires ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: kAccessSessionNeverExpireSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: Text(kAccessSessionNeverExpireLabel,
                  style: theme.textTheme.bodyMedium),
              subtitle: Text(kAccessSessionNeverExpireNote,
                  style: theme.textTheme.bodySmall),
              value: neverExpires,
              onChanged: resolved ? (next) => _setNeverExpires(next) : null,
            ),
          ],
        ),
      ),
    );
  }
}
