import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the [GlobalKey<NavigatorState>] from the app's [BeamerDelegate].
///
/// Overlay widgets rendered inside `MaterialApp.builder` (chat, drawings,
/// FAB) sit **above** the Navigator in the widget tree, so their
/// `BuildContext` cannot find a `Navigator` ancestor.  Any code that
/// needs to show dialogs, pop routes, or access the Beamer delegate
/// should use this key instead of `Navigator.of(context)`.
///
/// Set once in `MyApp.build` from `routerDelegate.navigatorKey`.
final navigatorKeyProvider = StateProvider<GlobalKey<NavigatorState>?>(
  (ref) => null,
);
