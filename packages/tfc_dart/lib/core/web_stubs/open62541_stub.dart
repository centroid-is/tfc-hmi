/// Web stubs for package:open62541/open62541.dart types.
/// These exist purely for compilation — OPC UA is not used on web.
///
/// DynamicValue, NodeId, LocalizedText, EnumField, and DynamicType are
/// re-exported from the canonical pure-Dart implementation so that the
/// same types are used everywhere on web.

// ignore_for_file: constant_identifier_names, camel_case_types

export '../dynamic_value.dart'
    show DynamicValue, NodeId, LocalizedText, EnumField, DynamicType;

import '../dynamic_value.dart';

// ---------------------------------------------------------------------------
// NodeClass enum — mirrors UA_NodeClass from open62541
// ---------------------------------------------------------------------------

enum NodeClass {
  UA_NODECLASS_UNSPECIFIED(0),
  UA_NODECLASS_OBJECT(1),
  UA_NODECLASS_VARIABLE(2),
  UA_NODECLASS_METHOD(4),
  UA_NODECLASS_OBJECTTYPE(8),
  UA_NODECLASS_VARIABLETYPE(16),
  UA_NODECLASS_REFERENCETYPE(32),
  UA_NODECLASS_DATATYPE(64),
  UA_NODECLASS_VIEW(128);

  final int value;
  const NodeClass(this.value);

  static NodeClass fromValue(int value) => switch (value) {
    0 => UA_NODECLASS_UNSPECIFIED,
    1 => UA_NODECLASS_OBJECT,
    2 => UA_NODECLASS_VARIABLE,
    4 => UA_NODECLASS_METHOD,
    8 => UA_NODECLASS_OBJECTTYPE,
    16 => UA_NODECLASS_VARIABLETYPE,
    32 => UA_NODECLASS_REFERENCETYPE,
    64 => UA_NODECLASS_DATATYPE,
    128 => UA_NODECLASS_VIEW,
    _ => throw ArgumentError('Unknown value for NodeClass: $value'),
  };
}

// ---------------------------------------------------------------------------
// Typedefs
// ---------------------------------------------------------------------------

typedef ReadAttributeParam = Map<NodeId, List<AttributeId>>;

// ---------------------------------------------------------------------------
// OPC UA enums
// ---------------------------------------------------------------------------

enum SessionState {
  UA_SESSIONSTATE_CLOSED,
  UA_SESSIONSTATE_CREATE_REQUESTED,
  UA_SESSIONSTATE_ACTIVATED,
}

enum SecureChannelState {
  UA_SECURECHANNELSTATE_CLOSED,
  UA_SECURECHANNELSTATE_OPEN,
  UA_SECURECHANNELSTATE_REVERSE_LISTENING,
}

enum MessageSecurityMode {
  UA_MESSAGESECURITYMODE_NONE,
  UA_MESSAGESECURITYMODE_SIGN,
  UA_MESSAGESECURITYMODE_SIGNANDENCRYPT,
}

enum LogLevel {
  UA_LOGLEVEL_TRACE,
  UA_LOGLEVEL_DEBUG,
  UA_LOGLEVEL_INFO,
  UA_LOGLEVEL_WARNING,
  UA_LOGLEVEL_ERROR,
  UA_LOGLEVEL_FATAL,
}

enum AttributeId {
  UA_ATTRIBUTEID_VALUE,
  UA_ATTRIBUTEID_DESCRIPTION,
  UA_ATTRIBUTEID_DISPLAYNAME,
  UA_ATTRIBUTEID_DATATYPE,
  UA_ATTRIBUTEID_NODEID,
  UA_ATTRIBUTEID_NODECLASS,
  UA_ATTRIBUTEID_BROWSENAME,
}

enum MonitoringMode {
  UA_MONITORINGMODE_DISABLED,
  UA_MONITORINGMODE_SAMPLING,
  UA_MONITORINGMODE_REPORTING,
}

// ---------------------------------------------------------------------------
// ClientState
// ---------------------------------------------------------------------------

class ClientState {
  final SecureChannelState channelState;
  final SessionState sessionState;
  final int recoveryStatus;

  ClientState({
    required this.channelState,
    required this.sessionState,
    this.recoveryStatus = 0,
  });
}

// ---------------------------------------------------------------------------
// Browse types
// ---------------------------------------------------------------------------

class BrowseResultItem {
  final NodeId nodeId;
  final String browseName;
  final String displayName;
  final NodeClass nodeClass;
  final NodeId? referenceTypeId;
  final bool isForward;
  final NodeId? typeDefinition;

  BrowseResultItem({
    required this.nodeId,
    required this.browseName,
    required this.displayName,
    required this.nodeClass,
    this.referenceTypeId,
    this.isForward = true,
    this.typeDefinition,
  });
}

class BrowseTreeItem extends BrowseResultItem {
  final List<BrowseTreeItem> children;

  BrowseTreeItem({
    required super.nodeId,
    required super.browseName,
    required super.displayName,
    required super.nodeClass,
    super.referenceTypeId,
    super.isForward,
    this.children = const [],
  });
}

// ---------------------------------------------------------------------------
// MonitoredItemInfo
// ---------------------------------------------------------------------------

class MonitoredItemInfo {
  final NodeId nodeId;
  final int subscriptionId;
  final int monitoredItemId;

