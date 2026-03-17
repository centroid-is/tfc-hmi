/// Mock MCP transport helpers for Flutter-side MCP bridge testing.
///
/// For full in-process transport testing, see the server-side
/// [MockMcpClient] in packages/tfc_mcp_server/test/helpers/.
/// This helper is for simpler unit tests that just need to verify
/// bridge state management without spawning a real subprocess.
library;

/// Tracks calls made to a simulated MCP transport.
class MockTransportTracker {
  bool startCalled = false;
  bool closeCalled = false;
  int sendCount = 0;

  void recordStart() => startCalled = true;
  void recordClose() => closeCalled = true;
  void recordSend() => sendCount++;

  void reset() {
    startCalled = false;
    closeCalled = false;
    sendCount = 0;
  }
}
