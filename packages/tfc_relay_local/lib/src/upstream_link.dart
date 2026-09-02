/// The one shape every protocol adapter presents to `LocalStateMan`.
///
/// The gateway wraps the protocol clients this repository already has —
/// `ClientWrapper` for OPC UA, `ModbusDeviceClientAdapter` for classic Modbus
/// and UMAS-by-name, `M2400DeviceClientAdapter` for the weighers — and
/// replaces the 2,796-line `StateMan` composer above them, whose throwing
/// `read`/`write` and quality-less `DynamicValue` are the anti-pattern
/// `StateManApi` exists to replace. But `ClientWrapper` is **not** a
/// `DeviceClient` (`packages/tfc_dart/lib/core/state_man.dart:1190-1228`
/// declares that interface; the OPC UA wrapper is the fallthrough *inside*
/// `StateMan`, not an implementation of it), so [UpstreamLink] is a **third
/// shape** that can wrap either. And the type is what forces the two facts a
/// value must carry to exist: a link hands back `tfc_relay_protocol`'s
/// [DynamicValue], which has [DynamicValue.quality] and
/// [DynamicValue.sourceTime] as first-class fields, so there is no way to pass
/// a value into the gateway without them.
///
/// The seam is drawn at `DeviceClient` and not one layer up for a reason:
/// `DeviceClient.subscribe` is already a plain `Stream`
/// (`state_man.dart:1209`), while `StateMan.subscribe` is a
/// `Future<Stream<…>>` — the shape `state_man_api.dart:80-84` names as how a
/// widget ends up missing the first values of its own subscription. The seam
/// is clean below and dirty above.
///
/// This file declares and documents only. Three adapters (08-07, 08-10) and
/// the composer (08-05, 08-06) are written against it, and an interface that
/// arrives after its implementors is an interface each of them invented
/// separately.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The five link states, which are exactly the five `StatusParams.state`
/// already accepts on the wire.
///
/// `messages.dart:458-479` carries `alias`, `state` and an optional `error`,
/// and its doc pins the vocabulary to
/// `connected | connecting | disconnected | unhealthy | reprogrammed`. Note
/// that **`reprogrammed` is already the epoch-bump state** — the wire
/// anticipated the PLC-download case before this package existed.
///
/// **The wire vocabulary is the authority here, not this enum.** Adding a
/// sixth name to this enum without adding it to `StatusParams`'s documented
/// set produces a `StatusParams` that no client can decode: the client's
/// status handler (`connection_supervisor.dart:404`) switches on the string,
/// and an unknown string is a link state the operator's screen cannot render.
/// A sixth state is a wire change, and a wire change is a protocol decision.
enum UpstreamLinkState {
  /// The session is up and the link is serving values.
  connected,

  /// A connect or reconnect is in progress. Values are not yet trustworthy,
  /// but waiting is the right response.
  connecting,

  /// The channel or session is down. Every key on this link degrades to
  /// [Quality.badCommFault] (08-RESEARCH §C.4).
  disconnected,

  /// Connected, but not serving: the classic case is a live channel whose
  /// subscription has stopped publishing, which `ClientWrapper`'s
  /// heartbeat-derived `EffectiveDeviceStatus` (`state_man.dart:826-832`)
  /// already distinguishes from a clean disconnect.
  unhealthy,

  /// The PLC's identity changed underneath us — a program download, a
  /// namespace renumber, a server restart. Every [UpstreamRef] resolved under
  /// the previous epoch is stale by construction.
  reprogrammed;

  /// The lowercase string this state travels as in `StatusParams.state`.
  String get wireName => name;
}

/// An opaque, immutable handle to one point on one link.
///
/// **The epoch is not decoration.** A ref whose [epoch] is not its link's
/// current [UpstreamLink.epoch] is stale *by construction*, and every
/// read/write/subscribe path checks that before it touches the wire. SRV-07's
/// "no stale-handle read ever returns a value" is therefore a property of this
/// type, enforced once here, rather than a rule each of the three adapters has
/// to remember in 08-08. A handle that outlived a PLC download addresses a
/// NodeId that may now mean a different tag, and answering from it is not a
/// stale read — it is a confidently wrong one.
final class UpstreamRef {
  /// The link that issued this handle. A ref is never valid on another link.
  final String alias;

  /// The link's epoch at the moment [UpstreamLink.resolve] minted this handle.
  ///
  /// Opaque: only equality against the link's current epoch means anything.
  final String epoch;

