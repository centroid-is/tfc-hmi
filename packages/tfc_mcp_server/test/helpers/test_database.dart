import 'package:tfc_mcp_server/src/database/server_database.dart';

/// Creates a fresh in-memory SQLite [ServerDatabase] for testing.
///
/// Each call returns an isolated database instance. No cleanup is needed --
/// the database is garbage collected when the test completes.
ServerDatabase createTestDatabase() {
  return ServerDatabase.inMemory();
}
