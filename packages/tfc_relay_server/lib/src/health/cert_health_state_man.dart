/// The one health key the gateway produces about *itself*: how many days are
/// left on the certificate it is serving `wss` from.
///
/// **Source: 06-RESEARCH §G**, SEC-04, and 06-CONTEXT decision 3 (a one-year
/// leaf, alarmed at thirty days). The shape is copied from
/// `tfc_relay_client/test/support/client_harness.dart:208-268`'s
/// `_PlantAddressSpace`: a [StateManApi] decorator that overrides the couple of
/// members it answers for and delegates the rest, member by member.
///
/// ## Why this is a key and not a method
///
/// "**There is no health method.** `PIPE.*` keys are subscribable like any
/// plant tag … `listen('PIPE.connected')` is the health API" —
/// `state_man_api.dart:45-49`, repeated in the contract kit's own barrel doc
/// (`:52-57`) and pinned by `api_surface_test.dart:48-51` at 49 interface
/// members. So the producer has to be an api-level overlay: it adds a key,
/// never a member, and the frozen 49 cannot move because of anything in this
/// file.
///
/// (The kit is named here by role rather than by package: `handler_table_test
/// .dart:278-287` greps every line under `lib/` for that package's name,
/// comments included, because an import of a dev-dependency test kit from
/// production code would ship the fakes to the plant.)
///
/// ## What breaks in the plant without it
///
/// The leaf lasts a year. On the morning it lapses, every panel in the plant
/// stops connecting at once and they all stop for the same reason, loudly and
/// simultaneously — `tls_test.dart`'s expired arm is that failure seen from
/// the panel's side, and it is deliberately loud, because a gateway that
/// downgraded instead would be worse. What this file buys is *notice*: the
/// number is an ordinary subscribable tag, AlarmMan can alarm on it like any
/// other, and re-issuing the leaf becomes a Tuesday ticket instead of a
/// Saturday outage.
///
/// ## A second decorator, chained — not a second job on the first
///
/// `PolicyStateMan` is built per session because identity is a property of the
/// session. A certificate is a property of the *server*. So this one is built
/// once by [RelayServer.start] and shared, and the chain is **policy over
/// health over source**: `canSee` then filters a key list that already
/// contains the health key, which is what a future hiding policy would need,
/// and Phase 8 can delete this file without touching the policy.
///
/// ## The Phase 8 merge note
///
/// This overlay exists because Phase 6 needed one health key and **Phase 8
/// owns the `PIPE.*` producer**. When `LocalStateMan` grows the real `PIPE.*`
/// namespace, the `days_to_expiry` computation moves there and this overlay's
/// *health* job goes away. Its *policy* job does not — there is none;
/// `canSee`/`canWrite` stay per session and stay in `PolicyStateMan`, because
/// identity is a property of the session while `LocalStateMan` is one shared
/// instance. Deleting this file is the whole of the merge.
///
/// The obligation runs the other way too: [certDaysToExpiryKey] must be on
/// **Phase 8's HLTH-03 reserved list from the start**.
/// `freshness_contract.dart:60-64` treats `PIPE.` as a reserved *prefix* and
/// Phase 8 will reject a plant keymapping claiming a name inside it. A
/// keymapping that claimed this one would surface as an alarm reading a
/// conveyor speed in days.
///
/// ## Why there is no timer here, and where the hourly cadence actually lives
///
/// 06-09's plan called for an hourly `Timer.periodic` in this file. There is
/// none, and the reason is executable: `teardown_test.dart:523-560` — "the
/// package holds no per-session timer" — walks every file under `lib/src`,
/// treats a non-comment `Timer.periodic(` outside `tick_engine.dart` as an
/// offence and pins the package's repeating-timer count at exactly **1**
/// (03-RESEARCH Finding 8: "a timer that captures a session closure is exactly
/// the ghost 03-11's kill-cycle test hunts").
///
/// So the recompute is on a **deadline, not on a timer** — which is the shape
/// Finding 8 itself chose over per-session timers: a `lastSeenMs` field plus a
/// check on a path that already runs. [_refreshIfDue] is called from every
/// read surface below, and in particular from [keys], which
/// `value_handlers.dart` consults on `read`, `readFresh`, `readMany` and
/// `write` and `session_handlers.dart` consults on `subscribe`. Any request
/// from any panel, after [period] has elapsed, recomputes and notifies.
///
/// Three consequences worth stating rather than discovering:
///
///  * **The value is computed once at [RelayServer.start]**, before anything
///    can subscribe, for the same reason `fake_state_man.dart:93-107` seeds the
///    other five health keys at construction — "a health indicator that reads
///    unknown until the first fault is no indicator at all".
///  * **It is never recomputed more often than [period]**, so an idle-loop of
///    `read` calls cannot turn a health key into a file-system benchmark.
///  * **A gateway with no traffic at all does not recompute.** That is the
///    honest residual of having no timer, and it costs nothing: with no
///    session there is nobody to push to, and the first request after the hour
///    recomputes before it is answered. A deployment that wants the number
///    moved on a schedule of its own calls [refresh] — the same seam
///    `RelayServer.reloadTokens` documents for the credential file, and for
///    the same reason ("the reload cadence is a deployment's business rather
///    than a gateway's").
///
/// ## `inDays` truncates, and an alarm at 30 fires when the value reads 29
///
/// The value is `notAfter.difference(now).inDays`. `Duration.inDays` truncates
/// toward zero, so a certificate with 16.9 days left reads **16** — measured
/// (06-RESEARCH §G.2): a leaf minted `notAfter: now + 17 days` reads back 16.
/// Whoever configures the thirty-day threshold should know that it fires on
/// the day the value first reads 29, not 30. We ship the number; the threshold
/// is AlarmMan's.
///
/// ## Quality, never a zero
///
/// A missing or unparseable chain reads [Quality.errorConfig] with a **null**
/// value. Never 0. A 0 reads as "expires today" and would fire the thirty-day
/// alarm for a misspelled path, sending somebody out to re-issue a certificate
/// that is perfectly fine — and the next real expiry warning is the one they
/// ignore. `errorConfig` is 770, narrowed in Phase 1 to "the source
/// affirmatively said the tag is gone"; the reading here is the same class of
/// statement — the gateway looked, and there is no certificate at that path to
/// report on. Negative values, by contrast, are *readings*: an already-lapsed
/// leaf reads `-3` under good quality, because "three days past" is exactly
/// what an engineer needs to know.
library;

