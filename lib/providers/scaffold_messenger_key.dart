import 'package:flutter/material.dart';

/// Global [ScaffoldMessengerState] key wired into [MaterialApp].
///
/// Allows fire-and-forget operations (e.g. background re-index) to show
/// snackbars even after the originating widget has been unmounted.
///
/// Usage:
/// ```dart
/// globalScaffoldMessengerKey.currentState?.showSnackBar(
///   SnackBar(content: Text('Done')),
/// );
/// ```
final globalScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
