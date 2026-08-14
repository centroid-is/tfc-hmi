/// One `RemoteStateMan`, one real `RelayServer`, one real WebSocket, and the
/// plant behind the server — built **synchronously**, which is the whole
/// difficulty.
///
/// This is `ws_harness.dart`'s `relayFixture` (server package,
/// `test/support/`) rebuilt in this package's test tree, for the reason 04-07
/// already hit and wrote down: another package's `test/` directory is not
/// addressable by any `package:` URI, so the wiring is copied rather than
/// imported. Where a decision was argued there it is re-argued here in one
/// line and the original is cited, because the argument is the value.
///
/// **Why a dial seam and not a port number.** The shared contract suite calls
/// `StateManApi Function() make` synchronously (04-RESEARCH Finding 6): there
/// is nothing to await between "the suite wants an implementation" and "the
/// suite starts driving it". A `RelayServer` binds port 0 on purpose
/// (`relay_server.dart:219-247`) so two servers can share a test process, so
/// its port exists only after an asynchronous bind. Those two facts cannot
/// both be satisfied by a URI known at construction. Rather than guess a port
/// — a guess that collides is a flaky suite blaming the client for the
/// operating system — the fixture hands `RemoteStateMan` a `dial` that waits
/// for the bind and then dials the real port. Everything downstream of the
/// dial is unchanged: one attempt, one `ConnectAttempt`, the supervisor's own
/// backoff, the client's own readiness barrier. A call issued before the
/// server is up waits on the barrier exactly as it does at plant power-on.
///
/// **Levers never touch the wire.** `rpc_names.dart` keeps `setValue`,
/// `failNextWrite`, `setQuality` and the rest off any method table a connected
/// client can reach — putting them on it would be an access-control change
/// wearing a testing convenience (T-04-30). So [RelayServedFake] forwards
/// every `StateManApi` call to the client, over the socket, and routes every
/// plant lever **directly** to the `FakeStateMan` the server sits on. Every
/// lever in this file is a `served.` call and there is no string form of one
/// anywhere.
///
/// **A missing observable throws; it never reads zero.** The rule and its
/// reasoning are `channel_state_man.dart:345-392`'s, and behind a gateway it
/// bites harder than it does over a channel: a `cmd` the plant has never heard
/// of returns an attempt count of 0, and 0 is precisely the answer the
/// no-auto-retry case is hunting for. Handing it over for free would make that
/// case pass on a client that re-sent every unanswered write. See
/// [RelayServedFake.upstreamWriteAttempts].
///
/// What breaks in the plant without this file: nothing directly — but nothing
/// judges `RemoteStateMan` against the same 44 properties `LocalStateMan` is
/// held to either, and CLI-01 is exactly that claim.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/client_config.dart';
import 'package:tfc_relay_client/src/remote_state_man.dart';
import 'package:tfc_relay_client/src/ws_transport.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:tfc_stateman_contract/testing/fake_data_services.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

/// The close a *client* observed, which is the only close worth asserting on
/// for a close the server initiated (`web_socket_channel` #1698).
///
/// Copied verbatim from `ws_harness.dart:73-90`, including its naming rule: a
/// client observation says `closeCode`, the server's own record says
/// `sentCloseCode`, and that one character's case is what lets the phase's
/// text sweep tell intention from observation. Renaming either half here would
/// make this package invisible to that sweep.
final class ClientClose {
  const ClientClose(this.closeCode, this.closeReason);

  /// The code the client's socket observed. Null while the socket is open.
  final int? closeCode;

  /// The reason the client's socket observed.
  final String? closeReason;

  @override
  String toString() =>
      'ClientClose($closeCode, ${closeReason ?? '<no reason>'})';
}

/// Every key the contract suite drives, so the page subscription covers them.
///
/// `RemoteStateMan` subscribes to the keys it is constructed with and to no
/// others — a panel is handed a page, and a client that widened its own
/// subscription on every `listen` would turn one mistyped key into a
/// server-side resubscribe (`remote_state_man.dart:238-249`). The contract
/// suite has no way to declare its keys to `make`, so the fixture declares
/// them here: the literal vocabulary of `tfc_stateman_contract/lib/src`,
/// enumerated rather than guessed.
///
/// A key the suite uses and this set omits does not fail loudly — the value
/// simply never arrives and the case times out on its own budget naming its
/// own property, which is the right failure but an expensive one to diagnose.
/// If a check fails here for "no value ever arrived", check this list first.
const Set<String> contractKeys = <String>{
  'PIPE.connected',
  'ST101.CN01.MOT01',
  'ST101.CN01.MOT01.reset',
  'ST101.CN01.MOT01.running',
  'ST101.CN01.MOT01.setpoint',
  'ST101.CN01.MOT01.speed',
  'ST201.CN04.MOT01',
  'ST201.CN04.MOT01.setpoint',
  'ST201.CN04.MOT01.speed',
  'ST301.CN07.SEN01.temp',
  'ST301.CN17.VLV02.stat',
  'ST301.CN18.VLV01.stat',
  'ST301.CN21.SEN01.temp',
  'ST999.CN99.MOT99.setpoint',
};

