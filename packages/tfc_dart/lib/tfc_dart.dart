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

// Device clients — native with web stubs
export 'core/m2400_device_client.dart'
    if (dart.library.js_interop) 'core/web_stubs/m2400_device_client_stub.dart';
export 'core/modbus_device_client.dart'
    if (dart.library.js_interop) 'core/web_stubs/modbus_device_client_stub.dart';
export 'core/opcua_device_client.dart'
    if (dart.library.js_interop) 'core/web_stubs/opcua_device_client_stub.dart';
export 'core/mqtt_device_client.dart'; // works on all platforms

// Client wrappers — native with web stubs
export 'core/modbus_client_wrapper.dart'
    if (dart.library.js_interop) 'core/web_stubs/modbus_client_wrapper_stub.dart';

// Config
export 'core/config_source.dart'; // pure Dart, no stub needed
export 'core/mqtt_client_factory.dart'; // already has internal conditional export

// UMAS
export 'core/umas_types.dart'; // pure Dart, no stub needed
export 'core/umas_client.dart'
    if (dart.library.js_interop) 'core/web_stubs/umas_client_stub.dart';

// Converters
export 'converter/duration_converter.dart';
export 'converter/dynamic_value_converter.dart';

// Secure Storage
export 'core/secure_storage/interface.dart';
export 'core/secure_storage/secure_storage.dart'
    if (dart.library.js_interop) 'core/web_stubs/secure_storage_stub.dart';
