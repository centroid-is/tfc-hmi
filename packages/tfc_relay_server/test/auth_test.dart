@TestOn('vm')

/// SEC-03: the credential the gateway checks, the identity it produces, and
/// the revocation that closes a live session.
///
/// Three properties, in the order they are built:
///
///  1. **The token file is read, and four classes of bad file are refused at
///     load** — a duplicate `stationId`, an unknown role, a token below the
///     length floor, and a file any other account on the plant machine can
///     read. A load failure fails `RelayServer.start()`; there is no
///     permissive fallback, for the same reason a misspelled PEM has none.
///  2. **A session knows which station it is**, and the credential appears in
///     nothing that leaves the process — not the `-32003` message, not the
///     close reason, not a `status` frame, not the error sink.
///  3. **Removing a station's token and reloading closes that station's live
///     session with 4001**, observed by a real client on its own socket, and
///     leaves every other station alone.
///
/// Without (1) any peer that can reach the port is a panel. Without (3) a
/// station whose token has been pulled keeps actuating the plant until it
/// chooses to reconnect, which is not revocation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/auth/auth_config.dart';
import 'package:tfc_relay_server/src/auth/file_token_validator.dart';
import 'package:tfc_relay_server/src/auth/identity.dart';
import 'package:tfc_relay_server/src/error_codes.dart';
import 'package:tfc_relay_server/src/error_reporter.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/token_validator.dart';

import 'support/ws_harness.dart';

/// Tokens long enough to clear [FileTokenValidator.minTokenLength], and
/// visibly not words anyone would type by accident.
const _stationOneToken = 'ST101-1nZq4tGm7Yb2Kd8Vw6Rc0Pf3';
const _stationTwoToken = 'ST201-9aXe5uHj1Lo4Nm7Bs2Tv8Qi6';

/// The `hello` a station sends, with or without its credential.
///
/// Local rather than `ws_harness.dart`'s `helloParams()`, which takes no
/// token: this is the only file in the package that needs one on the wire.
HelloParams _helloWith(String? token) => HelloParams(
      protocol: protocolVersion,
      supported: const [protocolVersion],
      client: const PeerInfo('panel-under-test', '0.1.0'),
      token: token,
    );

/// A production fixture whose gateway checks [tokens], written to a temp file
/// this case owns.
///
/// `relayFixture` passes `const PermissiveTokenValidator()` for `validator:`,
/// which is the canonical default object `RelayServer` reads as "no validator
/// configured" — so a `ServerConfig.auth` beside it is not the two-sources-of-
/// truth configuration the constructor refuses.
RelayFixture _gatewayOn(Map<String, Object?> tokens, {RelayErrorHandler? onError}) =>
    relayFixture(
      config: ServerConfig(
        tick: ServerConfig.minTick,
        auth: AuthConfig(tokenFilePath: _writeTokenFile(_tempDir(), tokens)),
      ),
      onError: onError,
    );

