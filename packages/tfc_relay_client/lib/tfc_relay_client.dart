/// The panel side of the relay pipe: `RemoteStateMan`, the `StateManApi`
/// implementation that speaks WebSocket + JSON-RPC to the gateway.
///
/// Pure Dart, no Flutter. The Flutter adapter is a later milestone, and this
/// package must keep resolving without it — pulling analyzer into the app's
/// version solve is the analyzer-cap blocker that has stopped this repo twice
/// in twelve months.
///
/// This barrel is the embedder's whole surface: build a `ClientConfig`, point
/// a client at a gateway, read values from it. Deliberately *not* exported are
/// the internal seams — the connection supervisor, the WS transport adapter,
/// the resync engine, the freshness watchdog, the deadline wrapper, the
/// backoff schedule — because an embedder constructs a `RemoteStateMan` and
/// reads values from it, it does not reach into a connection. Tests inside
/// this package import those directly as
/// `package:tfc_relay_client/src/<file>.dart`, which is legal within the
/// owning package and keeps this file from becoming an edit chokepoint for
/// every plan in the phase.
///
/// Exactly two plans of Phase 4 edit this file: 04-01 (which creates it and
/// exports the config) and 04-08 (which adds the client itself). Every other
/// plan imports internals.
///
/// What is here, and nothing else:
///
///  * [ClientConfig] — the deadlines, the backoff window, the staleness horizon.
///  * [RemoteStateMan] — the `StateManApi` an embedder holds, plus
///    `defaultPageSubscription`, the name its constructor keys are filed under.
///  * [LinkState] — the four-state connection indicator an operator-facing
///    health line renders. The supervisor that owns the state machine is not
///    exported with it: a caller reads where the link is, it does not drive the
///    reconnect loop.
///
/// Deliberately absent, and each for the same reason — an embedder constructs a
/// client and reads values from it, it does not reach into a connection:
/// `connection_supervisor.dart` (beyond [LinkState]), `ws_transport.dart`,
/// `resync_engine.dart`, `freshness_watchdog.dart`, `deadline.dart`,
/// `backoff.dart`, `readiness_barrier.dart`, `subscription_state.dart`,
/// `failure_taxonomy.dart`, `clock_offset.dart` and `client_sub_apis.dart`.
/// Tests inside this package import those directly as
/// `package:tfc_relay_client/src/<file>.dart`, which is legal within the owning
/// package.
library;

export 'src/client_config.dart';
export 'src/connection_supervisor.dart' show LinkState;
export 'src/remote_state_man.dart';