import 'dart:async';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart' show X509Utils;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// How many whole days are left on the gateway's leaf.
///
/// In the reserved `PIPE.` namespace (`fake_state_man.dart:93`,
/// `freshness_contract.dart:60-64`) because it is the pipe reporting on
/// itself. Named as a constant rather than spelled at each site so Phase 8's
/// reserved list and this producer cannot drift apart by a typo.
const certDaysToExpiryKey = 'PIPE.cert.days_to_expiry';

/// The shared source, plus one key the gateway knows and the plant does not.
///
/// Implements [StateManApi] and **adds no interface member**, which is how the
/// frozen 49 stays frozen. Written as explicit member-by-member delegation
/// rather than `noSuchMethod` forwarding, for the reason
/// `policy_state_man.dart:80-87` gives: a forwarder would silently absorb a
/// member added in a later phase, and here a new member is a compile error and
/// therefore a decision.
final class CertHealthStateMan implements StateManApi {
  CertHealthStateMan({
    required this.source,
    required this.chainPath,
    int Function()? nowMs,
    this.period = const Duration(hours: 1),
  }) : _nowMs = nowMs ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// The shared source every session on this gateway is served from.
  final StateManApi source;

  /// The mounted leaf, by path — the same string `TlsConfig.chainPath` holds
  /// and `SecurityContext.useCertificateChain` was given.
  ///
  /// A path and not bytes, deliberately: 06-03's SEC-01 sweep asserts that no
  /// key material is reachable from the configuration, and an overlay that
  /// cached the PEM would be a second copy of the chain living in a long-lived
  /// object for the life of the process. Re-reading a ~1 kB file once an hour
  /// is not a cost worth optimising against that.
  final String chainPath;

  /// How stale the number may get before the next reader pays for a recompute.
  ///
  /// One hour: 06-CONTEXT's "once an hour is plenty" for a value measured in
  /// days, and it is a knob either way. Injectable so a case can drive the
  /// deadline without waiting one out.
  final Duration period;

  /// Wall-clock epoch milliseconds.
  ///
  /// [RelayServer] passes its own `now`, so the certificate clock and the
  /// write-outcome log's clock are the same injectable one and a case can move
  /// the gateway forward in time with arithmetic rather than a sleep.
  final int Function() _nowMs;

