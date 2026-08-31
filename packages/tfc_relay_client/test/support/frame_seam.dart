/// The seam a socket occupies, opened up: inbound frames can be damaged on
/// their way in, and frames can be pushed in that the gateway never sent.
///
/// **Why this exists rather than a ninth fault-proxy mode.** `FaultProxy` moves
/// *bytes* and has eight declared modes; `faultModes` is a closed registry and
/// `tfc_stateman_contract`'s `proxy_core_test.dart` iterates it in both
/// directions, so a mode added for one client test would fail that package's
/// own sweep for want of a mode test beside it. The server package hit the same
/// wall and answered it the same way — `ws_fault_test.dart:31-38` builds a
/// local `_Utf8Corrupter` and says outright that the corrupter is local *and
/// that is deliberate*. This is that instrument for the panel side, one layer
/// up: it works on whole JSON-RPC messages rather than on bytes, which is the
/// layer `MalformedPeer` was written for.
///
/// **Where it sits, and why that is honest.** `MalformedPeer`'s own library doc
/// puts its corruptions "at [channelPair]'s seam — the point a socket would
/// occupy". This class puts them at the point where the socket actually is: the
/// client's dial builds the real `WebSocketChannel`, `wsChannel` frames it as
/// whole strings exactly as production does, and the transform is applied to
/// that stream before `Peer` ever sees it. Everything downstream — the peer,
/// the deadline, the taxonomy, the supervisor's reconnect — is the shipping
/// code path, unmodified. What is simulated is the *peer's* behaviour, which is
/// the only thing a test of a client is entitled to simulate.
///
/// It cannot be done from the other end. Corrupting a message server-side would
/// mean a gateway deliberately lying, and the gateway is a real `RelayServer`
/// in these legs; corrupting it byte-wise in the middle is `_Utf8Corrupter`'s
/// job and lands as *transport death* rather than as a bad message (03-RESEARCH
/// Finding 12: an invalid-UTF-8 payload never reaches our decoder, because RFC
/// 6455 validation sits between the wire and the JSON).
///
/// **Injection is for F18 and nothing else.** [inject] pushes a frame into the
/// client's inbound stream as though the gateway had sent it, which is exactly
/// what F18 describes ("scripted server sends old-epoch `values` after
/// resync"). TCP cannot deliver a frame from a connection that is gone, so the
/// only way to drive that scenario against a real client is to be the peer that
/// sends it. Nothing here rewrites what the client sends; the client's own
/// behaviour is never touched.
library;

import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_client/src/ws_transport.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One dial seam: a real socket, with the inbound direction under a lens.
///
/// Handed to `RemoteStateMan(dial: seam.dial)`. It survives reconnects — the
/// supervisor calls `dial` again and the lens is re-applied to the new socket —
/// which is what lets a case corrupt a frame, lose the link, and inspect what
/// the recovered client did with it.
final class FrameSeam {
  FrameSeam({this.corrupt, this.connectTimeout});

  /// The bound on the dial itself, mirroring [ClientConfig.connectTimeout].
  ///
  /// **Without this the seam is unfaithful to the panel it stands in for, and
  /// the unfaithfulness only shows on the one link that matters.** The real
  /// dial applies `config.connectTimeout` (`remote_state_man.dart:1059`), but a
  /// fixture that passes `dial:` replaces that path wholesale — so every case
  /// driven through this seam had an *unbounded* connect while production had a
  /// bounded one. An ordinary dial completes in milliseconds and nothing
  /// noticed; a dial into a blackholed proxy completes never, and the OS is
  /// what eventually ends it: **75 seconds on macOS** (`SocketException:
  /// Operation timed out`, errno 60 — 06-RESEARCH probe case 4, 07-RESEARCH
  /// trap 19).
  ///
  /// That is why F14b could not be written before this existed: the row's
  /// second leg is "a dial that is never answered", and a leg whose bound comes
  /// from the operating system measures the operating system. Null leaves the
  /// dial unbounded, which is what this seam did before.
  final Duration? connectTimeout;

  /// Applied to every inbound message before the peer sees it, or null to
  /// forward everything verbatim.
  ///
  /// A `MessageCorruption` from `malformed_peer.dart`, so the entries this
  /// package drives are the same thirteen `tfc_stateman_contract` measured
  /// rather than a second, differently-broken set.
  final MessageCorruption? corrupt;

  /// Every message the client received, after the lens, in order.
  ///
  /// Kept so a case can prove its corruption actually landed on something —
  /// an injector that matched nothing is the vacuous pass every fault test is
  /// one typo away from.
  final List<String> inbound = <String>[];

  /// How many connections this seam has served.
  ///
  /// The reconnect observable a case reads when it wants to know the outage
  /// really happened, without reaching into the supervisor's private state.
  int get dials => _dials;
  int _dials = 0;

  StreamController<String>? _toClient;

  /// Dials [uri] for real and returns the attempt with the lens installed.
  ///
  /// The failure path is `connect`'s, including its reason: the same exception
  /// is queued on the stream as well, and an unread error on a socket stream is
  /// the fault that reaches the ambient handler with no frame of this package
  /// in its trace.
  Future<ConnectAttempt> dial(Uri uri) async {
    final ws = WebSocketChannel.connect(uri);
    final timeout = connectTimeout;
    try {
      await (timeout == null ? ws.ready : ws.ready.timeout(timeout));
    } catch (error, stack) {
      ws.stream.listen(null, onError: (Object _) {}, cancelOnError: true);
      unawaited(ws.sink.done.catchError((Object _) => null));
      // Closed as well as drained, which the untimed path never had to do: a
      // dial that *failed* has no socket left to release, but a dial that
      // merely ran out of time still has one in progress, and abandoning it
      // leaks the descriptor for as long as the OS keeps trying — the very
      // 75 seconds this bound exists to avoid, moved from the case's wall
      // clock into F2b's file-descriptor count.
      unawaited(ws.sink.close().catchError((Object _) {}));
      return ConnectFailed(ws, error, stack);
    }
    _dials++;

    final base = wsChannel(ws);
    // A controller rather than a `map`, because injection needs a second
    // source for the same consumer. Not broadcast: `Peer` subscribes once, and
    // a broadcast stream would silently drop everything that arrived before it
    // did — which on this transport is the whole handshake.
    final incoming = StreamController<String>();
    _toClient = incoming;
    base.stream.listen(
      (message) {
        final delivered = corrupt == null ? message : corrupt!(message);
        inbound.add(delivered);
        if (!incoming.isClosed) incoming.add(delivered);
      },
      onError: (Object error, StackTrace stack) {
        if (!incoming.isClosed) incoming.addError(error, stack);
      },
      onDone: () {
        if (!incoming.isClosed) incoming.close();
      },
    );

    return ConnectSucceeded(ws, StreamChannel<String>(incoming.stream, base.sink));
  }

  /// Delivers [message] to the client as though the gateway had sent it.
  ///
  /// A no-op when there is no live connection, so a case that injects during an
  /// outage does not fail on the injector instead of on the property.
  void inject(String message) {
    final incoming = _toClient;
    if (incoming == null || incoming.isClosed) return;
    inbound.add(message);
    incoming.add(message);
  }

  /// The last inbound message satisfying [when], or null if none has arrived.
  ///
  /// Used to capture a genuine frame off the wire and replay it later, which is
  /// the only way to be sure the replayed frame is one the gateway really did
  /// send in a session that is now over — a hand-written stand-in would be
  /// asserting against a frame shape somebody guessed.
  String? lastMatching(bool Function(String message) when) {
    for (final message in inbound.reversed) {
      if (when(message)) return message;
    }
    return null;
  }
}
