/// `relay_certs`, judged by what dart:io does with what it wrote.
///
/// SEC-01's first half is "tooling generates a CA and a server leaf". This is
/// that tool, and these are the cases that stop it from being a tool that
/// produces plausible-looking files. Two properties carry the weight:
///
///  * **The CLI mints through the same function the tests do** (06-RESEARCH
///    §B.4). A second minting path inside `bin/` would be a second place the
///    `0x87` fix has to be remembered, and the one that only integrators run
///    is the one nobody re-tests. A case reads the file's own text for that.
///  * **The verifier is a real pinned handshake, not a file that parses.**
///    `useCertificateChain` accepts a self-signed leaf perfectly happily, so a
///    case that only loaded the PEMs would pass with `--ca-key` ignored. A
///    `SecureSocket` trusting only the CA the CLI produced is the check that
///    bites. Deliberately **not** `openssl`: `relay-packages-test` runs a
///    `windows-latest` leg (A7) and a test that needs openssl on PATH is a
///    lane that goes red for a reason unrelated to this code.
///
/// [run] is called in-process. `dart run` from the worktree root fires the
/// native-asset build hooks and rebuilds mbedTLS before the script executes
/// (trap 15), which turns a 15 ms case into minutes.
///
/// Without this file, the command an integrator runs on a plant machine at
/// 6 a.m. is the least-tested code in the phase.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:test/test.dart';

import '../bin/relay_certs.dart' as cli;

/// The tbsCertificate of the PEM at [path].
ASN1Sequence _tbsOf(String path) {
  final pem = File(path).readAsStringSync();
  final body = pem
      .split('\n')
      .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
      .join();
  final cert = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
  return cert.elements!.first as ASN1Sequence;
}

/// The exact DER of [object], sliced to its own length — a parsed object's
/// `encodedBytes` can be a view that runs on past it.
Uint8List _der(ASN1Object object) => Uint8List.fromList(object.encodedBytes!
    .sublist(0, object.valueStartPosition + object.valueByteLength!));

/// The `notAfter` of the certificate at [path].
///
/// `Validity ::= SEQUENCE { notBefore Time, notAfter Time }` is element 4 of
/// the tbsCertificate, after the explicit `[0]` version — a v1 certificate
/// would put it one slot earlier, which is one more reason [mintCertificate]
/// always writes v3.
DateTime _notAfter(String path) {
  final validity = _tbsOf(path).elements![4] as ASN1Sequence;
  final end = validity.elements![1];
  return switch (end) {
    ASN1UtcTime(:final time?) => time.toUtc(),
    ASN1GeneralizedTime(:final dateTimeValue?) => dateTimeValue.toUtc(),
    _ => throw StateError('notAfter is a ${end.runtimeType} with no date'),
  };
}

/// The GeneralName tag bytes in the subjectAltName extension.
List<int> _sanTags(String path) {
  final tagged = _tbsOf(path).elements!.firstWhere((e) => e.tag == 0xA3);
  final exts = ASN1Parser(tagged.valueBytes).nextObject() as ASN1Sequence;
  for (final ext in exts.elements!.cast<ASN1Sequence>()) {
    final oid = ext.elements!.first as ASN1ObjectIdentifier;
    if (oid.objectIdentifierAsString == '2.5.29.17') {
      final names =
          ASN1Parser((ext.elements!.last as ASN1OctetString).octets)
              .nextObject() as ASN1Sequence;
      return [for (final n in names.elements!) n.tag!];
    }
  }
  return const [];
}

