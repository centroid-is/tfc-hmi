/// The real credential check behind the Phase 3 seam: a mounted JSON file
/// mapping each station's token to its [Identity], and the two operations a
/// revocation needs.
///
/// **The file, and why it is keyed by token.**
/// `{"tokens": {"<token>": {"stationId": "...", "role": "view"|"operate"}}}`
/// (06-RESEARCH §D.3). Keyed by the credential rather than by the station so
/// a hello is answered by one lookup instead of a scan that compares every
/// secret in the file against the presented one — a loop whose *length* is a
/// function of how early the match is found.
///
/// **What is actually held in memory is a digest, not a credential.** The
/// parsed map is keyed by the SHA-256 of each token, so this object can be
/// dumped, inspected in a debugger or serialised by accident without
/// publishing the plant's keys. It also makes the lookup honest: the `==`
/// inside `Map` compares *digests*, which are fixed-length and preimage
/// resistant, and the confirmation that follows is
/// [_constantTimeEquals] over two 32-byte buffers. A Dart `String` `==` short
/// circuits on the first differing code unit and this is the one place in
/// this codebase where that is worth caring about (T-06-28).
///
/// **Four classes of bad file are refused at load, and a load failure fails
/// `RelayServer.start()`.** There is deliberately no permissive fallback, for
/// the same reason a misspelled PEM has none (`server_config.dart:169-175`):
/// a gateway that admitted every panel because somebody fat-fingered a path
/// would look perfectly healthy from every screen in the plant.
///
/// Without this file SEC-03 has a seam and nothing behind it — any peer that
/// can reach the port is a panel, and pulling a station's token off the disk
/// changes nothing about the session it already has.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../token_validator.dart';
import 'identity.dart';

/// A [TokenValidator] whose answers can change while the gateway is running.
///
/// A **second interface** rather than two more members on [TokenValidator],
/// so `PermissiveTokenValidator` and every test stand-in in this workspace —
/// `session_hello_test.dart`'s `_RejectingValidator` among them — are
/// untouched by revocation existing. `RelayServer.reloadTokens` type-tests for
/// this and throws when the live validator is not one, rather than no-opping:
/// a deployment that believes rotation works and has it silently do nothing is
/// worse off than one that is told at the first attempt.
abstract interface class RevocableTokenValidator implements TokenValidator {
  /// Re-reads the credential set from wherever it lives. Throws exactly what
  /// the initial load throws, and on a throw the previously loaded set is
  /// **kept** — a rotation that produced a broken file must not disconnect the
  /// plant.
  Future<void> reload();

  /// Whether the credential a live session authenticated with still buys
  /// [identity].
  ///
  /// False in all four ways a credential stops being valid:
  ///
  ///  * the station's token is **gone**;
  ///  * it now maps to a **different station**;
  ///  * the station's **role has been narrowed** — a demotion that only took
  ///    effect on the next reconnect would be a demotion an operator could
  ///    postpone indefinitely by not reconnecting;
  ///  * the token has been **replaced**, which is the remediation a leaked
  ///    credential actually gets. Nothing about the station's [Identity]
  ///    changes when an operator mints a new secret for it, so this is the
  ///    case an identity comparison structurally cannot see, and it is the
  ///    primary incident's primary fix.
  ///
  /// [credentialDigest] is [TokenAccepted.credentialDigest] as recorded on the
  /// session. It is nullable rather than required because a session may have
  /// been authenticated by a validator that produced none, in which case the
  /// answer necessarily falls back to what the file says about the station —
  /// which cannot distinguish a replacement from a re-save.
  bool stillValid(Identity identity, Uint8List? credentialDigest);
}

/// Reads per-station tokens from a mounted JSON file.
final class FileTokenValidator implements RevocableTokenValidator {
  FileTokenValidator._(this.path, this._set);

  /// The shortest token this gateway will load.
  ///
  /// 24 characters of the alphabet a provisioning script produces is well past
  /// anything an online guessing attack reaches through a WebSocket handshake,
  /// and short enough that nobody is tempted to shorten it further. The floor
  /// is enforced at *load*, not at hello: the operator who typed a four-letter
  /// token finds out when the gateway refuses to start, standing next to it,
  /// rather than never.
  static const int minTokenLength = 24;

  /// The file this validator was loaded from, re-read by [reload].
  final String path;

  _TokenSet _set;

  /// Reads and validates [path], or throws.
  ///
  /// Async because it is I/O and because `RelayServer.start()` — the only
  /// production caller — is already async. Refusals are [FormatException] for
  /// a file whose *contents* are wrong and [FileSystemException] for one whose
  /// *mounting* is wrong, so a deployment can tell "fix the JSON" from "fix
  /// the mount" without reading the message.
  static Future<FileTokenValidator> load(String path) async =>
      FileTokenValidator._(path, await _read(path));

