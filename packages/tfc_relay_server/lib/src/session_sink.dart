/// The one place in this package that a `Peer`'s output is written, and it
/// does not write to a socket.
///
/// Everything the session sends — RPC answers, write acks, status
/// notifications, the fan-out tick — goes into the session's
/// `ConflatingSendBuffer` priority lane, and the tick engine is what moves the
/// lane onto the wire. That is what makes backpressure measurable: a buffer
/// the server can poll is the only place a "this client cannot keep up"
/// verdict can come from, because `dart:io`'s WebSocket has no
/// `bufferedAmount`, no `flush`, and an `add` that returns void
/// (03-CONTEXT's written-down divergence). A `Peer` writing straight to the
/// socket would be invisible to that policy while contributing to exactly the
/// heap growth it exists to catch.
library;

import 'dart:async';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// A `StreamSink<String>` that funnels frames into [buffer]'s priority lane.
///
/// Handed to a `rpc.Peer` as the write half of its channel (see
/// `ws_channel.dart` for why the channel is built by hand). Frames arrive here
/// already encoded and leave unchanged: the priority lane stores whatever it
/// is given and `drain()` returns it verbatim, so an encode-once body is not
/// re-encoded per client.
final class SessionSink implements StreamSink<String> {
  SessionSink(this.buffer, {this.socket});

  /// Where every outbound frame goes.
  final ConflatingSendBuffer buffer;

  /// The socket's write side — held, and deliberately never written to or
  /// closed from here.
  ///
  /// It is a field rather than an absence so that the question a reader
  /// arrives with ("does this close the socket?") is answered next to the
  /// thing it is asking about, and so a test can inject a recorder and assert
  /// the answer instead of trusting the comment. `WebSocketSink` is a
  /// `StreamSink<dynamic>`, hence the type. Optional because the session-level
  /// tests run over an in-memory channel with no socket at all.
  final StreamSink<dynamic>? socket;

  /// Whether the `Peer` has closed its side of the channel.
  ///
  /// News the session reads during teardown, not an instruction to it.
  bool get closedByPeer => _closedByPeer;
  var _closedByPeer = false;

  /// Errors the `Peer` handed to the write side, kept for diagnosis.
  List<Object> get errors => List.unmodifiable(_errors);
  final _errors = <Object>[];

  final _done = Completer<void>();

  @override
  void add(String event) => buffer.putPriority(event);

  /// Records rather than rethrows.
  ///
  /// An error on the write side means the far end is already gone, which is
  /// the ordinary shape of every disconnect here. Rethrowing would surface as
  /// an unhandled async error attributed to whichever test ran next; the
  /// session learns the socket is gone from its read side, which is the
  /// channel the teardown path is watching.
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _errors.add(error);

  @override
  Future<void> addStream(Stream<String> stream) => throw UnsupportedError(
      'SessionSink takes frames one at a time: binding a stream to it would '
      'be the addStream lock this whole shape exists to avoid, and the '
      'priority lane has no notion of a partially delivered stream');

  /// A deliberate no-op on the socket. **Do not make this close anything.**
  ///
  /// `Peer.close()` closes its channel's sink — twice, as it happens. If that
  /// reached `ws.sink.close()` the socket would already be closed, with no
  /// code, by the time the session tried to close it with
  /// `CloseCodes.backpressureOverrun`; measured in 03-RESEARCH Finding 9,
  /// where the deliberate 4004 arrived only once this stopped closing the
  /// socket. A client that is disconnected without a code cannot tell a
  /// backpressure eviction from a crashed server, and those call for opposite
  /// reconnect behaviour.
  ///
  /// The session closes the socket itself, last, in
  /// `RelaySession.close(code, reason)`.
  @override
  Future<void> close() async => _closedByPeer = true;

  /// Completes when the *session* is finished with the sink.
  ///
  /// Not when the `Peer` closes: a Peer that closed its channel while the
  /// session was still writing its goodbye would otherwise strand the
  /// teardown half-done.
  @override
  Future<void> get done => _done.future;

  /// The session, not the peer, ends this sink's life. Idempotent.
  void finish() {
    if (!_done.isCompleted) _done.complete();
  }
}
