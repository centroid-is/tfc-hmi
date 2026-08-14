/// Protocol version negotiated in `hello` (MCP-style: date-stamped, client
/// sends the newest it supports, server echoes or counter-offers).
const protocolVersion = '2026-08-13';

/// JSON-RPC method names.
///
/// Requests (carry an id, expect a result): [hello], [subscribe],
/// [unsubscribe], [write], [writeStatus], [read], [readFresh], [readMany],
/// [ping], plus the timeseries / history / preferences methods added in later
/// steps.
///
/// Notifications (no id, never acknowledged): [update], [tick], [resync],
/// [status], [bye] server→client, and [holdTick] client→server — the only
/// name a client sends without expecting an answer. Nothing that needs an
/// outcome may ever be sent as a notification, and a hold tick has none: the
/// engage and the release are ordinary [write] calls with three-state
/// outcomes, and the feed in between is liveness, whose whole safety property
/// is that it STOPS.
abstract final class Methods {
  static const hello = 'hello';
  static const subscribe = 'subscribe';
  static const unsubscribe = 'unsubscribe';
  static const write = 'write';
  static const writeStatus = 'writeStatus';

  /// The cached read — no round trip, answered from what the gateway last
  /// heard. `StateManApi.read`'s name, because it is the same concept.
  static const read = 'read';

  /// The forced round trip for one key — `StateManApi.readFresh`.
  static const readFresh = 'readFresh';

  /// One round trip for many keys — `StateManApi.readMany`.
  static const readMany = 'readMany';

  static const ping = 'ping';

  /// The hold-to-run deadman feed — client→server, one frame per tick period
  /// while a button is held, carrying [HoldTickParams] and no id.
  ///
  /// One character for the same reason [update] is: this is a hot path, and
  /// the wire spelling is a literal in the server's surface test either way.
  /// It is registered as a handler so json_rpc_2 dispatches it, but it is not
  /// one of the nine names a client may *call* — nothing is ever sent back.
  static const holdTick = 'h';

  static const update = 'u'; // hot path — one character on purpose
  static const tick = 'tick';
  static const resync = 'resync';
  static const status = 'status';
  static const bye = 'bye';
}

/// Application close codes (WebSocket 4000–4999 private range).
///
/// Standard codes other than 1000 throw in web_socket_channel (#1690), and
/// `closeCode` is unreliable for self-initiated closes (#1698) — both ends
/// track the codes they send themselves.
abstract final class CloseCodes {
  static const authExpired = 4001;
  static const serverDraining = 4002;
  static const heartbeatTimeout = 4003;
  static const backpressureOverrun = 4004;
  static const protocolMismatch = 4005;
}
