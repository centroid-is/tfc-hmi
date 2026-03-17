# SEGFAULT in `Server.addCustomType` when called after `deleteNode` on same running server

## Summary

Calling `addCustomType()` (or `addVariableNode()`) on a **running** `Server` after `deleteNode()` has removed nodes from the address space causes a **SIGSEGV** (null pointer dereference at address 0x50). The server is never shut down — the crash happens on a live, running server when node deletion and node creation interleave via Dart async.

## Production crash

```
===== CRASH =====
si_signo=Segmentation fault(11), si_code=SEGV_MAPERR(1), si_addr=0x50

[Optimized] Server.addCustomType+0x88c
[Optimized] AggregatorServer._createAndSubscribeVariable+0x2da
```

The backend process (Dart AOT, Linux x64) crashed with exit code 139 after ~2 minutes of operation. The server was running and processing client requests at the time of the crash.

## Root cause

`addCustomType()` calls `_findDataType()` which calls `UA_Server_findDataType(_server, nodeId)`. When `deleteNode()` has been called between async `await` points, the internal open62541 data structures that `_findDataType` traverses contain freed/dangling pointers.

The race condition (single isolate, single thread, no actual concurrency):
1. **Async code** calls `addVariableNode()` / `addCustomType()` in a loop (with `await` points between iterations for upstream reads)
2. Between two `await` points, a **synchronous stream listener** fires and calls `deleteNode()` on nodes belonging to the same server
3. The async code resumes and calls `addCustomType()` → native open62541 traverses freed internal structures → SEGFAULT

## Reproducing test

```dart
// In aggregator_performance_test.dart — "Teardown/repopulate race condition" group
// Reliably produces: "Invalid argument(s): Unknown value for UA_LifecycleState: 40269504"
// which is corrupted native memory (same root cause as the production SEGFAULT)

test('rapid disconnect/reconnect during repopulation does not crash', () async {
  for (var cycle = 0; cycle < 3; cycle++) {
    // Stop upstream server → triggers deleteNode on all alias nodes
    upstreamServer.shutdown();
    upstreamServer.delete();
    await Future.delayed(const Duration(seconds: 2));

    // Restart → triggers addVariableNode/addCustomType for same nodes
    upstreamServer = Server(port: upstreamPort, ...);
    // ... re-add variables, start server
    await Future.delayed(const Duration(milliseconds: 500));
    // ^^^ dangerous window: repopulate is mid-flight when next cycle tears down
  }
});
```

The test fails with `Unknown value for UA_LifecycleState: 40269504` — a corrupted enum value from reading freed native memory.

## Affected methods (no lifecycle check)

| Method | Checks `UA_Server_getLifecycleState`? |
|--------|--------------------------------------|
| `runIterate()` | YES |
| `addCustomType()` | **NO** |
| `addVariableNode()` | **NO** |
| `addObjectNode()` | **NO** |
| `deleteNode()` | **NO** |
| `write()` | **NO** |
| `read()` | **NO** |
| `addMethodNode()` | **NO** |
| `monitorVariable()` | **NO** |
| `shutdown()` | **NO** |

## Suggested fix

The native open62541 library shouldn't SEGFAULT when `deleteNode` and `addCustomType` are called in sequence on the same running server. This is a memory safety issue in the C library's internal bookkeeping — likely `deleteNode` frees a data type entry or node that `addCustomType` / `_findDataType` later traverses.

As a defensive measure on the Dart side, add a lifecycle/null guard to all public Server methods:

```dart
void _ensureValid() {
  if (_server == ffi.nullptr) {
    throw StateError('Server has been deleted');
  }
}

void addCustomType(NodeId typeId, DynamicValue value) {
  _ensureValid();  // <-- add this
  // ... existing implementation
}
```

This won't prevent the underlying issue (the server IS valid and running — it's the internal node state that's corrupted), but it would catch the case where the server pointer itself has been freed.

## Environment

- Dart 3.11.1 (stable), linux_x64, AOT compiled
- open62541_dart commit `33ed12b`
- open62541 (C library) bundled in the package
- Single Dart isolate, no multi-threading — the race is between async continuations on the same event loop
