// Core — platform-agnostic
export 'core/dynamic_value.dart';
export 'core/fuzzy_match.dart';
export 'core/ring_buffer.dart';
export 'core/state_man.dart';

// Core — native with web stubs
export 'core/alarm.dart'
    if (dart.library.js_interop) 'core/web_stubs/alarm_stub.dart';
export 'core/boolean_expression.dart'
    if (dart.library.js_interop) 'core/web_stubs/boolean_expression_stub.dart';
export 'core/collector.dart'
    if (dart.library.js_interop) 'core/web_stubs/collector_stub.dart';
export 'core/database.dart'
    if (dart.library.js_interop) 'core/web_stubs/database_stub.dart';
export 'core/database_drift.dart'
    if (dart.library.js_interop) 'core/web_stubs/database_drift_stub.dart'
    hide Alarm, AlarmHistory;
export 'core/preferences.dart'
    if (dart.library.js_interop) 'core/web_stubs/preferences_stub.dart';

// Converters
export 'converter/duration_converter.dart';
export 'converter/dynamic_value_converter.dart';

// Secure Storage
export 'core/secure_storage/interface.dart';
export 'core/secure_storage/secure_storage.dart'
    if (dart.library.js_interop) 'core/web_stubs/secure_storage_stub.dart';
