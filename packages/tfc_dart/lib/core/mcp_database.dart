import 'package:drift/drift.dart';

/// Abstract interface for databases that provide MCP table accessors.
///
/// Both [AppDatabase] (Flutter in-process path) and [ServerDatabase]
/// (standalone binary path) satisfy this interface. MCP services accept
/// [McpDatabase] to decouple from the concrete database implementation.
///
/// This is a marker interface extending [GeneratedDatabase] to provide
/// type-safe discrimination between "any database" and "a database that
/// has MCP tables". Both AppDatabase and ServerDatabase implement this.
///
/// Table accessors (auditLog, plcCodeBlockTable, drawingTable, etc.) are
/// available on both concrete database classes with identical names but
/// different generated types (Drift generates table types per-database).
/// Services access them through the concrete type or via
/// [GeneratedDatabase.allTables] and SQL-level queries.
///
/// Shared tables (alarm, alarm_history, flutter_preferences) are NOT
/// part of this interface because AppDatabase and ServerDatabase define
/// them with different row classes (@UseRowClass vs generated).
///
/// Lives in tfc_dart (not tfc_mcp_server) to avoid circular dependency:
/// tfc_mcp_server depends on tfc_dart, so McpDatabase must be in tfc_dart
/// for AppDatabase to implement it.
abstract class McpDatabase implements GeneratedDatabase {}
