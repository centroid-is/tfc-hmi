/// The five ways a hold-to-run implementation lets a machine run without
/// somebody holding it.
///
/// `broken_write.dart` covers implementations that lie about a write that has
/// already happened. These are the same family and, on a jog button, the worse
/// half of it: a write that lies is wrong about one movement of the plant, and
/// a deadman that lies is wrong about *whether the movement is still under
/// anybody's control*. The safety property here is stated backwards from every
/// other one in the suite — what must happen is that a counter **stops** — so
/// every bug in this file looks, from the API surface, exactly like a system
/// working.
///
/// All five have shipped, in this shape, in real control software:
///
///  * a UI that lights the hold button on the local click, because the press
///    is the event the widget already had;
///  * a transport that drops notifications under load and reports nothing,
///    because a lost tick is "just" a lost tick;
///  * a controller whose cancellation is asynchronous and whose timer fires
///    once more, because `cancel()` returned and the author stopped reading;
///  * a source that feeds the counter itself to "smooth" a jittery cadence,
///    which is the single most reasonable-sounding line of code in this file;
///  * a teardown with nothing to release, because the registry was never
///    written to.
///
/// Each class replaces exactly one behaviour of [FakeStateMan] and inherits the
/// rest, so `test/sabotage_hold_test.dart` can assert both halves of a
/// sabotage — the targeted check fails, and a named neighbour still passes. A
/// variant that failed everything would prove nothing about any individual
/// check.
///
/// Two of the five are broad by construction and say so at their own class: a
/// source with no feed at all takes down every case that ticks once as its
/// anti-vacuity arm. Their surgical arm is the engage check, which is the one
/// case that never ticks.
///
/// These are **not** exported from `tfc_stateman_contract.dart`. The fakes live
/// under their own import path so nothing can acquire a deliberately broken
/// implementation by depending on the contract
/// (`tfc_stateman_contract.dart:59-63`).
library;

import 'dart:async';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'fake_state_man.dart';

/// Reports the engage as applied without the write ever reaching the plant.
///
/// The shipped version is a UI that lights the button on the local click: the
/// press is the event the widget already has, the handle is built from it, and
/// the operator is looking at a live hold on a machine that was never asked.
/// Everything downstream then works perfectly — the ticks go out, the counter
/// advances, the release writes its zero — which is why nothing but the tag
/// itself catches this.
///
/// It also never registers the hold, because a hold the source never took is
/// not a hold it can release; that makes the disposal case fail too, and the
/// surgical arm names the case that still passes.
class EngagesWithoutActuating extends FakeStateMan {
  EngagesWithoutActuating({super.staleAfter});
}

/// Honours no tick at all.
///
/// A transport that drops notifications under load, and says nothing, because
/// a tick is fire-and-forget by design and there is no outcome to lose. On a
/// plant this is the nastiest of the five: the machine simply refuses to jog,
/// the operator holds the button harder, and every screen involved reports a
/// healthy hold.
///
/// Broad by construction. Every hold case but the engage one ticks at least
/// once — as the property under test or as its anti-vacuity arm — so all of
/// them go red here. That is the honest consequence of removing the feed, and
/// the surgical case pins it by naming the one check that still passes.
class NeverAdvancesTheCounter extends FakeStateMan {
  NeverAdvancesTheCounter({super.staleAfter});
}

/// Lets one more counter value reach the plant after the release.
///
/// A controller whose cancellation is asynchronous: `release()` returns, the
/// zero lands on the tag, and the timer that was already scheduled fires once
/// behind it. The counter is now non-zero again, the PLC's deadman window
/// restarts, and the machine keeps moving after the finger came off — which is
/// the one failure the whole deadman exists to prevent.
///
/// The straggler is a real short timer rather than a microtask on purpose: a
/// microtask would land before the release even returned, which is a different
/// (and much more visible) bug. This one arrives in the gap where nobody is
/// looking, and it is cancelled in [dispose] so it cannot outlive its case.
class KeepsFeedingAfterRelease extends FakeStateMan {
  KeepsFeedingAfterRelease({super.staleAfter});
}

/// Advances the counter on a timer of its own, with no tick arriving.
///
/// The sabotage assumption A5 exists for, and the most reasonable-sounding
/// line of code in this file: a pump in the source that keeps the cadence
/// smooth over a jittery link. It passes every case that asserts something
/// happens. What it produces on a plant is a machine that keeps running with
/// nobody holding the button, because the thing the PLC is watching for —
/// silence — is exactly what this source refuses to produce.
///
/// The pump stops when the hold is released, which is what keeps the sabotage
/// surgical: this variant is wrong about *unattended* holds only.
class FeedsTheCounterOnATimer extends FakeStateMan {
  FeedsTheCounterOnATimer({super.staleAfter});
}

/// Hands out a hold it does not track, so its teardown has nothing to release.
///
/// The registry was never written to. Releasing by hand works perfectly and
/// every other case passes, which is what makes this one survive review: the
/// only moment it is visible is the moment the page closes with the button
/// still down, and by then nothing is watching the counter it left advancing.
class LeavesHoldsRunningOnDispose extends FakeStateMan {
  LeavesHoldsRunningOnDispose({super.staleAfter});
}
