/// Interface for providing the list of active PLC server aliases.
///
/// In production, this is backed by StateMan's OPC-UA config
/// (each `OpcUAConfig.serverAlias` in the active config).
/// In tests, a simple stub implementation can be used.
///
/// Used by [PlcContextService] to resolve the server alias for keys
/// whose key mapping has no explicit `server_alias` field. When there
/// is exactly one active server, that server's alias is used as the
/// default. When there are zero or multiple servers, the service
/// falls back to 'unknown'.
abstract class ServerAliasProvider {
  /// Returns the list of active PLC server aliases.
  ///
  /// Each alias corresponds to an `OpcUAConfig.serverAlias` in the
  /// StateMan configuration. The list may be empty if no servers are
  /// configured or connected.
  List<String> get serverAliases;
}