/// A temp directory released with the case.
Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('relay-auth-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Writes a token file and locks it to the owner, which is the only mode the
/// loader accepts on POSIX.
String _writeTokenFile(Directory dir, Object? contents, {String mode = '600'}) {
  final file = File('${dir.path}/tokens.json');
  file.writeAsStringSync(contents is String ? contents : _json(contents));
  if (!Platform.isWindows) {
    Process.runSync('chmod', [mode, file.path]);
  }
  return file.path;
}

String _json(Object? value) => jsonEncode(value);

/// The one-station file every accept-path case starts from.
Map<String, Object?> _oneStation() => {
      'tokens': {
        _stationOneToken: {'stationId': 'ST101', 'role': 'operate'},
      },
    };

Map<String, Object?> _twoStations() => {
      'tokens': {
        _stationOneToken: {'stationId': 'ST101', 'role': 'operate'},
        _stationTwoToken: {'stationId': 'ST201', 'role': 'view'},
      },
    };

void main() {
  group('the token file is read, and a bad one is refused at load', () {
    test('a token file with two stations sharing an id is refused', () async {
      final path = _writeTokenFile(_tempDir(), {
        'tokens': {
          _stationOneToken: {'stationId': 'ST101', 'role': 'operate'},
          _stationTwoToken: {'stationId': 'ST101', 'role': 'view'},
        },
      });

      await expectLater(
          FileTokenValidator.load(path),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', allOf(contains('ST101'), contains(path)))),
          reason: 'two tokens answering to one station makes a revocation '
              'ambiguous: pulling one of them leaves the other still valid for '
              'the identity that was supposed to lose access, and the sweep '
              'cannot tell which live session to close');
    });

    test('a token shorter than the floor is refused', () async {
      final path = _writeTokenFile(_tempDir(), {
        'tokens': {
          'short-token': {'stationId': 'ST101', 'role': 'operate'},
        },
      });

      await expectLater(
          FileTokenValidator.load(path),
          throwsA(isA<FormatException>().having((e) => e.message, 'message',
              allOf(contains('ST101'), contains('${FileTokenValidator.minTokenLength}'), contains(path)))),
          reason: 'a short credential is a guessable one, and the message must '
              'name the station rather than the token so a support ticket that '
              'pastes it does not paste a credential');
    });

    test('an unknown role string is refused', () async {
      final path = _writeTokenFile(_tempDir(), {
        'tokens': {
          _stationOneToken: {'stationId': 'ST101', 'role': 'supervisor'},
        },
      });

      await expectLater(
          FileTokenValidator.load(path),
          throwsA(isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('supervisor'), contains('view'),
                  contains('operate'), contains(path)))),
          reason: 'a role nobody implements must not silently become the '
              'narrower one: the operator who wrote it believes the station '
              'has the access it names');
    });

    test('a group- or world-readable token file is refused', () async {
      final path = _writeTokenFile(_tempDir(), _oneStation(), mode: '644');

      await expectLater(
          FileTokenValidator.load(path),
          throwsA(isA<FileSystemException>()
              .having((e) => e.message, 'message', contains('readable'))),
          reason: 'the credential set is the plant\'s keys; a file every '
              'account on the machine can read is a credential set every '
              'account on the machine has');
    }, skip: Platform.isWindows ? 'POSIX file modes' : null);

    test('a token file the gateway cannot read at all fails the load', () async {
      final dir = _tempDir();

      await expectLater(
          FileTokenValidator.load('${dir.path}/absent.json'),
          throwsA(isA<FileSystemException>()),
          reason: 'there is no permissive fallback: a gateway that accepted '
              'every panel because somebody misspelled a path would look '
              'perfectly healthy');
    });
  });

  group('a good file produces identities', () {
    test('a valid token maps to its station identity', () async {
      final validator =
          await FileTokenValidator.load(_writeTokenFile(_tempDir(), _twoStations()));

      final accepted = await validator.validate(_helloWith(_stationTwoToken));

      expect(
          accepted,
          isA<TokenAccepted>().having((a) => a.identity, 'identity',
              const Identity(stationId: 'ST201', role: Role.view)));
    });

    test('an unknown or absent credential is refused, and the refusal never '
        'repeats it', () async {
      final validator =
          await FileTokenValidator.load(_writeTokenFile(_tempDir(), _oneStation()));

      const impostor = 'IMPOSTOR-4d2f8e1c6b9a3057fe4d2c8b';
      final unknown = await validator.validate(_helloWith(impostor));
      final absent = await validator.validate(_helloWith(null));

      expect(unknown, isA<TokenRejected>());
      expect(absent, isA<TokenRejected>());
      expect((unknown as TokenRejected).reason, isNot(contains(impostor)),
          reason: 'the reason reaches the client inside a -32003 message; a '
              'gateway that echoes the credential back has published it to '
              'every log that catches the refusal');
      expect((absent as TokenRejected).reason, isNotEmpty);
    });

    test('stillValid follows the file, not the session', () async {
      final dir = _tempDir();
      final path = _writeTokenFile(dir, _twoStations());
      final validator = await FileTokenValidator.load(path);

      const one = Identity(stationId: 'ST101', role: Role.operate);
      const two = Identity(stationId: 'ST201', role: Role.view);
      expect(validator.stillValid(one), isTrue);
      expect(validator.stillValid(two), isTrue);

      _writeTokenFile(dir, _oneStation());
      expect(validator.stillValid(two), isTrue,
          reason: 'nothing has been reloaded yet — a validator that answered '
              'from the disk on every call would be doing file I/O on the '
              'hello path');

      await validator.reload();
      expect(validator.stillValid(one), isTrue);
      expect(validator.stillValid(two), isFalse,
          reason: 'ST201\'s token is gone from the file, so its live session '
              'is the one the sweep must close');
    });

    test('a station whose role was narrowed is no longer the identity it '
        'holds', () async {
      final dir = _tempDir();
      final path = _writeTokenFile(dir, _oneStation());
      final validator = await FileTokenValidator.load(path);

      const operating = Identity(stationId: 'ST101', role: Role.operate);
      expect(validator.stillValid(operating), isTrue);

      _writeTokenFile(dir, {
        'tokens': {
          _stationOneToken: {'stationId': 'ST101', 'role': 'view'},
        },
      });
      await validator.reload();

      expect(validator.stillValid(operating), isFalse,
          reason: 'a session minted before the demotion is still carrying '
              'Role.operate. Leaving it live is the demotion not taking '
              'effect until the panel happens to reconnect');
    });

    test('reloadIfChanged re-reads only when the file changed', () async {
      final dir = _tempDir();
      final path = _writeTokenFile(dir, _twoStations());
      final validator = await FileTokenValidator.load(path);

      expect(await validator.reloadIfChanged(), isFalse,
          reason: 'the digest is unchanged, so a config-watch loop that fires '
              'on every notification must cost nothing — re-parsing here is '
              'how a re-save of an identical file churns every live session');

      _writeTokenFile(dir, _oneStation());
      expect(await validator.reloadIfChanged(), isTrue);
      expect(
          validator.stillValid(const Identity(stationId: 'ST201', role: Role.view)),
          isFalse);
    });
  });

  group('the permissive default is honestly labelled', () {
    test('the permissive validator grants operate, and names itself', () async {
      final verdict =
          await const PermissiveTokenValidator().validate(_helloWith(null));

      expect(
          verdict,
          isA<TokenAccepted>().having((a) => a.identity.role, 'role', Role.operate),
          reason: 'its semantics today are "everyone may do everything"; '
              'Role.operate is that written down, and a deployment still '
              'running one stays legible in a config diff');
      expect((verdict as TokenAccepted).identity.stationId,
          PermissiveTokenValidator.stationId);
      expect(PermissiveTokenValidator.stationId, contains('permissive'),
          reason: 'the station id a permissive gateway hands out must say what '
              'it is wherever it is printed');
    });

    test('an identity carries no credential and cannot be made to', () {
      const identity = Identity(stationId: 'ST101', role: Role.operate);

      expect(identity.toString(), contains('ST101'));
      expect(identity.toString(), isNot(contains(_stationOneToken)));
    });
  });

  group('AuthConfig holds a path and nothing else', () {
    test('an empty token path is refused at construction', () {
      expect(() => AuthConfig(tokenFilePath: ''), throwsArgumentError);
    });
  });

  group('a session knows which station it is', () {
    test('a valid token gives the session its station identity', () async {
      final fixture = _gatewayOn(_twoStations());
      await fixture.ready;

      final raw = await fixture.request(Methods.hello,
          params: _helloWith(_stationTwoToken).toJson(),
          what: 'the hello result over a real socket');

      expect(HelloResult.fromJson((raw as Map).cast<String, Object?>()).protocol,
          protocolVersion);
      expect(fixture.server.sessions.sessions.single.identity,
          const Identity(stationId: 'ST201', role: Role.view),
          reason: 'every surface downstream of the handshake asks the session '
              'which station it is; a session that carries a protocol and no '
              'identity is one the policy seam cannot answer about');
    }, tags: 'ws');

    test('a hello with no credential is refused when the gateway has a token '
        'file', () async {
      final fixture = _gatewayOn(_oneStation());
      await fixture.ready;
      final session = fixture.server.sessions.sessions.single;

      final refusal = await fixture.refusal(Methods.hello,
          params: _helloWith(null).toJson(),
          what: 'a tokenless hello against a gateway with a token file');

      expect(refusal.code, ServerErrorCodes.unauthorized);
      expect(session.identity, isNull);
      expect(session.sentCloseCode, CloseCodes.authExpired,
          reason: 'the refusal answers first and the close is scheduled for '
              'the next turn (relay_session.dart:846-849), so a panel learns '
              'why before it learns that');
    }, tags: 'ws');

    test('a permissive gateway still accepts a hello with no credential',
        () async {
      // The control. Without it, the case above passes against a gateway that
      // refuses every hello for any reason at all.
      final fixture = relayFixture();
      await fixture.ready;

      final result = await fixture.hello();

      expect(result.protocol, protocolVersion);
      expect(fixture.server.sessions.sessions.single.identity?.role,
          Role.operate);
    }, tags: 'ws');

    test('a second hello cannot change the session\'s identity', () async {
      final fixture = _gatewayOn(_twoStations());
      await fixture.ready;
      await fixture.request(Methods.hello,
          params: _helloWith(_stationOneToken).toJson(),
          what: 'the first hello');
      final session = fixture.server.sessions.sessions.single;

      final second = await fixture.refusal(Methods.hello,
          params: _helloWith(_stationTwoToken).toJson(),
          what: 'a second hello on a session that already has one');

      expect(second.code, ServerErrorCodes.alreadyHelloed);
      expect(session.identity?.stationId, 'ST101',
          reason: 'the credential is checked before the gate, so a second '
              'hello carrying another station\'s token reaches the validator. '
              'If it could overwrite the identity, a view station could talk '
              'its way into an operate one on a handshake the gate then '
              'refuses — the refusal being irrelevant, because the damage is '
              'the field, not the answer');
    }, tags: 'ws');

    test('the credential appears in no message, close reason, status frame or '
        'log', () async {
      // Distinctive enough that a substring hit cannot be a coincidence, and
      // long enough to clear the loader's floor so the only reason it is
      // refused is that it is not in the file.
      const presented = 'LEAKCANARY-8f3b1d64ac0e529716b4d8fa3c';
      final reported = <String>[];
      final fixture = _gatewayOn(_oneStation(),
          onError: (error, stack, what) =>
              reported.add('$what: $error\n$stack'));
      await fixture.ready;

      final refusal = await fixture.refusal(Methods.hello,
          params: _helloWith(presented).toJson(),
          what: 'a hello carrying a credential this gateway never issued');
      final close = await fixture.awaitClose('the refused session closing');

      // One rule, four surfaces, because a credential published on any of
      // them is published (T-06-26).
      expect(refusal.toString(), isNot(contains(presented)),
          reason: 'the -32003 message and its data reach the panel and every '
              'log that catches the refusal');
      expect(close.closeReason, isNotNull,
          reason: 'a null reason would satisfy every absence assertion below '
              'while proving nothing (06-02-SUMMARY deviation 3)');
      expect(close.closeReason, isNot(contains(presented)),
          reason: 'the close reason is displayed to an operator');
      expect(fixture.inbound.where((f) => f.contains(presented)), isEmpty,
          reason: 'every frame the client received, which is where a '
              'StatusParams.error would arrive');
      expect(reported.where((r) => r.contains(presented)), isEmpty,
          reason: 'the gateway\'s error sink — its log on a plant machine');
    }, tags: 'ws');
  });

  // A security property no behavioural case can see. The sabotage arm proved
  // it: replacing the accumulator with an early-exit compare — the exact
  // "simplification" a later reader makes — leaves every other case in this
  // file green, because early exit is *correct*, it is only not constant
  // time. A timing assertion would be a flake on a shared CI runner, so the
  // pin is structural instead, and it is stated plainly rather than implied
  // by a comment nobody has to keep true.
  group('the credential comparison does not exit early', () {
    final source =
        File('lib/src/auth/file_token_validator.dart').readAsStringSync();

    test('the source the pin reads is the real one', () {
      // Anti-vacuity: every assertion below passes against an empty string.
      expect(source, contains('class FileTokenValidator'),
          reason: 'the pin is reading the wrong file, and everything it '
              'reports is noise');
    });

    test('the lookup confirms the digest through the constant-time helper', () {
      expect(source, contains('_constantTimeEquals(entry.digest, presented)'),
          reason: 'the map lookup is a hash lookup over digests; the actual '
              'credential comparison is the line after it, and if that line '
              'stops calling the helper the property is gone');
    });

    test('the helper accumulates instead of returning at the first difference',
        () {
      final body = _functionBody(source, 'bool _constantTimeEquals(');
      final loop = body.indexOf('for (');
      expect(loop, greaterThanOrEqualTo(0),
          reason: 'the helper has no loop left in it: something replaced the '
              'byte-wise comparison with a whole-object one, which for two '
              'Uint8Lists is reference equality');

      final afterLoop = body.substring(loop);
      expect('return'.allMatches(afterLoop), hasLength(1),
          reason: 'there is more than one exit from the comparison loop, so '
              'how long the comparison takes depends on where the two digests '
              'first differ — which is the side channel the helper exists to '
              'close (T-06-28). Found:\n$afterLoop');
      expect(afterLoop, contains('^'));
      expect(afterLoop, contains('|='));
    });

    test('nothing in the file compares a token with ==', () {
      final offenders = <String>[];
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//') || line.startsWith('///')) continue;
        if (!line.contains('==')) continue;
        // `token == null` is a presence check on the reference, not a
        // comparison of the secret against anything.
        if (line.contains('token ==') && !line.contains('token == null')) {
          offenders.add('${i + 1}: $line');
        }
        if (line.contains('== token')) offenders.add('${i + 1}: $line');
      }
      expect(offenders, isEmpty,
          reason: 'a Dart String `==` short circuits on the first differing '
              'code unit. Found: $offenders');
    });
  });
}

/// The body of the top-level function whose declaration starts with
/// [signature], braces included.
///
/// The `ws_malformed_test.dart` precedent for `_defuse`: a structural pin has
/// to read the one function rather than the whole file, or a `return` anywhere
/// else in the file satisfies it.
String _functionBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) fail('$signature is not in the source any more');
  final open = source.indexOf('{', start);
  // Top-level function, so the closing brace is the first one at column zero.
  final close = source.indexOf('\n}', open);
  if (close < 0) fail('$signature has no closing brace at column zero');
  return source.substring(open, close);
}
