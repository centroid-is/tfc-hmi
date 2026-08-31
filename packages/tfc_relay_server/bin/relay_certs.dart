/// `relay_certs` — the command an integrator runs to provision a plant.
///
/// SEC-01 asks for tooling that generates a CA root and a server leaf. This is
/// it, and it needs no `openssl` on the machine: the certificate bytes come
/// from `lib/src/tls/mint.dart`, which is also what every test in this phase
/// mints through. That shared function is the point (06-RESEARCH §B.4). A
/// second ASN.1 path living in `bin/` would be a second place the iPAddress
/// SAN fix has to be remembered, and it would be the copy nobody re-tests —
/// so `relay_certs_test.dart` reads this file's own text and fails if the
/// string `ASN1` appears in it.
///
/// Two runs, in order:
///
/// ```
/// dart run tfc_relay_server:relay_certs --ca --out /etc/relay/pki
/// dart run tfc_relay_server:relay_certs --leaf \
///     --ca-cert /etc/relay/pki/ca.pem --ca-key /etc/relay/pki/ca-key.pem \
///     --san relay.svn.local --san 10.104.29.71 --days 365 \
///     --out /etc/relay/pki
/// ```
///
/// The root is provisioned once (ten years) to every panel; the leaf is
/// re-issued yearly, which the days-to-expiry health key turns into a Tuesday
/// ticket rather than an outage.
///
/// [main] is a thin wrapper over [run] so the tests can call it in-process:
/// spawning `dart run` from the worktree root fires the native-asset build
/// hooks and rebuilds mbedTLS before the script executes (trap 15).
///
/// Without this file SEC-01 is half-met — the library can mint, and nobody in
/// the plant has a way to ask it to.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';

/// The exit code the process should carry.
///
/// `out` and `err` are [StringSink] rather than `IOSink` on purpose: `stdout`
/// and `stderr` are both, and so is a `StringBuffer`, which is what lets a
/// case assert on the message an integrator sees without a pipe or a
/// subprocess.
Future<int> run(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = _parser();

  ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    // A misspelled option is a refusal, not a crash: an integrator reading
    // `FormatException` learns nothing they can act on.
    stderrSink.writeln('relay_certs: ${e.message}');
    stderrSink.writeln(parser.usage);
    return 1;
  }

  if (options.flag('help')) {
    stdoutSink.writeln('Generate a private CA root and a gateway leaf for the '
        'relay pipe.\n');
    stdoutSink.writeln('Usage: relay_certs --ca   --out <dir>');
    stdoutSink.writeln('       relay_certs --leaf --ca-cert <path> '
        '--ca-key <path> [--san <name>]... --out <dir>\n');
    stdoutSink.writeln(parser.usage);
    return 0;
  }

  try {
    if (options.flag('ca')) return _mintRoot(options, stdoutSink);
    if (options.flag('leaf')) return _mintLeaf(options, stdoutSink);
    stderrSink.writeln('relay_certs: give exactly one of --ca or --leaf.');
    stderrSink.writeln(parser.usage);
    return 1;
  } on _Refused catch (refusal) {
    // Every refusal below reaches the operator as one sentence naming what is
    // missing. A stack trace on a plant machine at 6 a.m. is not a message.
    stderrSink.writeln('relay_certs: ${refusal.message}');
    return 1;
  } on FileSystemException catch (e) {
    stderrSink.writeln('relay_certs: ${e.path}: ${e.osError?.message ?? e.message}');
    return 1;
  }
}

Future<void> main(List<String> args) async => exit(await run(args));

ArgParser _parser() => ArgParser()
  ..addFlag('ca', negatable: false, help: 'Generate a private CA root.')
  ..addFlag('leaf',
      negatable: false, help: 'Generate a gateway leaf signed by a CA.')
  ..addOption('out',
      help: 'Directory the PEM files are written to.', valueHelp: 'dir')
  ..addOption('cn',
      help: 'Common name.', valueHelp: 'name')
  ..addOption('org', help: 'Organization.', valueHelp: 'name', defaultsTo: 'Centroid')
  ..addOption('ca-cert',
      help: 'Path to the CA certificate (--leaf).', valueHelp: 'path')
  ..addOption('ca-key',
      help: 'Path to the CA private key (--leaf).', valueHelp: 'path')
  ..addMultiOption('san',
      help: 'Subject-alternative name. A value that parses as an IP address '
          'is written as an iPAddress; anything else as a DNS name. Repeat '
          'for each. The panels dial addresses, so include them.',
      valueHelp: 'name-or-ip')
  ..addOption('days',
      help: 'Validity in days.', valueHelp: 'n', defaultsTo: '365')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

