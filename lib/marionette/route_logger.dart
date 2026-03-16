import 'dart:developer' as developer;

import 'package:beamer/beamer.dart';

/// Logs route changes to Flutter's developer log so that Marionette agents
/// can verify navigation instantly via `getLogs` instead of taking screenshots.
///
/// Emits log entries with the `ROUTE` name in the format:
///
///     [ROUTE] /alarm-editor
///     [ROUTE] /page-editor?id=123
///
/// Usage:
///
/// ```dart
/// final routeLogger = MarionetteRouteLogger(routerDelegate);
/// // later...
/// routeLogger.dispose();
/// ```
///
/// This class should only be instantiated when the `MARIONETTE` compile-time
/// flag is enabled, so it has zero cost in production builds.
class MarionetteRouteLogger {
  MarionetteRouteLogger(this._delegate) {
    // Log the initial route.
    _onRouteChanged();
    // Listen for subsequent route changes.
    _delegate.addListener(_onRouteChanged);
  }

  final BeamerDelegate _delegate;

  /// The last URI path that was logged. Used to suppress duplicate logs when
  /// the delegate notifies but the route hasn't actually changed (e.g. a
  /// query parameter update triggers a rebuild but the path is the same).
  String? _lastLoggedPath;

  void _onRouteChanged() {
    try {
      final location = _delegate.currentBeamLocation;
      if (location is EmptyBeamLocation) return;

      final state = location.state;
      if (state is! BeamState) return;

      final uri = state.uri;
      final fullPath = uri.hasQuery ? '$uri' : uri.path;

      if (fullPath == _lastLoggedPath) return;
      _lastLoggedPath = fullPath;

      developer.log(
        '[ROUTE] $fullPath',
        name: 'ROUTE',
      );
    } catch (_) {
      // Swallow errors — this is debug instrumentation only.
    }
  }

  /// Removes the listener from the delegate.
  void dispose() {
    _delegate.removeListener(_onRouteChanged);
  }
}
