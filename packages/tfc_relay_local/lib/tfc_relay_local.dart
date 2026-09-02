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
/// The contract comes first. `UpstreamLink` is exported before any adapter
/// implements it, because three adapters and one composer are all written
/// against it and an interface that arrives after its implementors is an
/// interface each of them invented separately.
library;

export 'src/epoch.dart';
export 'src/fanin.dart';
export 'src/freshness_sweep.dart';
export 'src/ingest.dart';
export 'src/key_router.dart';
export 'src/local_state_man.dart';
export 'src/m2400_upstream_link.dart';
export 'src/modbus_upstream_link.dart';
export 'src/opcua_upstream_link.dart';
export 'src/pipe_health.dart';
export 'src/string_encoding.dart';
export 'src/upstream_link.dart';
export 'src/value_shaping.dart';
// The write vocabulary the two DeviceClient adapters name in their own public
// signatures: `protocolFor` returns an `UpstreamProtocol` and
// `classifyWriteError` a `WriteAnswer`. Leaving this internal would make two
// members of an exported class unnameable outside the package — and
// `notWritableReason` is the gateway's single spelling of the read-only
// refusal, which a caller has to be able to compare against rather than
// re-spell. 08-06 anticipated this line ("the plan that first needs it from
// outside adds the export"); 08-10 is that plan.
export 'src/write_translation.dart';