  @override
  Future<void> reload() async => _set = await _read(path);

  /// Re-reads only when the file's bytes changed, and reports whether they
  /// did.
  ///
  /// The digest-not-content discipline `preferences_watch.dart:19-25` already
  /// uses on the backend: a config watch fires on every notification, and a
  /// re-save of an identical file must cost nothing. Without this, a `NOTIFY`
  /// storm would re-parse the file and — because `reloadTokens` sweeps after
  /// every reload — walk the whole registry each time.
  ///
  /// Deliberately **not** on [RevocableTokenValidator]: an in-memory
  /// implementation has no digest to compare, and an interface member that
  /// only one implementation can mean is an interface member that gets
  /// implemented as `=> true`.
  Future<bool> reloadIfChanged() async {
    final next = await _read(path);
    if (_hex(next.digest) == _hex(_set.digest)) return false;
    _set = next;
    return true;
  }

  /// Whether the credential this session presented still buys the identity it
  /// is carrying.
  ///
  /// **The digest is the question, and the identity is only half of it.**
  /// Asking `byStation[stationId] == identity` answers "is this station still
  /// entitled to this", which is true of a station whose token was replaced —
  /// and a replacement is what a leaked credential is remediated with. Looking
  /// the *digest* up and then comparing what it buys subsumes all four cases
  /// at once: a removed token is not in the map, a renamed or demoted station
  /// resolves to a different [Identity], and a replaced token is not in the
  /// map either, because the digest of the credential the session is holding
  /// is not the digest of the one the file now carries.
  ///
  /// A session with no digest falls back to the station comparison. That is
  /// the honest answer for a validator that produced none rather than a
  /// pretence of one, and it is what every case here that constructs an
  /// [Identity] by hand is exercising.
  @override
  bool stillValid(Identity identity, Uint8List? credentialDigest) {
    if (credentialDigest == null) {
      return _set.byStation[identity.stationId] == identity;
    }
    final entry = _set.entryFor(credentialDigest);
    return entry != null && entry.identity == identity;
  }

  @override
  Future<TokenVerdict> validate(HelloParams params) async {
    final token = params.token;
    // Note what is *not* in any of these reasons. The client did send the
    // credential, which is exactly why `TokenRejected`'s "nothing the client
    // did not already send" rule is not enough on its own: the reason travels
    // into a `-32003` message, into the gateway's log and into whatever the
    // operator's screen makes of both (T-06-26).
    if (token == null || token.isEmpty) {
      return const TokenRejected('no credential presented on hello; this '
          'gateway is configured with a token file and every station needs '
          'the token mounted beside it');
    }
    final entry = _set.lookup(token);
    if (entry == null) {
      return const TokenRejected('the credential presented is not in this '
          'gateway\'s token file; it was removed, or this panel was '
          'provisioned against another gateway');
    }
    // The digest, not the token: what the session records beside its identity
    // is what lets a later sweep tell "still this station" from "still this
    // credential". See [TokenAccepted.credentialDigest].
    return TokenAccepted(entry.identity, credentialDigest: entry.digest);
  }

  static Future<_TokenSet> _read(String path) async {
    final file = File(path);
    // `stat` before `read`: a world-readable credential file has already
    // leaked, and reading it into this process first does not make that
    // better, but refusing before the bytes are in memory keeps the failure
    // path from being the one that loads them.
    _refuseLoosePermissions(file);
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes);

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('the token file $path is not valid JSON: '
          '${error.message}');
    }
    if (decoded is! Map || decoded['tokens'] is! Map) {
      throw FormatException('the token file $path has no "tokens" object; the '
          'shape is {"tokens": {"<token>": {"stationId": "...", "role": '
          '"view"|"operate"}}}');
    }

    final byDigest = <String, _Entry>{};
    final byStation = <String, Identity>{};
    (decoded['tokens'] as Map).forEach((rawToken, rawEntry) {
      if (rawToken is! String || rawEntry is! Map) {
        throw FormatException('the token file $path has an entry that is not '
            'a token mapped to an object');
      }
      final stationId = rawEntry['stationId'];
      if (stationId is! String || stationId.isEmpty) {
        throw FormatException('the token file $path has an entry with no '
            'stationId; every token names the station it belongs to, and the '
            'station is what a revocation is about');
      }
      if (rawToken.length < minTokenLength) {
        // Names the station, never the token: this message reaches a log and
        // a support ticket.
        throw FormatException('the token for station $stationId in $path is '
            '${rawToken.length} characters; the floor is $minTokenLength. A '
            'short credential is a guessable one, and a gateway on a plant '
            'LAN answers guesses all day');
      }
      final role = _role(rawEntry['role'], stationId, path);
      final identity = Identity(stationId: stationId, role: role);

      final clash = byStation[stationId];
      if (clash != null) {
        throw FormatException('two tokens in $path both name station '
            '$stationId. One station, one credential: with two, pulling one '
            'of them revokes nothing and the sweep cannot tell which live '
            'session lost its access');
      }
      byStation[stationId] = identity;
      final digest = _sha256(utf8.encode(rawToken));
      byDigest[_hex(digest)] = _Entry(digest, identity);
    });

    return _TokenSet(byDigest, byStation, _sha256(bytes));
  }

  static Role _role(Object? raw, String stationId, String path) {
    for (final role in Role.values) {
      if (role.name == raw) return role;
    }
    throw FormatException('station $stationId in $path has role "$raw", which '
        'this gateway does not implement. The roles are '
        '${Role.values.map((r) => r.name).join(' and ')}. A role nobody '
        'implements must not quietly become the narrower one: whoever wrote '
        'it believes that station has the access it names');
  }

  static void _refuseLoosePermissions(File file) {
    if (Platform.isWindows) return;
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileSystemException(
          'the token file is not there. There is no permissive fallback: a '
          'gateway that admitted every panel because a path was misspelled '
          'would look healthy from every screen in the plant',
          file.path);
    }
    // 0o077 — any group or other bit.
    if (stat.mode & 0x3F != 0) {
      throw FileSystemException(
          'the token file is readable by group or other (mode '
          '${(stat.mode & 0x1FF).toRadixString(8).padLeft(3, '0')}); it must '
          'be 0600 and owned by the gateway. This file is the plant\'s keys, '
          'and a file every account on the machine can read is a credential '
          'set every account on the machine has',
          file.path);
    }
  }
}