/// The station tags the batch cases generate, which no literal sweep can find.
///
/// `store_contract.dart:88-91`, `read_contract.dart:52-55` and
/// `freshness_contract.dart:87-91` each build their own run of
/// `ST{101,201,301}.CN<nn>.MOT01.speed` — the fifty-tag diagnostics page, the
/// batch that must notify k times for k changes, the station mimic that must
/// degrade once rather than per key. The counts differ per case and are
/// private to those files, so the page covers the whole two-digit range for
/// all three stations rather than tracking three private constants across a
/// package boundary.
///
/// 300 keys, against `maxKeysPerSubscribe`'s 2000
/// (`server_config.dart:164`): one subscribe, comfortably inside the limit,
/// and a subscription of a page's realistic order rather than a toy one.
Iterable<String> _stationKeys() sync* {
  for (final station in const ['ST101', 'ST201', 'ST301']) {
    for (var i = 0; i < 100; i++) {
      yield '$station.CN${i.toString().padLeft(2, '0')}.MOT01.speed';
    }
  }
}

/// The client's timing knobs for a contract leg.
///
/// The deadline floor is lowered deliberately and greppably
/// (`client_config.dart`): nobody lowers it in production by accident. The
/// numbers are `remote_state_man_test.dart`'s, which were chosen against this
/// same transport — a tick-quantised round trip with a 50–100 ms floor
/// (04-RESEARCH Finding 8) — so a gateway that accepts a socket and then says
/// nothing fails a case inside that case's own budget instead of stalling it.
ClientConfig contractClientConfig() => ClientConfig(
      controlDeadline: const Duration(seconds: 2),
      writeDeadline: const Duration(seconds: 2),
      freshnessDeadline: const Duration(seconds: 3),
      backoffBase: const Duration(milliseconds: 20),
      backoffCap: const Duration(milliseconds: 200),
      deadlineFloor: const Duration(milliseconds: 50),
    );

/// A real gateway, a real socket, a real client, and the plant behind it all.
///
/// Ordinary drivers want [relayServedFake] and never see this; a case that
/// needs to reach past the client — to close the server, to count sessions —
/// takes the fixture.
final class RelayFixture {
  RelayFixture._(this.served, this.server, this.client, this.api, this.ready);

  /// The reference implementation the gateway is serving. Driveable directly,
  /// which is what lets a case apply a lever no client can see.
  final FakeStateMan served;

  /// The gateway under the client.
  final RelayServer server;

  /// The implementation under test.
  final RemoteStateMan client;

  /// [client] wearing the contract's control surfaces.
  final RelayServedFake api;

  /// Completes when the gateway has bound its port. The client does not wait
  /// for it — the readiness barrier does that — but a case that wants the
  /// port can.
  final Future<void> ready;

  /// The close the client's socket has observed so far.
  ///
  /// Both fields null while it is open. Reported through [ClientClose] rather
  /// than as a bare int so the phase's sweep can tell this from a close the
  /// server recorded having sent.
  ClientClose get observedClose =>
      ClientClose(_lastAttempt?.closeCode, _lastAttempt?.closeReason);

  ConnectAttempt? _lastAttempt;
  var _torn = false;

  /// Releases everything this fixture opened, innermost first, and only once.
  ///
  /// The order is `ws_harness.dart:359-384`'s read from the inside out: the
  /// client (which owns the socket and both its timers), then the server
  /// (whose `close` drains its sessions with a code and then stops its
  /// listener), then the fake, whose freshness watchdog must outlive anything
  /// still draining through it.
  Future<void> teardown() async {
    if (_torn) return;
    _torn = true;

    // A half-built harness is still a harness: wait for the bind to finish
    // before releasing what it managed to open, and do not let its failure
    // stop the release.
    await ready.catchError((Object _) {});

    await client.dispose();
    await server.close();
    await served.dispose();
  }
}

