import 'dart:async';

import 'package:logger/logger.dart';

/// Lets the page being shown veto navigation away from it.
///
/// The page editor keeps its edits in memory until Save. Leaving it -- the
/// back arrow, a nav-bar destination, a menu item -- used to drop them
/// silently; the only hint was the Save button having turned orange. The
/// editor registers a guard while it is open; the navigation chrome asks it
/// before beaming, and it gets to show "Unsaved changes: Save / Discard /
/// Stay". Programmatic navigation (a proposal opening another page) does
/// not ask -- by the time the router listener fires the route has changed.
abstract final class LeaveGuard {
  static final Logger _logger = Logger();

  static Future<bool> Function()? _guard;

  /// The guard currently being asked, or null when no question is open.
  ///
  /// Identity, not a flag: it is what tells an answer landing later whether
  /// the page that asked is still the page installed. A guard replaced or
  /// removed while its answer was in flight leaves this null (or holding
  /// someone else's guard), and the stale answer is dropped.
  static Future<bool> Function()? _asking;

  /// The newest [go] waiting on [_asking]. Replaced rather than queued: when
  /// the operator asks twice, only the destination they asked for last should
  /// be navigated to.
  static void Function()? _pendingGo;

  /// Install [guard]; it answers true to allow leaving. One at a time: the
  /// page on screen owns it.
  static void set(Future<bool> Function() guard) {
    // A new page owns the question now. Whatever the outgoing page was still
    // being asked, its answer is about to be meaningless -- see [_abandon].
    _abandon();
    _guard = guard;
  }

  /// Remove [guard] if it is still the installed one (a page that was
  /// replaced must not clear its successor's).
  static void clear(Future<bool> Function() guard) {
    if (identical(_guard, guard)) {
      _abandon();
      _guard = null;
    }
  }

  /// Forget any question still in flight.
  ///
  /// Its answer belongs to a page that has since been replaced or disposed,
  /// and running its [go] would beam on top of whatever took over -- or, when
  /// the next request took the synchronous no-guard path below, beam a second
  /// time on top of a beam that already happened.
  static void _abandon() {
    _asking = null;
    _pendingGo = null;
  }

  /// True when nothing objects to leaving the current page.
  ///
  /// The raw ask, with none of [then]'s supersession or error handling: the
  /// answer is the installed guard's, whoever asked and whatever else is in
  /// flight. Navigation must go through [then] instead; this is for callers
  /// that only want to know, and it is what the guard tests probe.
  static Future<bool> mayLeave() async =>
      await (_guard?.call() ?? Future.value(true));

  /// Run [go] if nothing objects -- and run it SYNCHRONOUSLY when no guard
  /// is installed. That matters: the navigation chrome closes the side pane
  /// and then beams in [go], and both must happen inside the tap handler.
  /// Deferring them by even one microtask (an `await` on an already-true
  /// Future) left the pane's overlay entry mounted across the route pop, so
  /// the pane rebuilt a builder whose asset had just been disposed -- the
  /// same "ValueNotifier used after being disposed" the dismiss-race fix had
  /// removed. With a guard installed the answer comes from a dialog, i.e.
  /// from a later tap handler, where the same ordering holds again.
  static void then(void Function() go) {
    final guard = _guard;
    if (guard == null) {
      // Nothing in flight may beam behind this one. set() and clear() are the
      // only ways to get here with a question still open and both already
      // abandon it, so this is belt and braces -- but a stale answer landing
      // after a beam has happened is exactly the double-navigation this class
      // exists to prevent, so do not rely on that staying true.
      _abandon();
      go();
      return;
    }

    // A guard is installed, so the answer arrives a microtask (a clean editor)
    // or a dialog tap and a save (a dirty one) later. The operator can act
    // again inside that window, and both halves of that need handling: the
    // request that arrives, and the answer that eventually lands.
    _pendingGo = go;

    // The arriving request. Asking a second time is not harmless -- the page
    // editor's guard shows a modal and then awaits _saveToPrefs(), which does
    // not mark the page clean until it has finished writing. A tap during that
    // window would put a second "Unsaved changes" dialog on screen and, if
    // answered, start a second concurrent save of the same page. So one
    // question at a time: a request landing on a guard already being asked
    // just replaces the destination and rides the answer already coming.
    //
    // The cost is that a guard which never answers at all now holds navigation
    // until its page is replaced, where before every tap asked again. That is
    // the trade we want: an unanswered guard means the page never said whether
    // its edits are safe to discard, and navigating anyway loses them. Asking
    // again would not have produced an answer either -- it would only have
    // stacked a second dialog on the first.
    if (identical(_asking, guard)) return;
    _asking = guard;

    guard().then((bool ok) {
      // The answering half. Between the ask and here the page may have been
      // disposed or replaced, which _abandon() records by dropping [_asking].
      if (!identical(_asking, guard)) {
        // Logged, not silent. Dropping a navigation the operator asked for and
        // the page allowed is exactly the kind of quiet early return that makes
        // a stuck screen impossible to read from the logs afterwards.
        _logger.d('Leave request superseded before its guard answered; '
            'not navigating');
        return;
      }
      final pending = _pendingGo;
      _abandon();
      if (!ok || pending == null) return;
      try {
        pending();
      } catch (error, stack) {
        // Separate from the guard's own failure below, and deliberately worded
        // differently: by the time [go] runs it has already closed the side
        // pane and the floating dialogs, so a throw here does NOT leave the
        // operator where they were. Reporting it as the guard failing would
        // point at the wrong half of the path.
        _logger.e('Navigation failed after the leave guard allowed it',
            error: error, stackTrace: stack);
      }
    }, onError: (Object error, StackTrace stack) {
      // `onError` on the ask, not `catchError` on the chain: this must catch
      // the guard failing -- showStandardDialog on an unmounted context, a save
      // that threw -- and nothing else. Without it the failure became an
      // unhandled async error and [go] never ran, so the tap was swallowed with
      // no trace. Staying put is the safe answer; it keeps the edits.
      if (identical(_asking, guard)) _abandon();
      _logger.e('Leave guard failed; staying on the current page',
          error: error, stackTrace: stack);
    });
  }

  static bool get isSet => _guard != null;
}