  /// What the adapter needs to reach the point, in whatever shape that
  /// adapter uses: a `NodeId` for OPC UA, a register spec or a variable name
  /// for Modbus/UMAS, a record type plus a field name for the M2400. Never
  /// interpreted outside the adapter that produced it.
  final Object payload;

  /// The gateway key this handle was resolved from, kept for error messages.
  ///
  /// A `WriteRejected` reason or a bad-quality read that names only a NodeId
  /// is unactionable to the person reading the screen; they typed a key.
  final String key;

  const UpstreamRef({
    required this.alias,
    required this.epoch,
    required this.payload,
    required this.key,
  });

  @override
  bool operator ==(Object other) =>
      other is UpstreamRef &&
      other.alias == alias &&
      other.epoch == epoch &&
      other.payload == payload &&
      other.key == key;

  @override
  int get hashCode => Object.hash(alias, epoch, payload, key);

  @override
  String toString() => 'UpstreamRef($alias/$key @$epoch)';
}

/// One configured upstream server, behind one uniform surface.
///
/// Implementations wrap a protocol client; they do not re-implement one.
/// `ClientWrapper` alone encodes the two-phase resubscribe that fixed a
/// measured monitored-item storm and a heartbeat-derived effective status, and
/// none of that is worth rewriting.
abstract interface class UpstreamLink {
  /// The configured server alias, as it appears in `StatusParams.alias` and in
  /// the `PIPE.upstream.<alias>.*` keys.
  String get alias;

  /// The link's current state. Synchronous, so nothing goes stale between
  /// stream events.
  UpstreamLinkState get state;

  /// Transitions of [state]. One event per transition, never one per key: the
  /// mass degradation of a link's keys and the announcement of the link's
  /// state are separate acts (`fake_state_man.dart:598-605`), and at 1500 keys
  /// a per-key fan-out is a denial of service against the operator's screen.
  Stream<UpstreamLinkState> get stateStream;

  /// The last upstream error, **already redacted**.
  ///
  /// This becomes a subscribable key value in 08-09
  /// (`PIPE.upstream.<alias>.last_error`), which means an unprivileged panel
  /// can read it. An endpoint URL, a username or a certificate path left in an
  /// upstream error string is therefore plant-visible information disclosure
  /// (threat T-08-08), and the redaction has to happen at *this* boundary
  /// rather than at the point of display — by the time it is a key value it
  /// has already been fanned out to every subscriber.
  ///
  /// Use [redactUpstreamError]. One implementation, all three adapters: three
  /// hand-rolled redactions is three chances to miss the userinfo in a
  /// `opc.tcp://user:pass@host/` endpoint.
  String? get lastError;

  /// The link's identity generation. Opaque — only equality matters.
  ///
  /// Derived from an ordered list of inputs, any one of which changing bumps
  /// it (08-RESEARCH §C.2): `Server_ServerStatus_StartTime` (ns=0, i=2257),
  /// a hash of `Server_NamespaceArray` (i=2255), and an optional configured
  /// PLC build-stamp key. Multi-input because whether a TwinCAT program
  /// download moves `StartTime` is an open question, and a detector that is
  /// blind exactly when it matters is not a detector.
  String get epoch;

  /// Epoch changes. An event here means every [UpstreamRef] ever handed out by
  /// this link is now stale and must be re-resolved.
  Stream<String> get epochStream;

  /// How many times this link has entered [UpstreamLinkState.connected] since
  /// the process started.
  ///
  /// The Sparkplug `bdSeq` analogue: monotonic per process, incremented on
  /// each transition **into** connected, so a client can tell "the same
  /// session, still running" from "a new session that may have missed
  /// updates". `ClientWrapper.reconnectCount` (`state_man.dart:924`) is the
  /// existing input for the OPC UA case.
  int get birthCount;

  /// When the link was last observed to go down, or null if it never has.
  ///
  /// Null is the honest answer for a link that has been up since boot. Zero or
  /// the epoch instant would both read as a real death (`cert_health_state_man.
  /// dart:115-126`: never a plausible zero).
  DateTime? get lastDeathAt;

  /// Claims [key] and mints a handle for it, or answers null for "not mine".
  ///
  /// [mappingEntry] is the configured keymapping entry for [key]; the adapter
  /// is what knows whether that entry describes a node it can reach. The
  /// handle is stamped with the link's **current** [epoch] at this moment.
  ///
  /// Null rather than a throw is what makes the router's fallthrough order
  /// (08-04) possible without the router knowing a single protocol: it offers
  /// the key to each link in turn and takes the first handle it gets, exactly
  /// as `StateMan` falls through M2400 → Modbus → OPC UA today
  /// (`state_man.dart:2054-2084`) but without the protocol knowledge baked
  /// into the router.
  UpstreamRef? resolve(String key, Object mappingEntry);

