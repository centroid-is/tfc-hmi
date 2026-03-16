import 'dart:async';

/// Encapsulates mutable state for MCP lifecycle providers.
///
/// Replaces module-level variables (`_activeStateReader`, `_reconnectTimer`,
/// `_toggleListenerSetUp`) that were duplicated in both `chat.dart` and
/// `mcp_bridge.dart`. Each lifecycle provider owns one instance.
class McpLifecycleState {
  /// The active state reader for the current session.
  ///
  /// Type is `dynamic` because the concrete type (StateManStateReader)
  /// is only available in the Flutter app layer. Callers cast as needed.
  dynamic activeStateReader;

  /// Debounce timer for toggle-change-triggered reconnects.
  Timer? reconnectTimer;

  /// Guard to set up the toggle change subscription only once.
  bool toggleListenerSetUp = false;

  /// Disposes the active state reader and nulls the reference.
  void disposeReader() {
    activeStateReader?.dispose();
    activeStateReader = null;
  }

  /// Cancels the reconnect timer and nulls the reference.
  void cancelTimer() {
    reconnectTimer?.cancel();
    reconnectTimer = null;
  }

  /// Cleans up all state: disposes reader, cancels timer, resets listener guard.
  void dispose() {
    disposeReader();
    cancelTimer();
    toggleListenerSetUp = false;
  }
}