/// Stands up a gateway, a client and a plant over one real WebSocket.
///
/// The `FakeStateMan` arguments are the same ones `channelServedFake`
/// (`channel_harness.dart:60-90`) and `wsServedFake` (`ws_harness.dart:463-480`)
/// take, with the same defaults. The copying is deliberate and is the reason
/// those two files give: a parity sweep runs one registry through several legs,
/// so a defaults difference between them reads as a *transport* difference and
/// sends someone hunting a socket bug that is really a `staleAfter` of 300 ms
/// against one of 500.
RelayFixture relayFixture({
  Duration staleAfter = const Duration(milliseconds: 300),
  Set<String> readOnlyKeys = const {},
  Duration writeLatency = Duration.zero,
  FakeBrowse? browse,
  FakeTimeseries? timeseries,
  FakeHistoryViews? historyViews,
  FakePreferences? preferences,
  ServerConfig? config,
  ClientConfig? clientConfig,
}) {
  final served = FakeStateMan(
    staleAfter: staleAfter,
    readOnlyKeys: readOnlyKeys,
    writeLatency: writeLatency,
    browse: browse,
    timeseries: timeseries,
    historyViews: historyViews,
    preferences: preferences,
  );
  final server = RelayServer(
    api: served,
    config: config ?? ServerConfig(tick: ServerConfig.minTick),
    // Discards rather than `reportToStderr`: several contract cases provoke
    // errors on purpose, and a suite that printed a stack per provoked error
    // would train everyone to scroll past them (`ws_harness.dart:231-235`).
    onError: (_, __, ___) {},
  );

  final ready = server.start();
  // Handled here so a fixture nobody awaited cannot surface as an unhandled
  // async error in an unrelated case, and still delivered to whoever does
  // await `ready`, because `catchError` returns a new future
  // (`ws_harness.dart:298-306`).
  unawaited(ready.catchError((Object _) {}));

  late final RelayFixture fixture;

  final client = RemoteStateMan(
    // Never dialled: the seam below supplies the address, because the port
    // does not exist yet in this event-loop turn. Carried anyway because the
    // supervisor puts it on the operator-facing health line, and a blank
    // there is worse than a placeholder that says what it is.
    uri: Uri.parse('ws://127.0.0.1:0/pending-bind'),
    config: clientConfig ?? contractClientConfig(),
    // The page. Seeded keys included so a subscribe answers with a real
    // snapshot; the contract's own vocabulary so a `setValue` mid-case
    // reaches a key this client is actually watching.
    keys: {...contractKeys, ..._stationKeys(), ...served.keys},
    dial: (_) async {
      await ready;
      final attempt = await connect(Uri.parse('ws://127.0.0.1:${server.port}'));
      fixture._lastAttempt = attempt;
      return attempt;
    },
  );

  final api = RelayServedFake._(served, client);
  fixture = RelayFixture._(served, server, client, api, ready);
  // The suite disposes what `make` returned; that has to release the gateway
  // and the plant too, not just the socket.
  api._teardown = fixture.teardown;

  // Registered at acquisition, so a case that returns early — or fails an
  // assertion before its own teardown line — still releases the descriptors.
  // Idempotent, so the suite's own per-case `dispose` is not a problem.
  addTearDown(fixture.teardown);
  return fixture;
}

/// The driver-facing factory: one gateway-served `StateManApi`, per case.
///
/// ```dart
/// void main() => runStateManContract(relayServedFake);
/// ```
///
/// Returns synchronously and takes no `Future` anywhere in its type, which is
/// the constraint 04-RESEARCH Finding 6 records and the reason the dial seam
/// exists at all. `readOnlyKeys` must be supplied by whichever leg declares a
/// `readOnlyKey`, or the read-only case is dropped and the count silently
/// falls by one.
StateManApi relayServedFake({
  Duration staleAfter = const Duration(milliseconds: 300),
  Set<String> readOnlyKeys = const {},
  Duration writeLatency = Duration.zero,
  FakeBrowse? browse,
  FakeTimeseries? timeseries,
  FakeHistoryViews? historyViews,
  FakePreferences? preferences,
}) =>
    relayFixture(
      staleAfter: staleAfter,
      readOnlyKeys: readOnlyKeys,
      writeLatency: writeLatency,
      browse: browse,
      timeseries: timeseries,
      historyViews: historyViews,
      preferences: preferences,
    ).api;

