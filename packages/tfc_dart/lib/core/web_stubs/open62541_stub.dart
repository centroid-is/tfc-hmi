/// Web stubs for package:open62541/open62541.dart types.
/// These exist purely for compilation — OPC UA is not used on web.

// ignore_for_file: constant_identifier_names, camel_case_types

typedef ReadAttributeParam = Map<NodeId, List<AttributeId>>;

class DynamicValue {
  final Object? value;
  final NodeId? typeId;
  final String? name;

  DynamicValue({this.value, this.typeId, this.name});

  DynamicValue? operator [](String key) => null;

  @override
  String toString() => 'DynamicValue($value)';
}

class NodeId {
  final int nsIndex;
  final Object identifier;

  const NodeId._(this.nsIndex, this.identifier);

  factory NodeId.fromNumeric(int nsIndex, int id) => NodeId._(nsIndex, id);
  factory NodeId.fromString(int nsIndex, String chars) =>
      NodeId._(nsIndex, chars);

  static NodeId get boolean => NodeId._(0, 1);
  static NodeId get int16 => NodeId._(0, 4);
  static NodeId get uint16 => NodeId._(0, 5);
  static NodeId get int32 => NodeId._(0, 6);
  static NodeId get uint32 => NodeId._(0, 7);
  static NodeId get float => NodeId._(0, 10);
  static NodeId get int64 => NodeId._(0, 8);
  static NodeId get uint64 => NodeId._(0, 9);
  static NodeId get double => NodeId._(0, 11);

  @override
  bool operator ==(Object other) =>
      other is NodeId &&
      nsIndex == other.nsIndex &&
      identifier == other.identifier;
  @override
  int get hashCode => Object.hash(nsIndex, identifier);
}

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

class BrowseResultItem {
  final NodeId nodeId;
  final String browseName;
  final String displayName;
  final int nodeClass;

  BrowseResultItem({
    required this.nodeId,
    required this.browseName,
    required this.displayName,
    required this.nodeClass,
  });
}

class BrowseTreeItem extends BrowseResultItem {
  final List<BrowseTreeItem> children;

  BrowseTreeItem({
    required super.nodeId,
    required super.browseName,
    required super.displayName,
    required super.nodeClass,
    this.children = const [],
  });
}

abstract class ClientApi {
  Stream<ClientState> get stateStream;
  Future<void> connect(String url);
  Future<void> write(NodeId nodeId, DynamicValue value);
  Future<DynamicValue> read(NodeId nodeId);
  Future<Map<NodeId, DynamicValue>> readAttribute(ReadAttributeParam nodes);
  Future<int> subscriptionCreate();
  Stream<DynamicValue> monitor(NodeId nodeId, int subscriptionId);
  Future<void> disconnect();
  Future<void> delete();
  Future<void> awaitConnect();
  Future<List<BrowseResultItem>> browse(NodeId nodeId);
  Stream<BrowseTreeItem> browseTree(NodeId root);
  Future<List<DynamicValue>> call(
      NodeId objectId, NodeId methodId, Iterable<DynamicValue> args);
}

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
  Future<int> subscriptionCreate() => throw UnsupportedError('Not on web');
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
}

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
  Future<int> subscriptionCreate() => throw UnsupportedError('Not on web');
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
}
