/// TFC Core - Pure Dart library for industrial HMI data collection and management
///
/// This library provides core functionality for:
/// - OPC UA communication (state_man.dart)
/// - Timeseries data collection (collector.dart)
/// - Alarm management (alarm.dart)
/// - Database integration with PostgreSQL (database.dart)
/// - Preferences and secure storage (preferences.dart)

// Core exports
export 'core/alarm.dart';
export 'core/boolean_expression.dart';
export 'core/collector.dart';
export 'core/database.dart';
export 'core/database_drift.dart' hide Alarm; // Hide Alarm table class to avoid conflict
export 'core/file_preferences.dart';
export 'core/preferences.dart';
export 'core/ring_buffer.dart';
export 'core/state_man.dart';

// Secure storage
export 'core/secure_storage/secure_storage.dart';

// Converters (only Dart-compatible ones)
export 'converter/duration_converter.dart';
export 'converter/dynamic_value_converter.dart';

// NOTE: color_converter.dart and icon.dart require Flutter (dart:ui) and are not exported