  MonitoredItemInfo({
    required this.nodeId,
    required this.subscriptionId,
    required this.monitoredItemId,
  });
}

// ---------------------------------------------------------------------------
// ClientApi — abstract interface
// ---------------------------------------------------------------------------

abstract class ClientApi {
  Stream<ClientState> get stateStream;
  Future<void> connect(String url);
  Future<void> write(NodeId nodeId, DynamicValue value);
  Future<DynamicValue> read(NodeId nodeId);
  Future<Map<NodeId, DynamicValue>> readAttribute(ReadAttributeParam nodes);
  Future<int> subscriptionCreate({
    Duration? requestedPublishingInterval,
    int? requestedMaxKeepAliveCount,
  });
  Stream<DynamicValue> monitor(NodeId nodeId, int subscriptionId);
  Future<void> disconnect();
  Future<void> delete();
  Future<void> awaitConnect();
  Future<List<BrowseResultItem>> browse(NodeId nodeId);
  Stream<BrowseTreeItem> browseTree(NodeId root);
  Future<List<DynamicValue>> call(
      NodeId objectId, NodeId methodId, Iterable<DynamicValue> args);
  List<MonitoredItemInfo> monitoredItems();
}

// ---------------------------------------------------------------------------
// Client — throws on construction (not available on web)
// ---------------------------------------------------------------------------

class Client implements ClientApi {
  Client(dynamic lib,
      {String? username,
      String? password,
      MessageSecurityMode? securityMode,
      dynamic certificate,
      dynamic privateKey,
      LogLevel? logLevel,
      Duration? secureChannelLifeTime,
      Duration connectivityCheckInterval = const Duration(seconds: 10)}) {
    throw UnsupportedError('OPC UA Client not available on web');
  }

  bool runIterate(Duration timeout) => false;

  @override
  Stream<ClientState> get stateStream => const Stream.empty();
  @override
  Future<void> connect(String url) => throw UnsupportedError('Not on web');
  @override
  Future<void> write(NodeId n, DynamicValue v) =>
      throw UnsupportedError('Not on web');
  @override
  Future<DynamicValue> read(NodeId n) =>
      throw UnsupportedError('Not on web');
  @override
  Future<Map<NodeId, DynamicValue>> readAttribute(ReadAttributeParam n) =>
      throw UnsupportedError('Not on web');
  @override
  Future<int> subscriptionCreate({
    Duration? requestedPublishingInterval,
    int? requestedMaxKeepAliveCount,
  }) =>
      throw UnsupportedError('Not on web');
  @override
  Stream<DynamicValue> monitor(NodeId n, int s) => const Stream.empty();
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> delete() async {}
  @override
  Future<void> awaitConnect() => throw UnsupportedError('Not on web');
  @override
  Future<List<BrowseResultItem>> browse(NodeId n) =>
      throw UnsupportedError('Not on web');
  @override
  Stream<BrowseTreeItem> browseTree(NodeId n) => const Stream.empty();
  @override
  Future<List<DynamicValue>> call(
          NodeId o, NodeId m, Iterable<DynamicValue> a) =>
      throw UnsupportedError('Not on web');
  @override
  List<MonitoredItemInfo> monitoredItems() => [];
}

// ---------------------------------------------------------------------------
// ClientIsolate — throws on creation (not available on web)
// ---------------------------------------------------------------------------

class ClientIsolate implements ClientApi {
  ClientIsolate._();

  static Future<ClientIsolate> create({
    String? username,
    String? password,
    MessageSecurityMode? securityMode,
    dynamic certificate,
    dynamic privateKey,
    LogLevel? logLevel,
    Duration? secureChannelLifeTime,
    String? libraryPath,
    Duration connectivityCheckInterval = const Duration(seconds: 10),
  }) async {
    throw UnsupportedError('OPC UA ClientIsolate not available on web');
  }

  bool runIterate(Duration timeout) => false;

  @override
  Stream<ClientState> get stateStream => const Stream.empty();
  @override
  Future<void> connect(String url) => throw UnsupportedError('Not on web');
  @override
  Future<void> write(NodeId n, DynamicValue v) =>
      throw UnsupportedError('Not on web');
  @override
  Future<DynamicValue> read(NodeId n) =>
      throw UnsupportedError('Not on web');
  @override
  Future<Map<NodeId, DynamicValue>> readAttribute(ReadAttributeParam n) =>
      throw UnsupportedError('Not on web');
  @override
  Future<int> subscriptionCreate({
    Duration? requestedPublishingInterval,
    int? requestedMaxKeepAliveCount,
  }) =>
      throw UnsupportedError('Not on web');
  @override
  Stream<DynamicValue> monitor(NodeId n, int s) => const Stream.empty();
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> delete() async {}
  @override
  Future<void> awaitConnect() => throw UnsupportedError('Not on web');
  @override
  Future<List<BrowseResultItem>> browse(NodeId n) =>
      throw UnsupportedError('Not on web');
  @override
  Stream<BrowseTreeItem> browseTree(NodeId n) => const Stream.empty();
  @override
  Future<List<DynamicValue>> call(
          NodeId o, NodeId m, Iterable<DynamicValue> a) =>
      throw UnsupportedError('Not on web');
  @override
  List<MonitoredItemInfo> monitoredItems() => [];
}