  /// Values for [ref], as a **plain Stream**.
  ///
  /// Deliberately not a `Future<Stream<…>>`, quoting
  /// `state_man_api.dart:80-84`: a future-of-stream forces every call site to
  /// await before it can even listen, which is how a widget ends up missing
  /// the first values of its own subscription. `DeviceClient.subscribe`
  /// already gets this right (`state_man.dart:1209`) and this seam keeps it.
  ///
  /// A stale [ref] must not stream values. It emits a bad-quality value and
  /// keeps the stream open; it does not end, because an ended stream is
  /// indistinguishable to a widget from a key that stopped changing
  /// (`AutoDisposingStream`'s close-on-source-end, `state_man.dart:2691`, is
  /// on the do-not-inherit list).
  Stream<DynamicValue> subscribe(UpstreamRef ref);

  /// The last known value for [ref], synchronously, or null if none is known.
  ///
  /// Never a round trip — the `DeviceClient.read` convention
  /// (`state_man.dart:1212`). Null means "nothing has arrived yet", which is a
  /// different statement from a known value under a bad quality.
  DynamicValue? peek(UpstreamRef ref);

  /// Reads [ref] from the wire, bounded by [deadline].
  ///
  /// **Never throws.** A failure is a [DynamicValue] carrying a bad quality
  /// and a null value — a timeout is [Quality.badCommFault], a tag that has
  /// left the address space is [Quality.errorConfig] (§C.4's table). A read
  /// that throws is a read whose caller has to decide what quality to invent,
  /// and the whole point of this seam is that quality is never invented.
  ///
  /// [deadline] is **required and has no default**, so an unbounded upstream
  /// await cannot be written by omission. This signature refuses to inherit
  /// `state_man.dart:1868`'s `await client.awaitConnect()` inside `read`: a
  /// disconnected PLC leaves that future pending forever, which is Phase 2's
  /// "a lost response leaves sendRequest pending FOREVER" finding wearing a
  /// different hat (threat T-08-10).
  ///
  /// A `DynamicValue` arriving is not evidence of freshness. Off a monitored
  /// item the binding delivers Bad samples with `hasValue` **clear** — a
  /// status code and a source time and no payload at all (08-01) — so a caller
  /// must read [DynamicValue.quality], not the fact that something arrived.
  Future<DynamicValue> read(UpstreamRef ref, {required Duration deadline});

  /// Writes [value] to [ref] under the operator's [cmd], bounded by
  /// [deadline].
  ///
  /// **Never throws**, and answers the sealed three-state [WriteResult].
  /// 08-RESEARCH §B.3, as prose:
  ///
  ///  * An echo or a Good status is [WriteApplied] — and "applied" means
  ///    applied *and read back*, because readback is the only confirmation
  ///    this system accepts.
  ///  * A **named refusal** is [WriteRejected]: OPC UA's `BadUserAccessDenied`,
  ///    `BadOutOfRange`, `BadTypeMismatch` or `BadNotWritable`; a classic
  ///    Modbus exception code; a typed `UmasException`. The device said no,
  ///    and said why.
  ///  * A timeout, or a channel loss with the request **already on the wire**,
  ///    is [WriteUnknown] — never [WriteRejected]. This is the distinction the
  ///    whole write path exists to preserve: "it did not happen" and "I cannot
  ///    tell whether it happened" are different things to tell an operator
  ///    standing next to the machine.
  ///
  /// And the standing rule, which belongs on the interface rather than in each
  /// adapter: **no auto-retry, at any layer, ever.** Not on a timeout, not on
  /// a reconnect, not "just once more". The three-state outcome is what makes
  /// a retry the operator's decision, and readback is the only confirmation.
  /// A well-meaning wrapper that re-sends an unknown write is exactly what the
  /// no-retry seam sweep in `freeze_test.dart` is pointed at.
  /// [hasExpect] says whether the caller supplied a compare-and-set value that
  /// `LocalStateMan._settle` has **already evaluated and matched**.
  ///
  /// It is not the `expect` itself, and deliberately so: the comparison is
  /// against the last value the gateway heard, which only the composer knows.
  /// What an adapter needs is the one bit — *was this write guarded* — and the
  /// only thing that reads it today is the array-element ruling
  /// ([guardArrayElementWrite]), where a read-modify-write is safe under a
  /// comparison and a silent overwrite of another operator's setpoint without
  /// one.
  ///
  /// 08-REVIEW WR-02: the bit existed on the guard and the one call site
  /// passed the literal `false`, because `_crossIntoThePlant` was not carrying
  /// it. The result was fail-safe but the parameter was dead, the documented
  /// escape was unreachable, and an operator who supplied `expect` correctly
  /// was told by name to supply `expect` — a message that sends them looking
  /// for a mistake they did not make.
  Future<WriteResult> write(
    UpstreamRef ref,
    DynamicValue value, {
    required String cmd,
    required Duration deadline,
    bool hasExpect = false,
  });