  /// One node, one batch entry point — the same store the real
  /// implementations use, so `listen` notifies through production code rather
  /// than through something written for a test (`fake_state_man.dart:110`).
  final _store = ValueStore();

  /// Closers for the streams [subscribe] has handed out that are still open.
  final _closeHandedOutStreams = <Future<void> Function()>{};

  /// When the value was last computed, in epoch ms, or null before the first.
  int? _computedAtMs;

  /// The last computed reading, for [read] and for the notification compare.
  DynamicValue? get value => _store.peek(certDaysToExpiryKey);

  /// Recomputes now, whatever the deadline says.
  ///
  /// Called once by [RelayServer.start] so the value exists before the first
  /// subscribe, and available to a deployment that wants the number moved on a
  /// cadence of its own. Only a genuine change notifies — that is
  /// [ValueStore.applyBatch]'s contract — so an hourly recompute on a value
  /// that ticks once a day pushes once a day.
  void refresh() {
    _computedAtMs = _nowMs();
    _store.applyBatch({certDaysToExpiryKey: _measure()});
  }

  /// Recomputes if [period] has elapsed since the last one.
  ///
  /// On every read surface. See this library's doc for why this and not a
  /// timer.
  void _refreshIfDue() {
    final last = _computedAtMs;
    if (last != null && _nowMs() - last < period.inMilliseconds) return;
    refresh();
  }

  /// Reads the mounted leaf and works out the days.
  ///
  /// `validity` is non-nullable while `tbsCertificate` is nullable — the
  /// upstream field names in `X509CertificateData` are a known trap (trap 14,
  /// and `subjectAlternativNames` is misspelled next door). The null branch is
  /// spelled out rather than `!`-ed so a chain the parser accepts but cannot
  /// describe reads as unknown instead of crashing whichever request happened
  /// to trigger the recompute.
  DynamicValue _measure() {
    try {
      final pem = File(chainPath).readAsStringSync();
      final tbs = X509Utils.x509CertificateFromPem(pem).tbsCertificate;
      if (tbs == null) return _unreadable;
      final now = DateTime.fromMillisecondsSinceEpoch(_nowMs());
      return DynamicValue.of(tbs.validity.notAfter.difference(now).inDays);
    } catch (_) {
      // Deliberately every failure, and deliberately not rethrown: a missing
      // mount, a directory where a file should be, a PEM the parser rejects
      // and a permission error are all the same statement to an operator —
      // this gateway cannot tell you when its certificate runs out — and none
      // of them is a reason to fail the request that happened to be first
      // through the door after the deadline.
      return _unreadable;
    }
  }

  /// The answer that is not a number. Never `0` — see this library's doc.
  static final _unreadable =
      DynamicValue.of(null, quality: Quality.errorConfig);

  // -------------------------------------------------------------------------
  // StateManApi — the thirteen members plus dispose.
  // -------------------------------------------------------------------------

  /// The plant's keys, plus this gateway's one.
  ///
  /// A union, not a replacement. This is also the broadest recompute trigger
  /// in the class: `value_handlers.dart` consults it on `read`, `readFresh`,
  /// `readMany` and `write`, and `session_handlers.dart` on `subscribe`, so
  /// every request on the gateway is a deadline check.
  @override
  List<String> get keys {
    _refreshIfDue();
    return <String>{...source.keys, certDaysToExpiryKey}.toList();
  }

  @override
  ValueListenable<DynamicValue> listen(String key) {
    if (key != certDaysToExpiryKey) return source.listen(key);
    _refreshIfDue();
    return _store.node(certDaysToExpiryKey);
  }

  /// A broadcast view of the same node, never a second source of truth — the
  /// shape and the argument are `fake_state_man.dart:224-261`'s.
  @override
  Stream<DynamicValue> subscribe(String key) {
    if (key != certDaysToExpiryKey) return source.subscribe(key);
    _refreshIfDue();
    final node = _store.node(certDaysToExpiryKey);
    late final StreamController<DynamicValue> controller;
    void push() => controller.add(node.value);
    late final Future<void> Function() close;
    close = () async {
      _closeHandedOutStreams.remove(close);
      await controller.close();
    };
    controller = StreamController<DynamicValue>.broadcast(
      onListen: () {
        node.addListener(push);
        _closeHandedOutStreams.add(close);
      },
      onCancel: () {
        node.removeListener(push);
        _closeHandedOutStreams.remove(close);
      },
    );
    _closeHandedOutStreams.add(close);
    return controller.stream;
  }