void main() {
  late Directory caDir;
  late StringBuffer out;
  late StringBuffer err;

  // One CA for the file: the RSA keygen inside a `--ca` run is the expensive
  // part (~180 ms) and every leaf case wants the same root anyway.
  setUpAll(() async {
    caDir = Directory.systemTemp.createTempSync('relay-certs-ca-');
    final code = await cli.run(['--ca', '--out', caDir.path],
        out: StringBuffer(), err: StringBuffer());
    expect(code, 0, reason: 'the whole file is built on this root');
  });

  tearDownAll(() => caDir.deleteSync(recursive: true));

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  Directory freshOut() {
    final dir = Directory.systemTemp.createTempSync('relay-certs-out-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  // `days` is nullable so a case can leave `--days` off the command line
  // entirely, which is the only way to see what each mode defaults to.
  Future<int> mintLeafInto(Directory dir,
          {List<String> sans = const [], String? days = '365'}) =>
      cli.run([
        '--leaf',
        '--ca-cert',
        '${caDir.path}/ca.pem',
        '--ca-key',
        '${caDir.path}/ca-key.pem',
        for (final s in sans) ...['--san', s],
        if (days != null) ...['--days', days],
        '--out',
        dir.path,
      ], out: out, err: err);

  test('--ca writes a root and its key where it was told to', () {
    expect(File('${caDir.path}/ca.pem').existsSync(), isTrue,
        reason: 'the root is what gets provisioned to every panel; a run that '
            'reports success and writes nothing is discovered on site');
    expect(File('${caDir.path}/ca-key.pem').existsSync(), isTrue);
    expect(File('${caDir.path}/ca.pem').readAsStringSync(),
        startsWith('-----BEGIN CERTIFICATE-----'));
  });

  group('how long each mode signs for', () {
    // The setUpAll root was minted with no `--days`, which is exactly the run
    // an integrator makes.
    test('--ca defaults to a root that outlives the provisioning visit', () {
      final years =
          _notAfter('${caDir.path}/ca.pem').difference(DateTime.now().toUtc());

      expect(years.inDays, greaterThan(365 * 9),
          reason: 'the root is provisioned once to every panel in the plant '
              'and is not re-issued yearly (06-CONTEXT decision 3, design '
              '§7.2, this file\'s own header). A 365-day root stops every '
              'panel at once a year after the visit, and the days-to-expiry '
              'health key cannot warn about it because it measures the leaf, '
              'which is being re-issued on schedule and reads healthy the '
              'whole way down');
    });

    test('--leaf defaults to one year, not to the root\'s ten', () async {
      final dir = freshOut();
      expect(await mintLeafInto(dir, sans: ['localhost'], days: null), 0,
          reason: '$err');

      final left =
          _notAfter('${dir.path}/leaf.pem').difference(DateTime.now().toUtc());

      expect(left.inDays, lessThan(400),
          reason: 'the two modes want different defaults, which is why '
              '`_days` takes a per-mode fallback. A parser-level default '
              'shadows both of them: `ArgResults.option` is '
              '`valueOrDefault(_parsed[name])`, so the fallback is never '
              'reached and whichever number the parser carries silently wins '
              'for both subcommands');
      expect(left.inDays, greaterThan(300),
          reason: 'a leaf shorter than the year 06-CONTEXT decided on turns '
              'the yearly Tuesday ticket into a quarterly one nobody has '
              'scheduled');
    });

    test('an explicit --days still wins over both defaults', () async {
      final dir = freshOut();
      expect(await mintLeafInto(dir, sans: ['localhost'], days: '30'), 0,
          reason: '$err');

      expect(
          _notAfter('${dir.path}/leaf.pem')
              .difference(DateTime.now().toUtc())
              .inDays,
          lessThan(31),
          reason: 'the near-expiry fixtures in `health_cert_test.dart` mint '
              'short-lived leaves through this option; a default that could '
              'not be overridden would take that away');
    });
  });

  group('the private key is never readable by anybody else, even briefly', () {
    test('both key files are 0600 and the created directory is 0700', () async {
      final parent = Directory.systemTemp.createTempSync('relay-certs-mode-');
      addTearDown(() => parent.deleteSync(recursive: true));
      // A path the CLI has to create itself: `createSync` applies the process
      // umask, so a directory the test made would prove nothing.
      final dir = Directory('${parent.path}/pki');

      expect(await cli.run(['--ca', '--out', dir.path], out: out, err: err), 0,
          reason: '$err');
      expect(
          await cli.run([
            '--leaf',
            '--ca-cert',
            '${dir.path}/ca.pem',
            '--ca-key',
            '${dir.path}/ca-key.pem',
            '--san',
            'localhost',
            '--out',
            dir.path,
          ], out: out, err: err),
          0,
          reason: '$err');

      for (final name in ['ca-key.pem', 'leaf-key.pem']) {
        expect(File('${dir.path}/$name').statSync().mode & 0x3F, 0,
            reason: 'a private key readable by group or other is the exact '
                'exposure `FileTokenValidator._refuseLoosePermissions` '
                'refuses to tolerate for the less valuable of the two '
                'secrets. `writeAsStringSync` creates a file at '
                '`0666 & ~umask` — 0644 on a normal account — so the '
                'restriction has to be applied to an empty file before the '
                'bytes go into it, not to a full one afterwards');
      }
      expect(dir.statSync().mode & 0x3F, 0,
          reason: 'the PKI directory the tool created holds the plant\'s CA '
              'key; a directory every account can list is a directory every '
              'account can watch for the moment a key appears in it');
    }, skip: Platform.isWindows ? 'POSIX modes' : null);

    test('a restriction that cannot be applied is a refusal, not a log line',
        () {
      final source = File('bin/relay_certs.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      // Sabotage arm, run by hand and recorded here: replacing the two checks
      // below with a bare `Process.runSync('chmod', ...)` leaves `ca-key.pem`
      // at 0644 permanently on any filesystem that does not carry POSIX modes
      // — a bind mount, a FAT stick, a machine with no `chmod` binary — while
      // the tool prints `wrote …` and exits 0. There is no failure the
      // integrator can see, and no behavioural case can produce one portably,
      // so the property is pinned structurally.
      expect(source, contains('chmod.exitCode == 0 &&'),
          reason: 'a discarded ProcessResult is a chmod that may never have '
              'happened, and success has to require its exit code rather '
              'than merely mention it');
      expect(source, contains('statSync(path).mode & 0x3F'),
          reason: 'exit 0 is not evidence: a filesystem that ignores modes '
              'reports success and leaves the key world-readable. The mode '
              'has to be read back');
      expect(source, contains('deleteSync'),
          reason: 'a key the machine cannot protect must not be left on '
              'disk — a refusal that leaves the file behind is a refusal an '
              'integrator works around by ignoring it');
    });
  });

  test('a leaf the CLI produced verifies against the CA the CLI produced',
      () async {
    final dir = freshOut();
    expect(await mintLeafInto(dir, sans: ['localhost', '127.0.0.1']), 0,
        reason: err.toString());

    final server = SecurityContext(withTrustedRoots: false)
      ..useCertificateChain('${dir.path}/leaf.pem')
      ..usePrivateKey('${dir.path}/leaf-key.pem');
    final client = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('${caDir.path}/ca.pem');

    final listener = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4, 0, server);
    addTearDown(() => listener.close());
    listener.listen((s) {
      s.listen(null, onError: (Object _) {});
      s.destroy();
    });

    // The verifier that matters. Loading the PEMs proves only that they parse;
    // a self-signed leaf loads just as well, which is exactly the mistake the
    // sabotage arm makes.
    final socket = await SecureSocket.connect(
        '127.0.0.1', listener.port,
        context: client, timeout: const Duration(seconds: 5));
    addTearDown(socket.destroy);
    expect(socket.peerCertificate, isNotNull,
        reason: 'a panel pinning only this CA must complete the handshake '
            'against a leaf this CA signed — that is the entire point of the '
            'two subcommands existing');
  });

  test("the leaf's issuer name is byte-identical to the CA's subject name",
      () async {
    final dir = freshOut();
    expect(await mintLeafInto(dir, sans: ['localhost']), 0, reason: '$err');

    final caSubject = _der(_tbsOf('${caDir.path}/ca.pem').elements![5]);
    final leafIssuer = _der(_tbsOf('${dir.path}/leaf.pem').elements![3]);

    expect(leafIssuer, caSubject,
        reason: 'a verifier matches issuer to subject on the DER bytes, not '
            'on the rendered text — a re-encoded name that reads the same and '
            'differs by one byte builds no chain, and the error a panel shows '
            'for that is the same one it shows for a wrong CA');
  });

  test('an IP among --san reaches the certificate as an iPAddress', () async {
    final dir = freshOut();
    expect(
        await mintLeafInto(dir, sans: ['relay.svn.local', '10.104.29.71']), 0,
        reason: '$err');

    expect(_sanTags('${dir.path}/leaf.pem'), [0x82, 0x87],
        reason: 'the --san values must reach mintCertificate unchanged; a CLI '
            'that normalised them to strings would ship the basic_utils '
            'defect through the front door');
  });

  test('--help prints the usage and exits 0', () async {
    expect(await cli.run(['--help'], out: out, err: err), 0);
    expect(out.toString(), contains('--san'),
        reason: 'an integrator on a plant machine has no other documentation '
            'in front of them');
    expect(err.toString(), isEmpty);
  });

  test('a --leaf run without --ca-key exits 1 and names the option', () async {
    final dir = freshOut();

    final code = await cli.run([
      '--leaf',
      '--ca-cert',
      '${caDir.path}/ca.pem',
      '--out',
      dir.path,
    ], out: out, err: err);

    expect(code, 1,
        reason: 'exit 0 on a run that produced no leaf is how a provisioning '
            'script carries on and the panel is discovered untrusted later');
    expect(err.toString(), contains('--ca-key'),
        reason: 'the message must name the option that is missing; a stack '
            'trace tells an integrator nothing they can act on');
    expect(err.toString(), isNot(contains('#0')),
        reason: 'a raw stack trace on stderr is not an error message');
    expect(File('${dir.path}/leaf.pem').existsSync(), isFalse,
        reason: 'a refused run leaves no half-written key material behind');
  });

  test('the CLI and the tests mint through the same function', () {
    final source = File('bin/relay_certs.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    expect(source, contains('mintCertificate'),
        reason: 'the CLI is a shell over the function the tests call, which '
            'is what makes a passing fixture evidence about the tool');
    expect(source, isNot(contains('ASN1')),
        reason: 'a second ASN.1 construction path is a second place the 0x87 '
            'fix has to be remembered, and it is the copy nobody re-tests');
  });
}