/// One loaded credential set: the lookup, the station index, and the digest of
/// the bytes it came from.
final class _TokenSet {
  const _TokenSet(this._byDigest, this.byStation, this.digest);

  /// SHA-256 hex of a token → what that token buys, and the digest bytes
  /// themselves. See the library doc on why the plaintext credential is not a
  /// key here.
  final Map<String, _Entry> _byDigest;

  /// Station id → identity, which is what [FileTokenValidator.stillValid]
  /// reads. Also what makes a duplicate station id detectable at load.
  final Map<String, Identity> byStation;

  /// The digest of the whole file, for [FileTokenValidator.reloadIfChanged].
  final Uint8List digest;

  /// The presented [token] resolved to the row it matches, or null.
  ///
  /// Two steps on purpose. The map lookup is O(1) and its internal `==`
  /// compares digests rather than secrets; the [_constantTimeEquals] that
  /// follows is the actual credential comparison, over two buffers that are
  /// 32 bytes long whatever the token was. Anyone replacing the second step
  /// with `a == b` re-introduces the early-exit compare the first step was
  /// arranged to avoid — `auth_test.dart` greps this file for exactly that.
  ///
  /// The whole row rather than just the identity, because the caller needs the
  /// digest too: it is what travels onto the session and what makes a
  /// *replaced* token detectable.
  _Entry? lookup(String token) {
    final presented = _sha256(utf8.encode(token));
    final entry = _byDigest[_hex(presented)];
    if (entry == null) return null;
    if (!_constantTimeEquals(entry.digest, presented)) return null;
    return entry;
  }

  /// The row [digest] names, or null when no loaded credential hashes to it.
  ///
  /// No constant-time step here and none needed: the argument is a digest this
  /// gateway itself produced and has been holding since the handshake, not
  /// something a peer just presented, so there is nobody on the other end of
  /// the timing.
  _Entry? entryFor(Uint8List digest) => _byDigest[_hex(digest)];
}

/// One row of the loaded file: the digest the credential hashes to, and the
/// identity it buys.
final class _Entry {
  const _Entry(this.digest, this.identity);

  /// The stored SHA-256 of the token, kept as bytes so the confirmation in
  /// [_TokenSet.lookup] compares two real buffers rather than re-deriving one
  /// from the other — a comparison of a value against itself is constant time
  /// and proves nothing.
  final Uint8List digest;

  final Identity identity;
}

/// Whether two fixed-length buffers are equal, in time that does not depend on
/// where they first differ.
///
/// Not a hand-rolled primitive — the hash is `package:pointycastle`'s, already
/// a direct dependency of this package for the certificate work (T-06-SC: this
/// plan installs nothing). What is hand-written is the comparison itself,
/// which is the one thing a library cannot be asked for here: `==` on `String`
/// and on `List<int>` both return the moment they find a difference, and the
/// moment they return is the side channel.
///
/// The length check is outside the accumulator on purpose: the inputs are
/// always digests of the same algorithm, so a length mismatch is a programming
/// error rather than an attacker's probe, and folding it into the loop would
/// only make that bug harder to read.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

Uint8List _sha256(List<int> bytes) =>
    SHA256Digest().process(Uint8List.fromList(bytes));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
