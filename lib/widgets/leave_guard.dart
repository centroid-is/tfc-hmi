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

  /// Bumps on every [then] request. A guard answers asynchronously (its answer
  /// comes from a dialog the operator taps, and saving first can await a disk
  /// write); by the time it lands the operator may have asked to leave a second
  /// time, or the page that installed it may be gone. Only the newest request
  /// is allowed to run its [go] -- see [then].
  static int _generation = 0;

  /// Install [guard]; it answers true to allow leaving. One at a time: the
  /// page on screen owns it.
  static void set(Future<bool> Function() guard) => _guard = guard;

  /// Remove [guard] if it is still the installed one (a page that was
  /// replaced must not clear its successor's).
  static void clear(Future<bool> Function() guard) {
    if (identical(_guard, guard)) _guard = null;
  }

  /// True when nothing objects to leaving the current page.
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
      go();
      return;
    }
    // A guard is installed, so the answer arrives a microtask (a clean editor)
    // or a dialog tap and a save (a dirty one) later. Three ways that await
    // used to lose the operator's tap into a wedged, unresponsive screen, all
    // fixed here:
    //
    //  * The future was chained with a bare `.then` and no error handler. A
    //    guard that threw -- `showStandardDialog` on an unmounted context, a
    //    save that failed -- became an *unhandled* async error, and [go] never
    //    ran: the pane and dialogs stayed, the beam never fired, and the tap
    //    was silently swallowed. `onError` below catches it, reports it, and
    //    stays put, which is always the safe answer -- refusing to leave keeps
    //    the operator's edits; losing the tap into a freeze does not.
    //
    //  * Nothing stopped a slow guard from beaming after the operator had
    //    already moved on. Two overlapping asks (the nav bar, then a
    //    programmatic beam; or a guard still saving when the next tap lands)
    //    could each fire [go], beaming twice or beaming on top of a page that
    //    had since taken over. The generation check lets only the newest
    //    request through.
    //
    //  * The chain is never awaited by the caller and carries no lock, so a
    //    guard that never completes at all costs one dropped tap, not a
    //    permanent block: the next tap starts a fresh request with a higher
    //    generation and proceeds on its own.
    final generation = ++_generation;
    guard().then((ok) {
      if (ok && generation == _generation) go();
    }).catchError((Object error, StackTrace stack) {
      _logger.e('Leave guard failed; staying on the current page',
          error: error, stackTrace: stack);
    });
  }

  static bool get isSet => _guard != null;
}
