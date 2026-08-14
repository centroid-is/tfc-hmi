/// A partial frame, delivered byte-exactly, whether or not the peer was
/// reading at the moment the connection was cut.
///
/// **The measurement this file exists for.** RESEARCH Finding 3 built
/// `cutMidFrame(137)` on a reset — `SO_LINGER{1, 0}` then `destroy()`, the same
/// primitive `killOnce` needs — and measured it twice, against a peer that was
/// actively reading and against a peer whose subscription was paused:
///
/// | Cut with | Peer reading | Peer paused |
/// |---|---|---|
/// | RST (`SO_LINGER{1, 0}` + destroy) | 137/137 bytes, 50 of 50 runs | **0/137 bytes, 50 of 50 runs** |
/// | FIN (`close()`)                   | 137/137 bytes, 50 of 50 runs | 137/137 bytes, 50 of 50 runs |
///
/// The FIN version held across N ∈ {1, 64, 4096, 200000}. The reset version is
/// the obvious implementation, it compiles, and it passes any test written
/// against an actively-reading fake — which is every test somebody writes
/// first. So the paused arm below is not a thoroughness arm. It is the only
/// thing standing between this mode and a lever that silently delivers nothing
/// in the exact scenario it was built for: a client that is momentarily busy
/// when the link is cut.
///
/// **Why the reset discards the bytes.** An arriving RST makes the kernel drop
/// whatever is sitting in the peer's receive queue unread. A peer that was
/// reading had already drained it, so it kept the bytes by luck of timing; a
/// peer that was paused had not, so it lost all of them. Nothing about the
/// proxy differs between those two runs, which is why no assertion on the
/// proxy's own state could tell them apart and every assertion here is on what
/// the peer received.
///
/// **The two modes are deliberately built on different primitives.**
/// `killOnce` must reset (`test/faults/kill_once_test.dart`); this one must
/// FIN. Merging them saves four lines and breaks one of the two, invisibly.
@Tags(['faults'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/faults.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

/// The cut sizes every arm is run at.
///
/// Finding 3's sweep, with 137 kept as the headline because it is the number
/// the measurement was taken at and it is not a round one — a mode that
/// happened to cut on a buffer boundary would pass at 4096 and fail here.
/// 1 catches an off-by-one at the very first byte; 4096 sits on a page; 200000
/// is several socket buffers and forces the cut to fall inside a chunk that
/// was already being written.
const _cutSizes = <int>[1, 137, 4096, 200000];

/// How many bytes beyond the cut the server sends.
///
/// The cut has to be *mid* frame or the mode is untested: if the peer were
/// only ever offered n bytes, a proxy that forwarded everything and closed
/// would pass every assertion in this file. The overshoot is what makes
/// `received.length == n` a statement about the cut rather than about the
/// payload.
const _overshootBytes = 512;

/// How long the paused arm leaves its peer not reading.
///
/// This is the fault being staged, not a wait for the proxy to get around to
/// something: the scenario *is* a client that stops reading for a quarter of a
/// second and comes back. The assertions afterwards are all gated on real
/// events — the stream ending, `within()` on that — so lengthening or
/// shortening this window changes which state the peer was in when the cut
/// landed and never whether the test synchronises correctly.
const _notReadingWindow = Duration(milliseconds: 250);

/// How long the peer's stream is given to end after the cut.
///
/// Generous, because the largest arm pushes 200 KiB through the proxy in both
/// directions with a flush per chunk, and because the paused arm spends a
/// quarter of a second not reading on purpose.
const _endBudget = Duration(seconds: 20);

/// How long a loopback connect is given.
const _connectBudget = Duration(seconds: 2);

/// What the client writes at a time.
const _chunkBytes = 64 * 1024;

/// What the peer saw: the bytes that arrived, and how the stream ended.
///
/// [error] is null for a clean `onDone`, which is the outcome this mode
/// promises. A reset shows up here as a non-null [SocketException] — and, on
/// the paused arm, with [received] empty.
typedef _Outcome = ({Uint8List sent, Uint8List received, Object? error});

void main() {
  group('the peer is actively reading', () {
    for (final n in _cutSizes) {
      test('cutMidFrame($n) delivers exactly $n bytes and then ends', () async {
        final outcome = await _cutRun(n: n, pausePeer: false);

        expect(outcome.received.length, n,
            reason: 'the peer was offered ${n + _overshootBytes} bytes and the '
                'cut was set at $n, so anything else means the byte count is '
                'not being honoured: more, and the cut is late or counts '
                'chunks rather than bytes; fewer, and the close raced the '
                'flush');
        expect(_firstDifference(outcome.received, _prefix(outcome.sent, n)), -1,
            reason: 'the peer must receive the *first* $n bytes in order — a '
                'cut that dropped a chunk and delivered a later one would '
                'still count to $n and would still be wrong');
        expect(outcome.error, isNull,
            reason: 'the mode promises a partial frame followed by an orderly '
                'end, so the peer must see onDone; an error here means the '
                'connection was reset rather than closed, and the bytes this '
                'arm counted survived only by luck of the peer having already '
                'read them (Finding 3)');
      });
    }
  });

  group('the peer subscription is paused across the cut', () {
    for (final n in _cutSizes) {
      test('cutMidFrame($n) still delivers exactly $n bytes', () async {
        final outcome = await _cutRun(n: n, pausePeer: true);

        expect(outcome.received.length, n,
            reason: 'this is the arm the mode exists for. Finding 3 measured '
                'the reset-based cut delivering 0 of 137 bytes in 50 of 50 '
                'runs against a peer that was not reading, because an RST '
                'makes the kernel discard the peer\'s unread receive queue — '
                'while the same implementation delivered 137 of 137 in 50 of '
                '50 runs against a peer that was. So a cut that passes only '
                'the reading arm is not a slightly weaker mode: it silently '
                'delivers nothing in the one scenario a partial frame is '
                'injected for, and its own test says it works');
        expect(outcome.received, _prefix(outcome.sent, n),
            reason: 'the paused peer must receive the same first $n bytes the '
                'reading peer did — the pause changes when they are read, not '
                'which ones arrive');
        expect(outcome.error, isNull,
            reason: 'RESEARCH Finding 3: the reset-based version of this mode '
                'made the paused peer see ECONNRESET instead of onDone in 50 '
                'of 50 runs. An error here is that implementation come back');
      });
    }
  });
}

/// Runs one cut and reports what the peer saw.
///
/// The lever is set on an already-open connection, because that is how every
/// scenario reaches for it: the cut interrupts a conversation in progress
/// rather than being configured before the client exists.
Future<_Outcome> _cutRun({required int n, required bool pausePeer}) async {
  final proxy = await _proxyToEcho();
  final client = await _connect(proxy.port);
  final payload = _pattern(n + _overshootBytes);

  final received = BytesBuilder(copy: false);
  final ended = Completer<Object?>();
  final subscription = client.listen(
    received.add,
    onDone: () {
      if (!ended.isCompleted) ended.complete(null);
    },
    onError: (Object error) {
      if (!ended.isCompleted) ended.complete(error);
    },
  );
  addTearDown(subscription.cancel);

  if (pausePeer) subscription.pause();

  proxy.cutMidFrame(n);

  // Not awaited: on the largest arm the proxy stops reading this direction
  // once the cut has fired, so the tail of the payload may never be taken.
  // The bytes that matter are the ones already on their way back, and the
  // assertions are about those.
  unawaited(_write(client, payload));

  if (pausePeer) {
    await Future<void>.delayed(_notReadingWindow);
    subscription.resume();
  }

  final error = await within(
    ended.future,
    'the peer\'s stream ended after a cutMidFrame($n)'
    '${pausePeer ? ' across a paused subscription' : ''}',
    budget: _endBudget,
  );
  return (sent: payload, received: received.takeBytes(), error: error);
}

/// Writes [payload] with a flush per chunk.
///
/// Gated like the delay line's own writer, so the rig applies pressure to the
/// proxy instead of buffering the payload in its own sink — and so a failure
/// here is the proxy's, not `dart:io`'s.
Future<void> _write(Socket socket, Uint8List payload) async {
  try {
    for (var offset = 0; offset < payload.length; offset += _chunkBytes) {
      final end = min(offset + _chunkBytes, payload.length);
      socket.add(Uint8List.sublistView(payload, offset, end));
      await socket.flush();
    }
  } catch (_) {
    // The proxy cut the connection while this was still writing, which is the
    // whole point of the mode. Object, not SocketException: Finding 9.
  }
}

/// A proxy in front of a fresh echo server, torn down at the end of the test.
Future<FaultProxy> _proxyToEcho() async {
  final echo = await _echoServer();
  final proxy = FaultProxy(targetPort: echo.port);
  await proxy.start();
  addTearDown(proxy.shutdown);
  return proxy;
}

/// A loopback echo server that gates its own writes and destroys what it
/// accepted.
Future<ServerSocket> _echoServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  final accepted = <Socket>[];
  addTearDown(() {
    for (final socket in accepted) {
      socket.destroy();
    }
  });

  final accepts = server.listen((socket) {
    accepted.add(socket);
    unawaited(socket.done.catchError((Object _) => socket));
    late final StreamSubscription<Uint8List> echoing;
    echoing = socket.listen(
      (data) {
        socket.add(data);
        // The same gate the delay line uses, for the same reason: an echo
        // server that buffers without limit reproduces Finding 7 in the rig.
        echoing.pause(socket.flush().catchError((Object _) {}));
      },
      onDone: socket.destroy,
      onError: (Object _) => socket.destroy(),
    );
  });
  addTearDown(accepts.cancel);
  return server;
}

/// Connects to [port] on loopback, destroyed at the end of the test.
Future<Socket> _connect(int port) async {
  final socket = await within(
    Socket.connect(InternetAddress.loopbackIPv4, port),
    'the client reached the proxy on port $port',
    budget: _connectBudget,
  );
  addTearDown(socket.destroy);
  unawaited(socket.done.catchError((Object _) => socket));
  return socket;
}

/// A deterministic pattern whose shifts are visible.
Uint8List _pattern(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31 + i ~/ 251) & 0xff;
  }
  return bytes;
}

/// The first [n] bytes of [payload], as an independent list.
///
/// A copy rather than a view, so a failure prints the bytes rather than a
/// description of a window onto a 200 KiB buffer.
Uint8List _prefix(Uint8List payload, int n) => Uint8List.fromList(
    payload.sublist(0, n < payload.length ? n : payload.length));

/// The index of the first differing byte, or -1 when the lists match.
int _firstDifference(List<int> a, List<int> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : shared;
}
