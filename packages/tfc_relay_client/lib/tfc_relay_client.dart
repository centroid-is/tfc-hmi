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
library;
