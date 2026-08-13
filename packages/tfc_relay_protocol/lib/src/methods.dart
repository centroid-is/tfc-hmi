/// Protocol version negotiated in `hello` (MCP-style: date-stamped, client
/// sends the newest it supports, server echoes or counter-offers).
const protocolVersion = '2026-08-13';

/// JSON-RPC method names.
///
/// Requests (carry an id, expect a result): [hello], [subscribe],
/// [unsubscribe], [write], [writeStatus], [ping], plus the timeseries /
/// history / preferences methods added in later steps.
///
/// Notifications (no id, never acknowledged): [update], [tick], [resync],
/// [status], [bye]. Nothing that needs an outcome may ever be sent as a
/// notification.
abstract final class Methods {
  static const hello = 'hello';
  static const subscribe = 'subscribe';
  static const unsubscribe = 'unsubscribe';
  static const write = 'write';
  static const writeStatus = 'writeStatus';
  static const ping = 'ping';

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
