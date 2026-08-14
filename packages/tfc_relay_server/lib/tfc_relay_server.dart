/// The relay gateway: the WebSocket + JSON-RPC session layer that serves
/// `StateManApi` to every panel.
///
/// Pure Dart, server-side, no Flutter — and the Flutter app must not depend on
/// this package at all. The app depends on `tfc_relay_protocol`; this package
/// depends on `package:test` transitively through its own dev kit, and pulling
/// analyzer into the app's version solve is the analyzer-cap blocker that has
/// stopped this repo twice in twelve months.
///
/// This barrel is the embedder's whole surface: configure a server, supply a
/// token validator, start it. Deliberately *not* exported are the internal
/// seams — `relay_session`, `tick_engine`, `frame_encoder`, `handle_table`,
/// `subscription_registry` — because an embedder configures and starts a
/// server, it does not reach into a session. Tests inside this package import
/// those directly as `package:tfc_relay_server/src/<file>.dart`, which is legal
/// within the owning package and keeps this file from becoming an edit
/// chokepoint for every plan in the phase.
library;

export 'src/server_config.dart';
