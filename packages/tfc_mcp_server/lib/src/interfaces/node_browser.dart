/// Read-only interface for browsing a PLC's address space.
///
/// Deliberately protocol-agnostic and free of any OPC UA or UMAS types: the
/// app layer owns those clients and adapts them to this, the same way
/// [StateReader] fronts StateMan. It mirrors the shape of the app's own
/// `BrowseDataSource`, which the adapter reuses rather than reimplementing.
///
/// Why this exists: `list_tags` and `get_tag_value` are both bounded by the
/// configured key mappings, so neither can answer "what else does this PLC
/// publish?" -- the question behind every stale mapping and every missing
/// signal. Browsing is the only way to tell a key that is mis-mapped from one
/// the PLC never exposed.
library;

/// What a node is, insofar as any protocol agrees.
enum BrowsedNodeType { folder, variable, method, other }

/// One node in a browsed address space.
class BrowsedNode {
  /// Protocol-native identity: an OPC UA NodeId (`ns=4;s=A.B.C`) or a UMAS
  /// variable path. Pass it back as `node_id` to descend.
  final String id;
  final String name;
  final BrowsedNodeType type;
  final String? dataType;
  final String? description;

  const BrowsedNode({
    required this.id,
    required this.name,
    required this.type,
    this.dataType,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        if (dataType != null) 'data_type': dataType,
        if (description != null) 'description': description,
      };
}

/// A browsable server, named the way the operator names it.
class BrowseSource {
  /// Matches `server_alias` in the key mappings, so a browsed node can be
  /// turned into a key mapping without a second lookup.
  final String alias;

  /// `opcua` or `umas`.
  final String protocol;
  final String? endpoint;

  const BrowseSource({
    required this.alias,
    required this.protocol,
    this.endpoint,
  });

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'protocol': protocol,
        if (endpoint != null) 'endpoint': endpoint,
      };
}

/// Browses PLC address spaces across protocols.
abstract class NodeBrowser {
  /// Every server that can be browsed.
  List<BrowseSource> get sources;

  /// Children of [nodeId] on [alias]; the server's roots when [nodeId] is
  /// null.
  ///
  /// Implementations must bound their own work: browsing is far heavier than
  /// a read, and an unhealthy server can leave a Browse outstanding
  /// indefinitely. Throws [ArgumentError] for an unknown alias.
  Future<List<BrowsedNode>> browse(String alias, {String? nodeId});
}
