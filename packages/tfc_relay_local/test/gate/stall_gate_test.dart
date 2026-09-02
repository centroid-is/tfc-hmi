/// F22 — Gateway stall: a synchronized false disconnect on every client.
///
/// Catalogue §7.9, verbatim on one line each so a `grep -F` finds the same
/// bytes in the registry and here:
///
///   Injection:  SIGSTOP gateway 45 s; 5 clients, 3 upstreams
///   Expect:     every value returns to good quality unaided (Ignition's bug:
///               stuck until hand-toggled); historian marks the gap; clients
///               shown "gateway stalled", not "you disconnected"
///
/// **What this plan delivers, and what it does not.** F22's Expect column is
/// three clauses. This file gates the announcement (F22a), the operator
/// sentence (F22b) and staleness-that-clears-unaided (F22c). The "synchronized
/// false disconnect"/reaper half is 09-08's RED and fix, and the historian
/// "marks the gap" clause is 09-09's `db`-tagged arm — both left outstanding as
/// `OutstandingKind.partial` in `f_row_registry.dart`.
///
/// **The arm letters are delivery order, not clause order.** The plan named
/// these arms a/b/d, reserving c for the reaper clause. The frozen manifest's
/// arm-letter sweep (`gate_b_manifest_test.dart`, "arm letters are unique and
/// gapless") requires the delivered arms to run a, b, c with no gap, so the
/// staleness arm the plan calls F22d is lettered F22c here; the reaper and
/// historian take the next free letters when 09-08 and 09-09 land. The clause
/// identity is preserved in each case's doc and in the outstanding entry.
///
/// **The honest lever, and the two things it decides** (the plan's `<house_
/// rules>`, restated). Whatever is being frozen cannot be the thing observing:
/// `stall_harness.dart` puts the gateway, its three upstreams and a
/// self-driving plant in one isolate this file can `Isolate.pause`, and the
/// panels stay in the test isolate. The capability probe below re-measures on
/// THIS platform what a paused isolate that owns a listening socket does —
/// assumption A3 — because the in-repo pause number (07-RESEARCH §A.4) was
/// taken on a client isolate with no socket.
///
/// **The measured client fact that shapes every arm.** A `RemoteStateMan`'s
/// `viewIsStale` and its reconnect fire on ONE timer
/// (`freshness_watchdog.dart:392` — `_linkWentQuiet` sets `_viewIsStale` and
/// then calls `onQuiet`). So a panel whose `freshnessDeadline` is shorter than
/// the freeze goes stale AND tears its socket down, and on resume it reconnects
/// fresh — it never sees the `gateway_stalled` resync, which the gateway pushes
/// to the session it still holds. A panel whose deadline outlasts the freeze
/// stays connected and receives the announcement but never reports
/// `viewIsStale`. Measured on this harness: a 3 s-deadline panel over a ~10 s
/// pause went `viewIsStale`/`down`/`connecting` at 3 s and recovered unaided on
/// resume with zero complaints; a 30 s-deadline panel stayed `ready` through
/// the pause and recorded the resync. The two are mutually exclusive per
/// panel, so **F22b (the sentence, on connected panels) and F22c (staleness,
/// on short-deadline panels) are different cases**, not one — the plan's "assert
/// them together" is unrepresentable in this client, and the SUMMARY records
/// the measurement. They are still the pair the row is about: stale-and-
/// recovering is the honest state, and it is a different state from being told
/// the gateway stalled — which is itself different from a link-down banner.
///
/// **`PIPE.*` health-key homes** (08-09's F22 exemption). The per-link keys
/// (`PipeKeys.upstreamConnected`/`upstreamState`) are the LOCAL package's,
/// minted by `LocalStateMan` inside the frozen isolate; the per-session keys
/// are the server's. This file reads plant keys and the per-link keys, both of
/// which live in the frozen isolate — so during the freeze they too stop
/// advancing, which is the point. No case here reads a per-session health key.
@TestOn('vm')
@Tags(['gate'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_client/tfc_relay_client.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../support/gate_b_fixture.dart' show gateBPage, until, within;
import '../support/stall_harness.dart';

/// The `reason` a stalled gateway announces itself under — one of
/// `ResyncParams`' documented vocabulary (`messages.dart:455-464`). Spelled
/// here as the wire literal rather than imported: `tfc_relay_server`'s
/// `gatewayStalled` constant is not exported, and the client branches on this
/// exact string.
const gatewayStalled = 'gateway_stalled';

/// The three upstreams F22's row names, and the page each carries.
const _aliases = <String>['ST101', 'ST201', 'ST301'];
const _keysPerAlias = 20;

/// One key every arm watches — a real plant name, first motor of the first
/// device on the first PLC.
const _watch = 'ST101.CN01.MOT01.setpoint';

/// The whole page a panel subscribes to: every plant key across the three
/// upstreams.
Set<String> _page() => <String>{
      for (final alias in _aliases) ...gateBPage(alias, _keysPerAlias),
    };

/// How long the gateway is frozen in the default lane.
///
/// Five seconds: comfortably past the 300 ms `stallThreshold` so the
/// `LagMonitor` announces, past a short panel `freshnessDeadline` so F22c's
/// panels go stale, and short enough that the whole file stays inside the gate
/// budget. The catalogue's 45 s runs behind `RELAY_SOAK` — F22's registry
/// deviation ("SIGSTOP gateway 45 s", 09-CONTEXT ruling 6) records the
/// shortening. Exceeding the gateway's *heartbeatDeadline* is 09-08's reaper
/// concern; these arms set that deadline generously so no reap competes with
/// the announcement they measure.
Duration _freeze() =>
    (Platform.environment['RELAY_SOAK']?.isNotEmpty ?? false)
        ? const Duration(seconds: 45)
        : const Duration(seconds: 5);

/// A raw observing socket: it says hello, subscribes, and records every frame
/// the gateway pushes — so a case can read the `gateway_stalled` resync off the
/// wire, whole, **before** the client fix teaches `RemoteStateMan` to surface
/// it. This is F22a's instrument and its anti-vacuity: the wire carries the
/// fact whether or not any panel decodes it (the pub/sub survey's shape).
final class _WireObserver {
  _WireObserver._(this._socket, this.frames);

  final WebSocket _socket;

  /// Every text frame the gateway sent, in order.
  final List<String> frames;

  final _pending = <int, Completer<Map<String, Object?>>>{};

  /// Stands one up over a raw `dart:io` WebSocket — no `web_socket_channel`,
  /// no `json_rpc_2`, because all this instrument does is send two requests and
  /// record every notification the gateway pushes. Dials [port], says hello,
  /// subscribes [keys] under [sub], and returns once the snapshot has landed.
  static Future<_WireObserver> connect(
      int port, String sub, Set<String> keys) async {
    final socket = await WebSocket.connect('ws://127.0.0.1:$port');
    final frames = <String>[];
    final observer = _WireObserver._(socket, frames);
    socket.listen(
      (Object? data) {
        final frame = '$data';
        frames.add(frame);
        final decoded = jsonDecode(frame);
        if (decoded is Map && decoded['id'] is int) {
          observer._pending
              .remove(decoded['id'])
              ?.complete(decoded.cast<String, Object?>());
        }
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
    addTearDown(() => socket.close().catchError((Object _) => null));

    await observer._request(1, Methods.hello,
        HelloParams(
          protocol: protocolVersion,
          supported: const [protocolVersion],
          client: const PeerInfo('wire-observer', '0.0.1'),
        ).toJson());
    await observer._request(2, Methods.subscribe,
        SubscribeParams(sub: sub, keys: keys.toList()).toJson());
    return observer;
  }

  Future<Map<String, Object?>> _request(
      int id, String method, Map<String, Object?> params) {
    final answer = Completer<Map<String, Object?>>();
    _pending[id] = answer;
    _socket.add(jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }));
    return answer.future.timeout(const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
            'the wire observer got no answer to "$method" within 10 s'));
  }

  /// Every `gateway_stalled` resync this observer has seen, decoded.
  List<ResyncParams> get gatewayStalls => [
        for (final frame in frames)
          if (_resyncOf(frame) case final ResyncParams r)
            if (r.reason == gatewayStalled) r,
      ];

  static ResyncParams? _resyncOf(String frame) {
    final decoded = jsonDecode(frame);
    if (decoded is! Map) return null;
    if (decoded['method'] != Methods.resync) return null;
    final params = decoded['params'];
    if (params is! Map) return null;
    return ResyncParams.fromJson(params.cast<String, Object?>());
  }
}

void main() {
  // ------------------------------------------------------- capability probe
  //
  // The file's first case, a SUPPORTING case that gates no row (registered in
  // gate_b_manifest_test.dart's _supportingCases). It measures on THIS
  // platform that pausing an isolate that OWNS A LISTENING SOCKET stops it
  // serving that socket — assumption A3 — by proving the plant freezes and a
  // command to the gateway times out while paused, then recovers on resume.
  // Re-measured here rather than trusted from F16's client-isolate number
  // (07-RESEARCH §A.4's instruction), and printed so the SUMMARY can paste it
  // per platform.
  test('the stall capability probe (supporting case, gates no row)', () async {
    final gw = await StalledGateway.spawn(
      aliases: _aliases,
      keysPerAlias: _keysPerAlias,
    );

    // A panel with a long deadline, so the probe's own numbers are about the
    // pause and not about the panel's reconnect timer.
    final panel = RemoteStateMan(
      uri: Uri.parse('ws://127.0.0.1:${gw.port}'),
      config: ClientConfig(freshnessDeadline: const Duration(seconds: 30)),
      keys: _page(),
    );
    addTearDown(panel.dispose);
    await until('the probe panel to hold a value',
        () => panel.isReady && panel.read(_watch)?.value != null);

    // Running: the plant advances and the panel sees it move.
    final beforeSweeps = gw.reportsSeen;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final runningSweeps = gw.reportsSeen - beforeSweeps;
    final runningValue = panel.read(_watch)!.value as int;
    await until('the panel to see the plant advance',
        () => (panel.read(_watch)!.value as int) > runningValue);

    gw.pause();
    final atPause = gw.reportsSeen;
    final frozenValue = panel.read(_watch)!.value as int;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final duringPause = gw.reportsSeen - atPause;

    // Asked while frozen, expected to fail by name — the strongest available
    // statement that the isolate's event loop is not turning.
    Object? refusal;
    try {
      await gw.ask('sweeps', budget: const Duration(milliseconds: 400));
    } on Object catch (error) {
      refusal = error;
    }

    // The panel saw nothing new during the pause: its value did not move past
    // where it froze.
    final valueDuringPause = panel.read(_watch)!.value as int;

    gw.resume();
    await until('the plant to advance again after resume',
        () => (panel.read(_watch)!.value as int) > frozenValue);

    print('F22 probe: Isolate.pause of a socket-owning gateway — '
        '$runningSweeps plant sweeps in 400 ms running, $duringPause across '
        '600 ms of pause; ask() while paused: ${refusal.runtimeType}; '
        'panel value frozen at $frozenValue, read $valueDuringPause mid-pause');

    expect(runningSweeps, greaterThan(0),
        reason: 'the plant produced no sweeps even while running, so a frozen '
            'count below would prove nothing');
    expect(duringPause, 0,
        reason: '$duringPause plant sweeps arrived from a paused isolate. '
            'Isolate.pause is F22\'s injection; if the event loop keeps turning '
            'on this platform the freeze injects nothing');
    expect(refusal, isA<TimeoutException>(),
        reason: 'a paused gateway answered a command: $refusal. The command '
            'loop is the event loop, so an isolate that can still reply is not '
            'stopped, and neither is its socket');
    expect(valueDuringPause, frozenValue,
        reason: 'the panel saw a new value ($valueDuringPause, was '
            '$frozenValue) while the gateway was paused — the pause did not '
            'block the socket on this platform, so bytes did not queue in the '
            'kernel as they do under SIGSTOP');
  }, timeout: const Timeout(Duration(minutes: 2)));

  // --------------------------------------------------------------- F22a
  //
  // The announcement arrives and is attributed. Five never-frozen panels watch
  // a gateway freeze; on resume, one gateway_stalled resync per live
  // subscription reaches the wire, carrying an ABSOLUTE stalledMs inside a band
  // around the real pause. Read off a raw observer, so this is GREEN before the
  // client fix: the wire carries the fact even while RemoteStateMan drops it.
  test('F22a: a frozen gateway announces itself — gateway_stalled with an '
      'absolute stalledMs reaches every live subscription', () async {
    final freeze = _freeze();
    final gw = await StalledGateway.spawn(
      aliases: _aliases,
      keysPerAlias: _keysPerAlias,
      // No reap competes with the announcement: the reaper is 09-08's row, and
      // a deadline shorter than the freeze would close these sessions before
      // the resume that announces to them.
      heartbeatDeadline: const Duration(seconds: 15),
    );

    // Five panels that stay connected through the freeze (deadline > freeze),
    // so the announcement has live subscriptions to reach.
    final panels = <RemoteStateMan>[];
    for (var i = 0; i < 5; i++) {
      final client = RemoteStateMan(
        uri: Uri.parse('ws://127.0.0.1:${gw.port}'),
        config: ClientConfig(
            freshnessDeadline: freeze + const Duration(seconds: 20)),
        keys: _page(),
      );
      panels.add(client);
      addTearDown(client.dispose);
    }
    // The wire observer, one subscription, the instrument F22a reads.
    final observer = await _WireObserver.connect(gw.port, 'observer', _page());

    // Anti-vacuity: every panel ready and holding an advancing value before the
    // freeze.
    await until(
        'all five panels and the observer to hold an advancing value',
        () => panels.every((c) => c.isReady && c.read(_watch)?.value != null));
    final before = panels.first.read(_watch)!.value as int;
    await until('the plant to advance before the freeze',
        () => (panels.first.read(_watch)!.value as int) > before);

    gw.pause();
    await Future<void>.delayed(freeze);
    gw.resume();

    // The announcement lands on the wire after resume.
    await within(
        Future(() async {
          while (observer.gatewayStalls.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }),
        'a gateway_stalled resync to reach the observer after the freeze',
        budget: const Duration(seconds: 10));

    final stalls = observer.gatewayStalls;
    final stalledMs = stalls.first.stalledMs;
    print('F22a: freeze ${freeze.inMilliseconds} ms, announced stalledMs='
        '$stalledMs, band [${freeze.inMilliseconds - 1500}, '
        '${freeze.inMilliseconds + 4000}], resyncs for observer='
        '${stalls.length}');

    expect(stalls, hasLength(1),
        reason: 'the observer holds one subscription and heard '
            '${stalls.length} gateway_stalled resyncs. One freeze is one '
            'announcement per subscription — Finding 10 measured no catch-up '
            'burst, so a debounce here would guard a storm measured not to '
            'happen');
    expect(stalledMs, isNotNull,
        reason: 'a gateway_stalled resync carried no stalledMs — the number is '
            'the whole content of the operator sentence F22b builds');
    expect(stalledMs, greaterThan(freeze.inMilliseconds - 1500),
        reason: 'the announced stalledMs $stalledMs is far below the '
            '${freeze.inMilliseconds} ms freeze: it must be the ABSOLUTE gap, '
            'not the excess over the tick period, because a panel renders it '
            'as "the plant view was frozen for N ms"');
    expect(stalledMs, lessThan(freeze.inMilliseconds + 4000),
        reason: 'the announced stalledMs $stalledMs is implausibly far above '
            'the ${freeze.inMilliseconds} ms freeze; the band tolerates '
            'scheduling slack on a loaded runner but not a wrong number');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // --------------------------------------------------------------- F22b
  //
  // The panel says stalled, not disconnected. Same freeze as F22a, on connected
  // panels — but read off RemoteStateMan's own surface, the one an operator
  // sentence is built from, never off a log line. THIS ARM IS THE RED: before
  // the client fix `RemoteStateMan` has no stallReason/stalledMs surface at
  // all, so this case does not compile — the RED names the missing surface.
  // 09-07 task 3 adds the getters; this file is byte-identical between the RED
  // and the GREEN, which is task 3's own acceptance criterion.
  //
  // Paired with F22c by argument, not by structure (see the library doc): the
  // sentence here and the staleness there are the two halves of "stale-and-
  // explained, not link-down", and they need opposite freshnessDeadlines, so
  // they cannot share a panel.
  test('F22b: clients shown "gateway stalled", not "you disconnected" — the '
      'reason and duration are readable from an operator surface', () async {
    final freeze = _freeze();
    final gw = await StalledGateway.spawn(
      aliases: _aliases,
      keysPerAlias: _keysPerAlias,
      heartbeatDeadline: const Duration(seconds: 15),
    );

    final panels = <RemoteStateMan>[];
    for (var i = 0; i < 5; i++) {
      final client = RemoteStateMan(
        uri: Uri.parse('ws://127.0.0.1:${gw.port}'),
        config: ClientConfig(
            freshnessDeadline: freeze + const Duration(seconds: 20)),
        keys: _page(),
      );
      panels.add(client);
      addTearDown(client.dispose);
    }

    await until('all five panels to hold an advancing value',
        () => panels.every((c) => c.isReady && c.read(_watch)?.value != null));
    final before = panels.first.read(_watch)!.value as int;
    await until('the plant to advance before the freeze',
        () => (panels.first.read(_watch)!.value as int) > before);

    gw.pause();
    await Future<void>.delayed(freeze);
    gw.resume();

    // Every panel can say WHY it went quiet, in a sentence, from a surface a
    // widget binds to — not from a link-down banner and not from a log.
    await within(
        Future(() async {
          while (!panels.every((c) => c.stallReason == gatewayStalled)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }),
        'every panel to surface reason gateway_stalled after the freeze',
        budget: const Duration(seconds: 10));

    for (final panel in panels) {
      expect(panel.stallReason, gatewayStalled,
          reason: 'a panel could not say the gateway stalled; that is the '
              'defect Ruling 5a permits fixing — the wire carried the reason '
              'and connection_supervisor decoded and dropped it');
      expect(panel.stalledMs, isNotNull,
          reason: 'the panel has a stall reason but no duration, so it can say '
              '"stalled" but not "for how long" — half the sentence');
      expect(panel.stalledMs, greaterThan(freeze.inMilliseconds - 1500),
          reason: 'the surfaced stalledMs ${panel.stalledMs} is not the '
              'absolute gap the gateway sent; a client that recomputed it from '
              'its own clock would drift');
      // stale-and-explained is not link-down: the connection is up.
      expect(panel.linkState, LinkState.ready, // window-exempt: the within() above waited for every panel to surface gateway_stalled while still connected — this re-asserts the link stayed up through that completed event
          reason: 'the panel that was told the gateway stalled also shows the '
              'link down — the two states F22b keeps apart have collapsed '
              'into one');
    }
    print('F22b: five panels surface reason=gateway_stalled, stalledMs='
        '${[for (final p in panels) p.stalledMs]}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  // --------------------------------------------------------------- F22c
  //
  // Staleness is honest, and it clears unaided (the plan's F22d clause; see the
  // library doc on the letter). During the freeze the short-deadline panels
  // receive nothing, so they go stale — viewIsStale true, per-subscription
  // staleness set — and after the resume every value returns to good quality
  // with NOBODY TOUCHING ANYTHING: no operator toggle, no manual resubscribe,
  // no reconnect initiated by the test. This is the anti-Ignition clause
  // (their bug: stuck until hand-toggled). GREEN before task 3 — no product
  // change is needed for staleness to be honest.
  test('F22c: every value returns to good quality unaided — the panels go '
      'honestly stale during the freeze and recover on their own', () async {
    final freeze = _freeze();
    final gw = await StalledGateway.spawn(
      aliases: _aliases,
      keysPerAlias: _keysPerAlias,
    );

    // Short deadline, so the panels detect the silence and go stale during the
    // freeze — the whole subject of this clause.
    final panels = <RemoteStateMan>[];
    for (var i = 0; i < 5; i++) {
      final client = RemoteStateMan(
        uri: Uri.parse('ws://127.0.0.1:${gw.port}'),
        config: ClientConfig(freshnessDeadline: const Duration(seconds: 2)),
        keys: _page(),
      );
      panels.add(client);
      addTearDown(client.dispose);
    }

    await until('all five panels to hold an advancing value',
        () => panels.every((c) => c.isReady && c.read(_watch)?.value != null));
    final before = panels.first.read(_watch)!.value as int;
    await until('the plant to advance before the freeze',
        () => (panels.first.read(_watch)!.value as int) > before);
    final frozenValues = [for (final c in panels) c.read(_watch)!.value as int];

    gw.pause();

    // Every panel goes stale during the freeze — read inside a window, never at
    // an instant (the freeze is longer than the deadline, so this is a state
    // the panels reach, not a scheduler race).
    final toStale = Stopwatch()..start();
    await within(
        Future(() async {
          while (!panels.every((c) => c.viewIsStale)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }),
        'every panel to go viewIsStale during the freeze',
        budget: const Duration(seconds: 8));
    toStale.stop();
    // The per-subscription verdict is set too: this is the plant's silence, not
    // just the socket's.
    for (final panel in panels) {
      expect(panel.staleSubscriptions, isNotEmpty, // window-exempt: the within() above waited for every panel to reach viewIsStale during the freeze — this re-asserts the per-subscription verdict of that same completed event
          reason: 'a panel is viewIsStale but names no stale subscription, so '
              'it cannot tell the operator WHICH page stopped');
    }

    await Future<void>.delayed(freeze);
    gw.resume();

    // Recovery is unaided: the test does nothing. Every value comes back good,
    // past where it froze, and the staleness clears.
    final toClear = Stopwatch()..start();
    await within(
        Future(() async {
          while (!panels.every((c) =>
              !c.viewIsStale &&
              c.isReady &&
              (c.read(_watch)?.value as int? ?? -1) > frozenValues.first)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }),
        'every panel to return to good quality with no operator action',
        budget: const Duration(seconds: 15));
    toClear.stop();

    print('F22c: freeze ${freeze.inMilliseconds} ms, panels went stale in '
        '${toStale.elapsedMilliseconds} ms, cleared unaided in '
        '${toClear.elapsedMilliseconds} ms after resume; froze at '
        '$frozenValues, now advancing');

    for (final panel in panels) {
      expect(panel.viewIsStale, isFalse, // window-exempt: the within() above waited for every panel to clear staleness and advance past the freeze value — this re-asserts consistency with that completed recovery event
          reason: 'a panel stayed stale after the gateway came back and kept '
              'delivering — Ignition\'s exact bug, stuck until hand-toggled, '
              'reproduced here');
      expect(panel.read(_watch)!.value as int,
          greaterThan(frozenValues.first),
          reason: 'the value did not advance past where it froze, so the plant '
              'view has not actually recovered');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
