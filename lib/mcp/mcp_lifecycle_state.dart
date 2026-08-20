import 'dart:async';

/// Encapsulates mutable state for MCP lifecycle providers.
///
/// Replaces module-level variables (`_activeStateReader`, `_reconnectTimer`)
/// that were duplicated in both `chat.dart` and `mcp_bridge.dart`. Each
/// lifecycle provider owns one instance.
class McpLifecycleState {
  /// The active state reader for the current session.
  ///
  /// Type is `dynamic` because the concrete type (StateManStateReader)
  /// is only available in the Flutter app layer. Callers cast as needed.
  dynamic activeStateReader;

  /// Debounce timer for toggle-change-triggered reconnects.
  Timer? reconnectTimer;

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

  /// Cleans up all state: disposes reader and cancels the timer.
  void dispose() {
    disposeReader();
    cancelTimer();
  }
}
