/// Web-safe barrel for tfc_mcp_server.
///
/// Exports interfaces, data classes, pure-Dart services, and configuration.
/// Native implementations (TfcMcpServer, drift indexes, audit, etc.) are
/// replaced by minimal type stubs from web_types.dart.
///
/// Import pattern in Flutter app:
/// ```dart
/// import 'package:tfc_mcp_server/tfc_mcp_server.dart'
///     if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart';
/// ```

// Interfaces (pure Dart)
export 'src/interfaces/state_reader.dart';
export 'src/interfaces/alarm_reader.dart';
export 'src/interfaces/drawing_index.dart';
export 'src/interfaces/plc_code_index.dart';
export 'src/interfaces/tech_doc_index.dart';
export 'src/interfaces/empty_readers.dart';
export 'src/interfaces/server_alias_provider.dart';

// Identity (pure Dart abstract interface)
export 'src/identity/operator_identity.dart';

// Config & toggles (pure Dart)
export 'src/tools/tool_toggles.dart';

// Safety (pure Dart abstract)
export 'src/safety/risk_gate.dart';
export 'src/safety/proposal_declined_exception.dart';

// Expression validator (pure Dart)
export 'src/expression/expression_validator.dart';

// McpDatabase interface from tfc_dart_core
export 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase;

// Pure-Dart services (no drift/io deps)
export 'src/services/plc_code_service.dart';
export 'src/services/plc_context_service.dart';
export 'src/services/drawing_service.dart';
export 'src/services/tech_doc_service.dart';
export 'src/services/asset_type_catalog.dart';

// Compiler (pure Dart)
export 'src/compiler/call_graph_builder.dart';

// Parsers (pure Dart)
export 'src/parser/twincat_zip_extractor.dart';
export 'src/parser/twincat_xml_parser.dart';
export 'src/parser/structured_text_parser.dart';
export 'src/parser/schneider_xml_parser.dart';

// Web type stubs for native-only implementations
export 'src/web_types.dart';