int _mintRoot(ArgResults options, StringSink out) {
  final dir = _outDirectory(options);
  final days = _days(options, fallback: 3650);
  final keys = generateKeyPair();
  final dn = {
    'CN': options.option('cn') ?? 'Relay Private CA',
    'O': options.option('org')!,
  };
  final now = DateTime.now().toUtc();

  final pem = mintCertificate(
    signingKey: keys.privateKey,
    issuer: dn,
    subject: dn,
    subjectPublicKey: keys.publicKey,
    notBefore: now.subtract(const Duration(days: 1)),
    notAfter: now.add(Duration(days: days)),
    ca: true,
  );

  _write(dir, 'ca.pem', pem, out);
  _write(dir, 'ca-key.pem', privateKeyToPem(keys.privateKey), out, private: true);
  return 0;
}

int _mintLeaf(ArgResults options, StringSink out) {
  final dir = _outDirectory(options);
  final caCert = _readRequired(options, 'ca-cert');
  final caKey = _readRequired(options, 'ca-key');
  final days = _days(options, fallback: 365);

  final sans = options.multiOption('san');
  if (sans.isEmpty) {
    throw const _Refused('--leaf needs at least one --san. A leaf with no '
        'subject-alternative name matches no host, and every panel refuses '
        'it at the handshake.');
  }

  final keys = generateKeyPair();
  final now = DateTime.now().toUtc();

  final pem = mintCertificate(
    signingKey: privateKeyFromPem(caKey),
    // Byte-identical to the CA's own subject name, because a verifier matches
    // the two on DER bytes and not on how they render.
    issuer: subjectNameFromPem(caCert),
    subject: {
      'CN': options.option('cn') ?? sans.first,
      'O': options.option('org')!,
    },
    subjectPublicKey: keys.publicKey,
    sans: sans,
    notBefore: now.subtract(const Duration(days: 1)),
    notAfter: now.add(Duration(days: days)),
  );

  _write(dir, 'leaf.pem', pem, out);
  _write(dir, 'leaf-key.pem', privateKeyToPem(keys.privateKey), out,
      private: true);
  return 0;
}

Directory _outDirectory(ArgResults options) {
  final path = options.option('out');
  if (path == null) {
    throw const _Refused('--out is required: name the directory the PEM files '
        'should be written to.');
  }
  final dir = Directory(path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Reads the file named by [name], refusing before anything is written.
///
/// The check is up front so a `--leaf` run that cannot succeed leaves no
/// half-written key material in the output directory.
String _readRequired(ArgResults options, String name) {
  final path = options.option(name);
  if (path == null) {
    throw _Refused('--$name is required with --leaf: the leaf has to be '
        'signed by something, and nothing was named.');
  }
  final file = File(path);
  if (!file.existsSync()) {
    throw _Refused('--$name: no such file: $path');
  }
  return file.readAsStringSync();
}

int _days(ArgResults options, {required int fallback}) {
  final raw = options.option('days');
  if (raw == null) return fallback;
  final days = int.tryParse(raw);
  if (days == null || days <= 0) {
    throw _Refused('--days must be a positive whole number, not "$raw".');
  }
  return days;
}

void _write(Directory dir, String name, String contents, StringSink out,
    {bool private = false}) {
  final path = '${dir.path}${Platform.pathSeparator}$name';
  File(path).writeAsStringSync(contents);
  if (private && !Platform.isWindows) {
    // 0600. The key is readable by the account that runs the gateway and by
    // nobody else on the box; POSIX permissions are the only thing standing
    // between a shared plant machine and the gateway's identity.
    Process.runSync('chmod', ['600', path]);
  }
  out.writeln('wrote $path');
}

/// An operator-facing refusal: one sentence, no stack trace, exit 1.
final class _Refused implements Exception {
  const _Refused(this.message);
  final String message;
  @override
  String toString() => message;
}
