import 'dart:async';

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
  static Future<bool> Function()? _guard;

  /// Install [guard]; it answers true to allow leaving. One at a time: the
  /// page on screen owns it.
  static void set(Future<bool> Function() guard) => _guard = guard;

  /// Remove [guard] if it is still the installed one (a page that was
  /// replaced must not clear its successor's).
  static void clear(Future<bool> Function() guard) {
    if (identical(_guard, guard)) _guard = null;
  }

  /// True when nothing objects to leaving the current page.
  static Future<bool> mayLeave() async => await (_guard?.call() ?? Future.value(true));

  static bool get isSet => _guard != null;
}
