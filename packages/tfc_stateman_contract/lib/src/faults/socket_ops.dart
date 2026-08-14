/// Raw socket operations the fault modes need and `dart:io` does not offer:
/// a genuine TCP reset, and a way to read an errno off whatever was thrown.
///
/// **`destroy()` is not a reset.** RESEARCH Finding 1 measured it sending a
/// clean FIN on POSIX in every state except one — a peer with data still
/// unread in the *kernel* queue sees ECONNRESET, which is a coincidence of
/// timing rather than a property of the call. The original
/// `tfc_dart/test/proxy.dart` documents `reject()` as RSTing on that basis, and
/// a `killOnce` mode built the same way would test an orderly shutdown while
/// its name promised a cut cable.
///
/// `SO_LINGER{1, 0}` followed by `destroy()` produced a real reset in **50 of
/// 50 runs** (Finding 2). Two measured details constrain [forceReset] and are
/// easy to undo by accident:
///
/// - **It must end in `destroy()`, never `close()`.** Linger set plus
///   `close()` produced a FIN. Verified, both ways.
/// - **The option number is not portable.** `SOL_SOCKET` is, via
///   [RawSocketOption.levelSocket]; `SO_LINGER` is 13 on Linux and `0x0080` on
///   Darwin/BSD.
///
/// **The reset is destructive, and that is a feature with a sharp edge.**
/// Finding 3: an RST arriving while data sits unread causes the kernel to
/// discard that data — `cutMidFrame(137)` delivered 0 of 137 bytes in 50 of 50
/// runs against a peer that was not reading. So a mode that promises "exactly
/// N bytes, then a cut" must cut with FIN and must not call this function. Two
/// primitives, two modes; do not merge them.
///
/// **Capability is probed, never inferred.** Winsock's `struct linger` is
/// believed to use `u_short` fields, making this 8-byte struct wrong on
/// Windows — but that is an assumption (Assumptions Log A3), and an assumption
/// is a poor thing to branch on when the platform will answer the question.
/// `setRawOption` rejects a wrong-size struct loudly with `OSError` errno 22
/// (verified at 2 and 4 bytes; 8 and 16 accepted), so [lingerResetSupported]
/// asks. Nothing in this file branches on which OS it is running under except
/// the option number itself.
library;

import 'dart:io';
import 'dart:typed_data';

/// The `SO_LINGER` option number for this platform.
///
/// Darwin/BSD `0x0080`, Linux 13. Not a capability check — the *number* is
/// known per platform, whereas whether the struct this file writes is the
/// right shape is a question only the kernel can answer. See
/// [lingerResetSupported].
final int _soLinger = Platform.isLinux ? 13 : 0x0080;

/// A `struct linger { int32 l_onoff; int32 l_linger; }` set to reset-on-close.
///
/// `l_onoff = 1` with `l_linger = 0` is the documented way to ask for an
/// abortive close: the kernel discards the send buffer and sends RST instead
/// of going through FIN/FIN-ACK.
Uint8List _lingerZero() {
  final value = Uint8List(8);
  value.buffer.asByteData()
    ..setInt32(0, 1, Endian.host) // l_onoff  = 1
    ..setInt32(4, 0, Endian.host); // l_linger = 0
  return value;
}

/// Cuts [socket] with a TCP reset, so the peer observes ECONNRESET.
///
/// Best-effort by design: a socket that is already dead throws from
/// `setRawOption` ("Socket has been closed"), and that is not worth failing a
/// fault mode over — the connection is gone either way, which is what the
/// caller wanted. What is *not* swallowed is the platform question; call
/// [lingerResetSupported] to find out whether this produces a reset or merely
/// a FIN before writing a test that depends on the difference.
///
/// Destroys unread data at the peer. See the library doc: `cutMidFrame` must
/// not use this.
void forceReset(Socket socket) {
  try {
    socket.setRawOption(
        RawSocketOption(RawSocketOption.levelSocket, _soLinger, _lingerZero()));
  } catch (_) {
    // Already-closed sockets throw here. The reset is moot; the destroy below
    // still puts the socket in the state the caller asked for.
  }
  socket.destroy(); // close() does NOT reset even with linger set — verified.
}

/// The narrowed errno of a socket-facing error, or null if it carries none.
///
/// Finding 9: `Socket.connect` against a resetting listener and
/// `setRawOption` with a wrong-size struct both throw a bare [OSError], which
/// is **not** a subtype of [SocketException]. A catch clause narrowed to
/// [SocketException] therefore does not catch them at all, and the harness
/// crashes at the exact moment it meant to report. Every socket-facing catch
/// in this kit takes `Object` and comes here — a grep of this file for a
/// narrowed clause finds none.
int? errnoOf(Object? error) => switch (error) {
      SocketException(:final osError) => osError?.errorCode,
      OSError(:final errorCode) => errorCode,
      _ => null,
    };

/// Cached outcome of the linger probe: null until it has been asked once.
({bool supported, String? reason})? _lingerProbe;

/// Dedupes concurrent probes, so a suite whose files all ask at load time
/// opens one throwaway socket rather than one per file.
Future<({bool supported, String? reason})>? _lingerProbeInFlight;

/// Why [forceReset] cannot produce a real reset here, or null if it can.
///
/// Null before [lingerResetSupported] has been awaited — nothing has been
/// judged yet, and inventing a reason for an unasked question is how a skip
/// message ends up describing a platform nobody tested. Await the probe, then
/// read this.
String? get lingerResetSkipReason => _lingerProbe?.reason;

/// Whether `SO_LINGER{1, 0}` is accepted by this kernel, asked once.
///
/// Opens a throwaway loopback connection and sets the option on it. A wrong
/// struct size fails with `OSError` errno 22 rather than silently no-op'ing
/// (verified), which is what makes this a real probe rather than a guess
/// dressed up as one.
///
/// Asynchronous because `dart:io` has no synchronous way to obtain a `Socket`
/// — every constructor is a future. Callers that need the answer at test
/// *registration* time await it in `main` before registering the group, which
/// is the shape `test/faults/socket_ops_test.dart` uses.
Future<bool> lingerResetSupported() async {
  final cached = _lingerProbe;
  if (cached != null) return cached.supported;
  return (await (_lingerProbeInFlight ??= _probeLinger())).supported;
}

Future<({bool supported, String? reason})> _probeLinger() async {
  ServerSocket? server;
  Socket? client;
  Socket? accepted;
  try {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final pending = server.first;
    client = await Socket.connect(server.address, server.port);
    accepted = await pending;
    client.setRawOption(
        RawSocketOption(RawSocketOption.levelSocket, _soLinger, _lingerZero()));
    return _lingerProbe = (supported: true, reason: null);
  } catch (error) {
    // Object, not SocketException: setRawOption throws bare OSError here
    // (Finding 9), which is the very case this probe exists to detect.
    final code = errnoOf(error);
    return _lingerProbe = (
      supported: false,
      reason: 'SO_LINGER{1,0} was rejected by this platform'
          '${code == null ? '' : ' (errno $code)'}, so forceReset would send a '
          'FIN rather than a reset and any assertion about half-open recovery '
          'would be measuring an orderly shutdown: $error',
    );
  } finally {
    client?.destroy();
    accepted?.destroy();
    await server?.close();
    _lingerProbeInFlight = null;
  }
}
