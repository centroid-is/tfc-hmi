/// Web stub for package:open62541/open62541.dart.
///
/// Re-exports pure-Dart types and provides minimal stubs for
/// FFI types that are referenced but never instantiated on web.
library;

// Re-export pure-Dart types that work on all platforms.
import 'package:open62541/open62541_types.dart';
export 'package:open62541/open62541_types.dart';

// Minimal stubs for FFI types used in `show` clauses on web.
// These are never constructed on web — only referenced for type annotations.

enum ClientState { disconnected, connected, sessionReady }

enum NodeClass { object, variable, method, objectType, variableType, referenceType, dataType, view }

enum BrowseResultMask { all }

class BrowseResultItem {
  final NodeId nodeId = NodeId.fromNumeric(0, 0);
  final String browseName = '';
  final String displayName = '';
  final NodeClass nodeClass = NodeClass.object;
}

class BrowseTreeItem extends BrowseResultItem {
  final List<BrowseTreeItem> children = [];
}

abstract class ClientApi {
  Future<DynamicValue> read(NodeId nodeId);
  Future<void> write(NodeId nodeId, DynamicValue value);
  Stream<DynamicValue> subscribe(NodeId nodeId);
}

class AccessLevelMask {
  static const int read = 1;
  static const int write = 2;
}