/// `RemoteStateMan` wearing the contract's test-only control surfaces.
///
/// Every `StateManApi` member forwards to the client and therefore travels
/// over the socket. Every lever goes straight to the `FakeStateMan` behind the
/// gateway. That split is the file's reason to exist: the levers are the plant,
/// and the plant is not something a connected client may drive (T-04-30).
final class RelayServedFake
    implements StateManApi, StateManWriteHarness, StateManDataHarness {
  RelayServedFake._(this._served, this._client);

  /// The plant, reachable directly. Never over the wire.
  final FakeStateMan _served;

  /// The implementation under test.
  final RemoteStateMan _client;

  /// The client, for a case that wants its link state or its debug counters.
  RemoteStateMan get client => _client;

  // ------------------------------------------------ the wire surface, forwarded

  @override
  ValueListenable<DynamicValue> listen(String key) => _client.listen(key);

  @override
  Stream<DynamicValue> subscribe(String key) => _client.subscribe(key);

  @override
  DynamicValue? read(String key) => _client.read(key);

  @override
  Future<DynamicValue> readFresh(String key) => _client.readFresh(key);

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) =>
      _client.readMany(keys);

  @override
  Future<WriteResult> write(String key, Object? value, {Object? expect}) =>
      _client.write(key, value, expect: expect);

  @override
  List<String> get keys => _client.keys;

  @override
  BrowseApi get browse => _client.browse;

  @override
  TimeseriesApi get timeseries => _client.timeseries;

  @override
  HistoryViewApi get historyViews => _client.historyViews;

  @override
  PreferencesApi get preferences => _client.preferences;

  /// Releases the whole fixture, not merely the client.
  ///
  /// The suite disposes the instance `make` handed it, once per case
  /// (`tfc_stateman_contract.dart:180-184`). If that only closed the socket,
  /// every case would leak a bound port and a running tick engine, and the
  /// leg would run out of descriptors long before it ran out of checks.
  /// Idempotent against the fixture's own `addTearDown`.
  @override
  Future<void> dispose() => _teardown?.call() ?? Future<void>.value();

  Future<void> Function()? _teardown;

  // ------------------------------------------- the plant, reached directly

  @override
  void setValue(String key, Object? value,
          {Quality quality = Quality.good, DateTime? sourceTime}) =>
      _served.setValue(key, value, quality: quality, sourceTime: sourceTime);

  @override
  void setValues(Map<String, Object?> values) => _served.setValues(values);

  @override
  void setQuality(String key, Quality quality) =>
      _served.setQuality(key, quality);

  @override
  void dropKey(String key) => _served.dropKey(key);

  @override
  void disconnectUpstream() => _served.disconnectUpstream();

  @override
  void reconnectUpstream() => _served.reconnectUpstream();

  @override
  void failNextWrite(WriteReason reason, {bool unknown = false}) =>
      _served.failNextWrite(reason, unknown: unknown);

  @override
  void clampNextWrite(Object? readback) => _served.clampNextWrite(readback);

  @override
  void stallWrites() => _served.stallWrites();

  @override
  void releaseWrites({bool applied = true}) =>
      _served.releaseWrites(applied: applied);

  @override
  void setReadOnly(String key, bool readOnly) =>
      _served.setReadOnly(key, readOnly);

  @override
  void seedTimeseries(String tableName, List<TimeseriesData> points) =>
      _served.seedTimeseries(tableName, points);

  // ---------------------------------------- observables, off the plant itself

  /// The freshness deadline the *pipeline* declares.
  ///
  /// The gateway's, not the client's: staleness is decided where the value
  /// ages, and what reaches the panel is the quality the gateway already
  /// stamped. A client-side number here would make every freshness case a
  /// measurement of `ClientConfig.freshnessDeadline`, which is the link
  /// watchdog and a different promise entirely.
  @override
  Duration get staleAfter => _served.staleAfter;

  @override
  int get roundTrips => _served.roundTrips;

  @override
  int get statusNotifications => _served.statusNotifications;

  @override
  List<String> get mintedCmds => _served.mintedCmds;

  /// How many times [cmd] reached the plant.
  ///
  /// Read off the plant, because that is where an attempt happens. A
  /// client-side copy would count what this object *sent*, which is exactly
  /// the place a transport-added retry would not be
  /// (`channel_state_man.dart:352-366`).
  ///
  /// The throw is the part that matters behind a gateway. If the plant has
  /// never heard of [cmd] then the id died somewhere between the client and
  /// the device — the gateway minted its own, or the write never left — and
  /// the honest count is *unknown*, not zero. Zero is the exact answer
  /// `a write is never auto-retried` is looking for, so returning it would
  /// make that check pass on a client that re-sent every unanswered write.
  /// `UnsupportedError` names what is missing instead
  /// (`channel_state_man.dart:378-392`).
  @override
  int upstreamWriteAttempts(String cmd) {
    if (!_served.mintedCmds.contains(cmd)) {
      throw UnsupportedError(
          'the plant behind the gateway has never seen cmd "$cmd", so the '
          'number of upstream attempts it made for that id is not a '
          'measurement of anything. It is not zero: zero is what "no retry '
          'happened" looks like, and handing it back for free is how a client '
          'that quietly re-sends every unanswered write passes the '
          'no-auto-retry check. Either the gateway mints its own cmd when it '
          'forwards a write — in which case the client-minted id can never be '
          'correlated and this observable needs a side channel (04-RESEARCH '
          'Finding 4) — or the write never reached the plant at all. Minted '
          'so far: ${_served.mintedCmds}');
    }
    return _served.upstreamWriteAttempts(cmd);
  }
}
