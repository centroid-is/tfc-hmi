import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_access/tfc_access.dart';

/// Read a file relative to the package root, wherever `dart test` was invoked
/// from. Same reasoning as `package_purity_test.dart`: a source-text assertion
/// that cannot find its file must say so, not quietly do nothing.
String _source(String relative) {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: tfc_access')) {
      return File('${dir.path}/$relative').readAsStringSync();
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('could not locate the tfc_access package root from '
          '${Directory.current.path}');
    }
    dir = parent;
  }
}

/// Every test in this file runs with the iteration hook clamped to 10.
///
/// A production-strength derivation is tens of seconds in the debug-mode test
/// VM, and this suite performs dozens of them. If this file ever starts taking
/// minutes, the hook has stopped being honoured somewhere — that is the failure
/// this arrangement is meant to make loud.
void main() {
  setUp(() => Pbkdf2Kdf.iterationsForTest = 10);
  tearDown(() => Pbkdf2Kdf.iterationsForTest = null);

  group('Pbkdf2Kdf.iterations', () {
    test('is defaultIterations when the hook is null', () {
      Pbkdf2Kdf.iterationsForTest = null;
      expect(Pbkdf2Kdf.iterations, Pbkdf2Kdf.defaultIterations);
      expect(Pbkdf2Kdf.defaultIterations, 200000);
    });

    test('is the hook value when the hook is set', () {
      Pbkdf2Kdf.iterationsForTest = 10;
      expect(Pbkdf2Kdf.iterations, 10);
    });
  });

  group('Pbkdf2Kdf.deriveKey', () {
    test('is deterministic for the same passphrase, salt and iterations',
        () async {
      final salt = List<int>.generate(16, (i) => i);
      final a = await Pbkdf2Kdf.deriveKey(passphrase: 'hunter2', salt: salt);
      final b = await Pbkdf2Kdf.deriveKey(passphrase: 'hunter2', salt: salt);
      expect(await a.extractBytes(), await b.extractBytes());
    });

    test('produces different bytes for a different salt', () async {
      final a = await Pbkdf2Kdf.deriveKey(
        passphrase: 'hunter2',
        salt: List<int>.generate(16, (i) => i),
      );
      final b = await Pbkdf2Kdf.deriveKey(
        passphrase: 'hunter2',
        salt: List<int>.generate(16, (i) => i + 1),
      );
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });

    test('produces different bytes for a different passphrase', () async {
      final salt = List<int>.generate(16, (i) => i);
      final a = await Pbkdf2Kdf.deriveKey(passphrase: 'hunter2', salt: salt);
      final b = await Pbkdf2Kdf.deriveKey(passphrase: 'hunter3', salt: salt);
      expect(await a.extractBytes(), isNot(await b.extractBytes()));
    });

    test('honours an explicit iteration count over the ambient one', () async {
      // This is the case SecureEnvelope.decrypt depends on: an envelope made
      // at 10 iterations must still decrypt after the default changes.
      final salt = List<int>.generate(16, (i) => i);
      final ambient =
          await Pbkdf2Kdf.deriveKey(passphrase: 'hunter2', salt: salt);
      final explicit = await Pbkdf2Kdf.deriveKey(
        passphrase: 'hunter2',
        salt: salt,
        iterations: 11,
      );
      expect(
          await ambient.extractBytes(), isNot(await explicit.extractBytes()));

      final sameAsAmbient = await Pbkdf2Kdf.deriveKey(
        passphrase: 'hunter2',
        salt: salt,
        iterations: 10,
      );
      expect(await ambient.extractBytes(), await sameAsAmbient.extractBytes());
    });

    test('derives 256 bits by default', () async {
      final key = await Pbkdf2Kdf.deriveKey(
        passphrase: 'hunter2',
        salt: List<int>.generate(16, (i) => i),
      );
      expect((await key.extractBytes()).length, 32);
    });
  });

  group('PasswordHasher.hash', () {
    test('produces a different salt and a different hash every call', () async {
      final a = await PasswordHasher.hash('hunter2');
      final b = await PasswordHasher.hash('hunter2');
      expect(a.saltB64, isNot(b.saltB64));
      expect(a.hashB64, isNot(b.hashB64));
    });

    test('uses 16 bytes of salt', () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(base64Decode(h.saltB64).length, 16);
    });

    test('records the iteration count actually used', () async {
      // A later change to defaultIterations must not invalidate hashes made
      // before it, so the count travels with the hash.
      final h = await PasswordHasher.hash('hunter2');
      expect(h.iterations, 10);
    });
  });

  group('PasswordHasher.verify', () {
    test('returns true for the password that produced the hash', () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: h.hashB64,
          saltB64: h.saltB64,
          iterations: h.iterations,
        ),
        isTrue,
      );
    });

    test('returns false for a wrong password, and does not throw', () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter3',
          hashB64: h.hashB64,
          saltB64: h.saltB64,
          iterations: h.iterations,
        ),
        isFalse,
      );
    });

    test('returns false for an empty password against a non-empty hash',
        () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: '',
          hashB64: h.hashB64,
          saltB64: h.saltB64,
          iterations: h.iterations,
        ),
        isFalse,
      );
    });

    test('returns false when the salt does not match', () async {
      final h = await PasswordHasher.hash('hunter2');
      final other = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: h.hashB64,
          saltB64: other.saltB64,
          iterations: h.iterations,
        ),
        isFalse,
      );
    });

    test('returns false when the iteration count does not match', () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: h.hashB64,
          saltB64: h.saltB64,
          iterations: 11,
        ),
        isFalse,
      );
    });

    // A row mangled by hand in psql must fail a login, not crash the app.
    test('returns false for a non-base64 hash rather than throwing', () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: 'not base64 !!!',
          saltB64: h.saltB64,
          iterations: h.iterations,
        ),
        isFalse,
      );
    });

    test('returns false for a non-base64 salt rather than throwing', () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: h.hashB64,
          saltB64: 'not base64 !!!',
          iterations: h.iterations,
        ),
        isFalse,
      );
    });

    test('returns false for a truncated hash rather than throwing', () async {
      final h = await PasswordHasher.hash('hunter2');
      final short = base64Encode(base64Decode(h.hashB64).sublist(0, 8));
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: short,
          saltB64: h.saltB64,
          iterations: h.iterations,
        ),
        isFalse,
      );
    });

    test('returns false for empty hash and salt strings', () async {
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: '',
          saltB64: '',
          iterations: 10,
        ),
        isFalse,
      );
    });

    test('returns false for a nonsensical iteration count rather than throwing',
        () async {
      final h = await PasswordHasher.hash('hunter2');
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: h.hashB64,
          saltB64: h.saltB64,
          iterations: 0,
        ),
        isFalse,
      );
    });
  });

  group('PasswordHasher.constantTimeEquals', () {
    test('is true for identical byte lists', () {
      expect(
        PasswordHasher.constantTimeEquals([1, 2, 3, 4], [1, 2, 3, 4]),
        isTrue,
      );
    });

    test('is false for equal-length but different inputs', () {
      expect(
        PasswordHasher.constantTimeEquals([1, 2, 3, 4], [1, 2, 3, 5]),
        isFalse,
      );
      // Differing in the first byte must give the same answer as differing in
      // the last; the comparison does not return early.
      expect(
        PasswordHasher.constantTimeEquals([9, 2, 3, 4], [1, 2, 3, 4]),
        isFalse,
      );
    });

    test('is false for different-length inputs', () {
      expect(
          PasswordHasher.constantTimeEquals([1, 2, 3], [1, 2, 3, 4]), isFalse);
      expect(
          PasswordHasher.constantTimeEquals([1, 2, 3, 4], [1, 2, 3]), isFalse);
    });

    test('is true for two empty lists', () {
      expect(PasswordHasher.constantTimeEquals(const [], const []), isTrue);
    });
  });

  // The AppUser table (spec §2, quoted as final) has passwordHash and salt but
  // no iterations column, so the count rides in the passwordHash field. These
  // helpers are the encode/decode side of that decision; plan 01-06's
  // AccessRepository stores what encode() returns.
  group('PasswordHash stored encoding', () {
    test('encodes as pbkdf2-sha256\$<iterations>\$<hash_b64>', () {
      const h = PasswordHash(
        hashB64: 'aGFzaA==',
        saltB64: 'c2FsdA==',
        iterations: 200000,
      );
      expect(h.encode(), 'pbkdf2-sha256\$200000\$aGFzaA==');
    });

    test('round-trips through encode/decode', () async {
      final h = await PasswordHasher.hash('hunter2');
      final decoded = PasswordHash.decode(h.encode(), saltB64: h.saltB64);
      expect(decoded.hashB64, h.hashB64);
      expect(decoded.saltB64, h.saltB64);
      expect(decoded.iterations, h.iterations);
      expect(decoded, h);
    });

    test('a decoded hash still verifies', () async {
      final h = await PasswordHasher.hash('hunter2');
      final decoded = PasswordHash.decode(h.encode(), saltB64: h.saltB64);
      expect(
        await PasswordHasher.verify(
          password: 'hunter2',
          hashB64: decoded.hashB64,
          saltB64: decoded.saltB64,
          iterations: decoded.iterations,
        ),
        isTrue,
      );
    });

    test('a legacy bare-base64 value decodes at the default iteration count',
        () async {
      // Anything written before this encoding existed has no prefix. It was
      // made at whatever the ambient default was, which is what Pbkdf2Kdf
      // .iterations reports.
      final h = await PasswordHasher.hash('hunter2');
      final decoded = PasswordHash.decode(h.hashB64, saltB64: h.saltB64);
      expect(decoded.iterations, Pbkdf2Kdf.iterations);
      expect(decoded.hashB64, h.hashB64);
    });

    test('decode throws FormatException on a malformed prefixed value', () {
      expect(
        () => PasswordHash.decode('pbkdf2-sha256\$notanint\$aGFzaA==',
            saltB64: 'c2FsdA=='),
        throwsFormatException,
      );
      expect(
        () => PasswordHash.decode('pbkdf2-sha256\$10', saltB64: 'c2FsdA=='),
        throwsFormatException,
      );
    });

    test('decode throws FormatException on an unknown algorithm', () {
      expect(
        () =>
            PasswordHash.decode('argon2id\$10\$aGFzaA==', saltB64: 'c2FsdA=='),
        throwsFormatException,
      );
    });

    test('tryDecode returns null instead of throwing', () {
      expect(
        PasswordHash.tryDecode('pbkdf2-sha256\$notanint\$aGFzaA==',
            saltB64: 'c2FsdA=='),
        isNull,
      );
      expect(
        PasswordHash.tryDecode('argon2id\$10\$aGFzaA==', saltB64: 'c2FsdA=='),
        isNull,
      );
      expect(
        PasswordHash.tryDecode('aGFzaA==', saltB64: 'c2FsdA==')?.hashB64,
        'aGFzaA==',
      );
    });
  });

  group('password_hasher.dart purity', () {
    test('does not reach for Flutter or the cryptography_flutter plugin', () {
      // package_purity_test.dart covers lib/ as a whole; this states the rule
      // at the one file where the temptation is real, because the accelerated
      // backend is a plugin and this is the code that would want it.
      final source = _source('lib/src/password_hasher.dart');
      expect(source, isNot(contains('cryptography_flutter')));
      expect(source, isNot(contains('package:flutter')));
      expect(source, isNot(contains('dart:ui')));
    });
  });
}