  /// Whether this link can write at all.
  ///
  /// False for the M2400, which is read-only by protocol. That **must** become
  /// a [WriteRejected] with `Bad_NotWritable`, not an `UnsupportedError`:
  /// `M2400DeviceClientAdapter.write` throws one today
  /// (`state_man.dart:1266-1268`) and `state_man_api.dart:114-117` names that
  /// throw as what not to copy. A throw on the write path reads to the
  /// operator as "the write failed", which is the one thing a refusal to try
  /// does not prove about the plant.
  bool get supportsWrites;

  /// Whether this link can browse a live address space.
  ///
  /// Backs `BrowseApi` per alias. False does not mean the alias has no keys —
  /// the keymapping list is always browsable; it means the *live* address
  /// space is not.
  bool get supportsBrowse;

  /// Opens the link, bounded by [deadline]. Required, no default, same reason
  /// as [read].
  ///
  /// The link **constructs cheaply and connects on demand**, copying
  /// `createM2400DeviceClients`'s division of labour: that factory builds one
  /// wrapper per enabled config and says in so many words that "the caller is
  /// responsible for calling connect() and dispose() on the returned clients"
  /// (`state_man.dart:1292-1293`). Here the caller is `LocalStateMan`.
  Future<void> connect({required Duration deadline});

  /// Closes the link and releases everything it holds.
  ///
  /// No `.timeout` on this path (project memory: no `.timeout` in dispose
  /// paths — a dispose that gives up half way leaves the thing it was
  /// disposing in a state nobody owns).
  ///
  /// **"Everything it holds" includes a protocol client handed in through a
  /// constructor seam.** An injected client was *handed over*, not lent: the
  /// composition root builds it because only the composition root knows the
  /// credentials, and it has nowhere to keep it afterwards. 08-REVIEW WR-03 is
  /// what that ambiguity cost — the OPC UA adapter released only the clients
  /// it had built itself, so a credentialed gateway left a spawned
  /// `ClientIsolate` alive, and a live isolate keeps the VM alive: the process
  /// logged "stopping", finished `stop()`, and hung until the container
  /// runtime escalated to SIGKILL.
  ///
  /// An implementation with a client seam must therefore delete what it was
  /// given, and a caller must not use an injected client after handing it over.
  Future<void> dispose();

  /// Monotonic count of subscriptions this link has asked the server to
  /// create.
  ///
  /// **Count deltas of creates. Never balances.** One logical OPC UA key is
  /// *four* monitored items — `monitor()` requests DataType, Value,
  /// Description and DisplayName (`state_man.dart:848-861`) — so the absolute
  /// number never equals the number of keys and no test should expect it to.
  /// And there is deliberately **no delete counter**: the binding's `onCancel`
  /// is a block body that discards the inner future, so a cancel completes
  /// locally the moment it is requested and never when the server acknowledges
  /// the delete. A counter fed from that would read healthy during exactly the
  /// leak it was added to catch.
  ///
  /// So a fan-in leak test asserts that N client subscriptions to one key
  /// produce **one** delta here, and that the delta after unsubscribe-then-
  /// resubscribe is one more — it never asserts that creates minus deletes is
  /// zero, because the second number does not exist and must not be invented.
  int get upstreamSubscriptionsCreated;
}

