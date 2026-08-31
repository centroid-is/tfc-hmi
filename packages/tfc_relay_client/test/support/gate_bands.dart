/// The timing vocabulary the fault gate asserts against, defined once.
///
/// These are **three separate numbers with three separate jobs**, and the one
/// change to resist here is collapsing them into a single "timeout". They
/// answer different questions and they fail differently when they are wrong:
///
/// - [slack] is measurement tolerance — how far either side of an expected
///   instant a real event may land before the reading is called wrong. It
///   widens a comparison; it never waits for anything.
/// - [recovery] is a liveness budget — how long "the panel came back" is
///   allowed to take. It bounds a wait; a case that used [slack] here would
///   report a healthy reconnect as a failure.
/// - [settle] is the opposite shape: it is spent on purpose, in the one case
///   family where the property is that *nothing* happened. A poll cannot
///   establish an absence, so this is a delay rather than a budget, and using
///   [recovery] here would make every such case five seconds long for no
///   additional evidence.
///
/// Collapse them and the gate keeps passing while it stops measuring: a
/// tolerance used as a budget is a case that waits 20 ms for a reconnect, and a
/// budget used as a tolerance is a case that accepts a five-second round trip
/// as on time.
///
/// **The slack pair is mirrored in `tfc_relay_server/test/support/bands.dart`
/// and must not diverge.** Two packages that disagree about what "on time"
/// means will eventually disagree about whether the gateway is healthy — one
/// side's green and the other side's red, over the same link, with no way to
/// tell which one is describing the plant. The expression below is
/// byte-identical to that file's `slack`; if one moves, the other moves in the
/// same commit and the reason is recorded in both.
///
/// **Why the non-Linux band is nearly four times wider.** The Linux leg is a
/// quiet dedicated runner and 20 ms is the resolution that would notice a
/// mechanism which had quietly stopped working. The hosted macOS and Windows
/// runners are neither quiet nor dedicated, and tens of milliseconds of
/// event-loop jitter there is ordinary. At 20 ms those legs go red about the
/// runner while naming the mode under test, which trains people to re-run CI
/// until it passes — and a real regression then gets re-run too.
///
/// Assert windows, not instants: `lessThan(ceiling)`, never an equality on a
/// duration.
library;

import 'dart:io';

/// The key every scenario case drives. Seeded before the gateway starts, so it
/// is in the address space by the time the client subscribes.
///
/// Shared rather than per-file: the gate's cases are read side by side when a
/// row goes red, and a key that differs by one segment between two files is a
/// difference a reader will spend time on before discovering it means nothing.
const String scenarioKey = 'ST101.CN01.MOT01.setpoint';

/// How far either side of an expected instant a real event may land.
///
/// STATE's Phase 2 handoff bands, and `bands.dart` in the server package is the
/// same two numbers with the same argument: the Linux leg is a quiet dedicated
/// runner, the hosted macOS and Windows ones are neither, and tens of
/// milliseconds of event-loop jitter there is ordinary.
final Duration slack = Platform.isLinux
    ? const Duration(milliseconds: 20)
    : const Duration(milliseconds: 75);

/// The budget for "the panel came back", named once and used everywhere.
///
/// A liveness budget rather than a latency measurement: it has to cover a
/// capped backoff draw, a dial, a handshake and a snapshot.
const Duration recovery = Duration(seconds: 5);

/// Long enough for anything the gateway was going to send to have arrived, on a
/// tick configured at `ServerConfig.minTick`.
///
/// Used only where the property is that *nothing* happened, which is the one
/// shape a poll cannot establish.
const Duration settle = Duration(milliseconds: 400);

/// The one-way delay F13 imposes. A round trip therefore costs twice this.
const Duration f13Latency = Duration(milliseconds: 100);

/// The control deadline F13's client is given: comfortably above the round trip
/// the case imposes, which is the whole point — a link that is merely slow must
/// not read as a link that is gone.
const Duration f13Deadline = Duration(milliseconds: 1500);
