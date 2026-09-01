/// The gateway's plant side.
///
/// This package will hold `LocalStateMan`: the `StateManApi` implementation
/// that talks to real hardware — OPC UA over `ClientWrapper`, classic Modbus
/// and UMAS-by-name over `ModbusDeviceClientAdapter`, and the M2400 weighers —
/// and turns what comes back into values that carry a quality and a source
/// time. With it come the pieces that only make sense next to it: the key
/// router, one `UpstreamLink` per configured server alias, the refcounted
/// fan-in that releases an upstream subscription when the last client
/// unsubscribes, the freshness sweep, and the `PIPE.*` health keys.
///
/// What this package is NOT is the front end. The WebSocket transport, the
/// JSON-RPC session layer, the tick engine and the send buffers are
/// `tfc_relay_server`, and the dependency edge runs one way only: this package
/// depends on that one. That is not a filing decision. `tfc_relay_server` has
/// zero native dependencies and a test pinning its `lib/src` to exactly one
/// `Timer.periodic`; putting the plant side in there would either break that
/// property or start an exemption list that erodes it, and would put an
/// open62541 native-asset build in front of 505 tests that have nothing to do
/// with a PLC.
///
/// Nothing is exported yet — the scaffold lands before the implementation, so
/// that the pinned binding, the analyzer and CI are all in place and green
/// before the first line of `LocalStateMan` is written.
library;