  @override
  DynamicValue? read(String key) {
    if (key != certDaysToExpiryKey) return source.read(key);
    _refreshIfDue();
    return value;
  }

  /// A forced round trip is a forced recompute.
  ///
  /// `readFresh` is the method a diagnostics page calls precisely *because* it
  /// doubts the cache (`value_handlers.dart:244-262`), so honouring the
  /// deadline here would answer the doubt with the cached number. Re-reading a
  /// small file is what a round trip costs for this key.
  @override
  Future<DynamicValue> readFresh(String key) async {
    if (key != certDaysToExpiryKey) return source.readFresh(key);
    refresh();
    return value ?? _unreadable;
  }

  /// One round trip for the plant's keys, plus this one answered from here.
  ///
  /// The delegate is skipped entirely when nothing but the health key was
  /// asked for: `readMany` counts round trips as an observable
  /// (`fake_state_man.dart:432-435`), and a round trip nobody needed would be
  /// a number a test is entitled to be surprised by.
  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    if (!keys.contains(certDaysToExpiryKey)) return source.readMany(keys);
    _refreshIfDue();
    final rest = [
      for (final key in keys)
        if (key != certDaysToExpiryKey) key,
    ];
    final answers = rest.isEmpty
        ? <String, DynamicValue>{}
        : {...await source.readMany(rest)};
    answers[certDaysToExpiryKey] = value ?? _unreadable;
    return answers;
  }

  /// Refused: it is a reading of the world, not a setpoint.
  ///
  /// The refusal **reuses the read-only shape** a device gives rather than
  /// inventing one — `not_writable` / `Bad_NotWritable`, byte for byte what
  /// `fake_state_man.dart:835-842` answers for a read-only tag — so nothing on
  /// the panel side needs a special case for a health key, and an operator
  /// gets the sentence they already know. A write that *moved* this value
  /// would let somebody silence the expiry alarm by typing a number into it.
  ///
  /// The id follows the source's own rule (`fake_state_man.dart:659`): the
  /// caller's `cmd` when there is one, a fresh ULID when there is not, because
  /// a `WriteResult` with no id is one `writeStatus` could never match.
  @override
  Future<WriteResult> write(String key, Object? value,
      {Object? expect, String? cmd}) async {
    if (key != certDaysToExpiryKey) {
      return source.write(key, value, expect: expect, cmd: cmd);
    }
    return _refuseWrite(cmd);
  }

  static WriteResult _refuseWrite(String? cmd) => WriteRejected(
      cmd ?? newUlid(),
      const WriteReason('not_writable',
          message: 'the gateway\'s certificate expiry is a reading, not a '
              'setpoint',
          status: 'Bad_NotWritable'));

  @override
  Future<List<WriteResult>> writeStatus(List<String> cmds) =>
      source.writeStatus(cmds);

  /// Refused the same way [write] is, through the same shape.
  ///
  /// An inert handle rather than a throw: `hold_handle.dart:100-109` makes a
  /// handle whose engagement is a [WriteRejected] un-held and un-feedable, and
  /// `value_handlers.dart:654` already knows not to record one. So the hold
  /// path inherits the refusal with no arm of its own.
  @override
  Future<HoldHandle> holdToRun(String key) async {
    if (key != certDaysToExpiryKey) return source.holdToRun(key);
    return HoldHandle(
      key: key,
      engagement: _refuseWrite(null),
      onTick: (_) {},
      onRelease: (_) async => _refuseWrite(null),
    );
  }

  @override
  BrowseApi get browse => source.browse;

  @override
  TimeseriesApi get timeseries => source.timeseries;

  @override
  HistoryViewApi get historyViews => source.historyViews;

  @override
  PreferencesApi get preferences => source.preferences;

  /// Releases this overlay's own store, then delegates.
  ///
  /// Nothing in `RelayServer.close()` calls it, and nothing should — the
  /// source is one instance shared by every session
  /// (`relay_server.dart:216`), so a per-session dispose would take the whole
  /// plant off the air when one panel goes home. The delegation exists for an
  /// embedder that built one of these by hand. What this overlay owns and does
  /// release is its store's listeners and any stream it handed out; it owns no
  /// timer, which is the point of the argument above.
  @override
  Future<void> dispose() async {
    for (final close in _closeHandedOutStreams.toList()) {
      await close();
    }
    _store.dispose();
    await source.dispose();
  }
}