/// Strips credentials, endpoints and filesystem paths out of an upstream error
/// before it can become a subscribable value.
///
/// The threat is not an attacker inside the error string; it is the ordinary
/// case (T-08-08). open62541, the Modbus stack and `dart:io` all put the thing
/// they were talking to into the message — `opc.tcp://svc:hunter2@10.104.29.11:
/// 4840/`, `/etc/centroid/certs/client.pem`, `SocketException: … address =
/// 10.104.29.71` — and 08-09 turns `lastError` into
/// `PIPE.upstream.<alias>.last_error`, which any panel may subscribe to. The
/// alias is already public; the credential, the certificate path and the plant
/// topology are not.
///
/// Deliberately over-broad. Redacting a version string that looks like an IPv4
/// address costs a diagnostic detail; missing a password costs a credential,
/// and the redacted forms still say *what kind* of thing was removed. The
/// unredacted string stays available to the gateway's own log, which is not a
/// key.
///
/// **Over-broad still has an edge, and it is written down.** 08-REVIEW WR-11
/// added IPv6 literals and the `address = <token>` shapes — the latter being
/// the only rule that can catch a DNS hostname, which names a PLC and a site
/// as plainly as an address does and which no literal pattern will ever match.
/// The IPv6 rules stop short of two-colon runs on purpose: `09:49:57` is a
/// timestamp, and a redactor that ate every clock time would make this key
/// unreadable in exchange for nothing.
String? redactUpstreamError(String? raw) {
  if (raw == null) return null;
  var out = raw;

  // Any scheme://… — this is the one that carries userinfo, so it goes first
  // and takes the credentials with it.
  out = out.replaceAll(
      RegExp(r'\b[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s,;)"' "'" r']+'), '<endpoint>');

  // Windows paths (certificate stores, key files).
  out = out.replaceAll(
      RegExp(r'[a-zA-Z]:\\[^\s,;)"' "'" r']*'), '<path>');

  // Absolute POSIX paths. Two segments minimum, so ordinary prose containing
  // "and/or" survives and "/etc/ssl/private/client.pem" does not.
  out = out.replaceAll(
      RegExp(r'/(?:[A-Za-z0-9._@\-]+/)+[A-Za-z0-9._@\-]*'), '<path>');

  // key=value credentials that never had a scheme in front of them.
  out = out.replaceAllMapped(
      RegExp(
          r'\b(user|username|uid|login|password|passwd|pwd|token|secret|api[_-]?key)'
          r'\s*[=:]\s*\S+',
          caseSensitive: false),
      (m) => '${m[1]}=<redacted>');

  // The shapes `dart:io` writes a peer in: `address = <token>`,
  // `host = <token>`. This one comes BEFORE the literal patterns below because
  // it is the only one that can catch a **DNS hostname** — `st101.svn.local`
  // names the PLC and the site as plainly as an address does, and no literal
  // pattern will ever match it (08-REVIEW WR-11). The label is kept so the
  // message still reads.
  out = out.replaceAllMapped(
      RegExp(r'\b(address|host|hostname|remoteAddress|peer)\s*[=:]\s*([^\s,;)]+)',
          caseSensitive: false),
      (m) => '${m[1]} = <host>');

  // Bare hosts: an IPv4 literal with an optional port.
  out = out.replaceAll(
      RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b'), '<host>');

  // IPv6 literals, in the two shapes that actually occur (08-REVIEW WR-11).
  //
  // **The bracketed form first**, because it carries the port inside a
  // structure the bare patterns would only half-eat.
  out = out.replaceAll(
      RegExp(r'\[[0-9A-Fa-f:]{2,}\](?::\d+)?'), '<host>');

  // Then the two bare forms. The threshold is not arbitrary and it is where
  // "deliberately over-broad" has to stop: a compressed address is recognised
  // by its `::`, and an uncompressed one by having **at least three** colons.
  // Two colons is `09:49:57`, and redacting every timestamp in every message
  // would make `last_error` unreadable for the sake of nothing.
  out = out.replaceAll(
      RegExp(r'(?<![\w:])[0-9A-Fa-f]{0,4}::[0-9A-Fa-f:]*[0-9A-Fa-f](?::\d+)?'),
      '<host>');
  out = out.replaceAll(
      RegExp(r'(?<![\w:])[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){3,}(?![\w:])'),
      '<host>');

  // A key value is read on a screen. An unbounded error string is also an
  // unbounded thing to fan out to every subscriber of that key.
  return out.length <= maxRedactedErrorLength
      ? out
      : '${out.substring(0, maxRedactedErrorLength)}…';
}

/// How much of an upstream error survives redaction.
///
/// Long enough to name the failure, short enough that a link flapping under a
/// verbose stack trace cannot push kilobytes per event at every subscriber of
/// `PIPE.upstream.<alias>.last_error`.
const int maxRedactedErrorLength = 200;
