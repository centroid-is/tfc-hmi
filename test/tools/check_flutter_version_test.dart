/// Tests for `scripts/check-flutter-version.sh`.
///
/// The script is the repo's guard against working on a Flutter that is not the
/// one CI installs, so it has to be right about the one thing it does: compare
/// two strings and pick the correct exit code. It is also the kind of file
/// nobody opens for a year, which is exactly when a `sed` expression quietly
/// stops matching a reworded `flutter --version`.
///
/// Each case runs the real script against a fake `flutter` on PATH, so the
/// parsing is exercised for real rather than mocked.
@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _script = 'scripts/check-flutter-version.sh';

/// Exit codes the script documents.
const _match = 0;
const _mismatch = 1;
const _cannotRun = 2;

void main() {
  late Directory tmp;
  late String fakeBinDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('check_flutter_version_');
    fakeBinDir = p.join(tmp.path, 'bin');
    Directory(fakeBinDir).createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Puts a `flutter` on PATH that reports [version].
  ///
  /// [machineOutput] overrides the `--version --machine` body so tests can feed
  /// the script malformed or noise-prefixed JSON; [humanOutput] does the same
  /// for the plain `--version` form the script falls back to.
  void installFakeFlutter({
    String version = '3.44.9',
    String? machineOutput,
    String? humanOutput,
  }) {
    final machine = machineOutput ??
        const JsonEncoder.withIndent('  ').convert({
          'frameworkVersion': version,
          'channel': 'stable',
          'dartSdkVersion': '3.12.0',
        });
    final human = humanOutput ?? 'Flutter $version • channel stable • https://x';
    final file = File(p.join(fakeBinDir, 'flutter'));
    file.writeAsStringSync('''
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = "--machine" ]; then
    cat <<'MACHINE'
$machine
MACHINE
    exit 0
  fi
done
cat <<'HUMAN'
$human
HUMAN
''');
    Process.runSync('chmod', ['+x', file.path]);
  }

  /// Writes a `.flutter-version` containing [contents] and returns its path.
  String pinFile(String contents) {
    final file = File(p.join(tmp.path, '.flutter-version'));
    file.writeAsStringSync(contents);
    return file.path;
  }

  ProcessResult run(
    List<String> args, {
    bool withFakeFlutter = true,
    Map<String, String> env = const {},
  }) {
    // The fake bin dir goes first either way; when the fake flutter was not
    // installed it is empty, so the trailing entries decide. Those are the
    // system directories only — enough for the script's shebang and `git`,
    // and short of wherever a real flutter lives.
    final path = withFakeFlutter
        ? '$fakeBinDir:${Platform.environment['PATH']}'
        : '$fakeBinDir:/usr/bin:/bin';
    return Process.runSync(
      _script,
      args,
      environment: {'PATH': path, ...env},
      includeParentEnvironment: false,
    );
  }

  test('script is present and executable', () {
    final stat = File(_script).statSync();
    expect(stat.type, FileSystemEntityType.file,
        reason: '$_script must exist — see README "Flutter version"');
    expect(stat.mode & 0x40, isNonZero, reason: '$_script must be chmod +x');
  });

  group('matching versions', () {
    test('exits 0 and says so', () {
      installFakeFlutter(version: '3.44.9');
      final r = run(['--version-file', pinFile('3.44.9\n')]);
      expect(r.exitCode, _match);
      expect(r.stdout, contains('3.44.9 matches'));
    });

    test('--quiet prints nothing', () {
      installFakeFlutter(version: '3.44.9');
      final r = run(['--version-file', pinFile('3.44.9\n'), '--quiet']);
      expect(r.exitCode, _match);
      expect(r.stdout, isEmpty);
    });

    test('surrounding whitespace in .flutter-version is ignored', () {
      installFakeFlutter(version: '3.44.9');
      final r = run(['--version-file', pinFile('  3.44.9  \n\n')]);
      expect(r.exitCode, _match);
    });
  });

  group('mismatched versions', () {
    test('exits 1 and names both versions', () {
      installFakeFlutter(version: '3.41.9');
      final r = run(['--version-file', pinFile('3.44.9\n')]);
      expect(r.exitCode, _mismatch);
      expect(r.stderr, contains('3.41.9'));
      expect(r.stderr, contains('3.44.9'));
      // The two failure modes are the whole reason to care; the message is
      // useless without them.
      expect(r.stderr, contains('Goldens'));
      expect(r.stderr, contains('assertions'));
    });

    test('a patch-level difference still fails', () {
      installFakeFlutter(version: '3.44.8');
      final r = run(['--version-file', pinFile('3.44.9\n')]);
      expect(r.exitCode, _mismatch);
    });

    test('--warn-only reports it but exits 0', () {
      installFakeFlutter(version: '3.41.9');
      final r = run(['--version-file', pinFile('3.44.9\n'), '--warn-only']);
      expect(r.exitCode, _match);
      expect(r.stderr, contains('WARNING'));
    });

    test('TFC_ALLOW_FLUTTER_SKEW=1 downgrades it to a warning', () {
      installFakeFlutter(version: '3.41.9');
      final r = run(
        ['--version-file', pinFile('3.44.9\n')],
        env: {'TFC_ALLOW_FLUTTER_SKEW': '1'},
      );
      expect(r.exitCode, _match);
      expect(r.stderr, contains('WARNING'));
    });

    test('TFC_ALLOW_FLUTTER_SKEW=0 does not', () {
      installFakeFlutter(version: '3.41.9');
      final r = run(
        ['--version-file', pinFile('3.44.9\n')],
        env: {'TFC_ALLOW_FLUTTER_SKEW': '0'},
      );
      expect(r.exitCode, _mismatch);
      expect(r.stderr, contains('ERROR'));
    });
  });

  group('reading the installed version', () {
    test('tolerates noise before the --machine JSON', () {
      // Flutter has prefixed first-run banners and analytics notices to this
      // output before; grepping the field out survives that.
      installFakeFlutter(
        machineOutput: 'Resolving dependencies...\n'
            '{"frameworkVersion": "3.44.9", "channel": "stable"}',
      );
      final r = run(['--version-file', pinFile('3.44.9\n')]);
      expect(r.exitCode, _match);
    });

    test('falls back to the human output when --machine yields nothing', () {
      installFakeFlutter(
        machineOutput: '',
        humanOutput: 'Flutter 3.44.9 • channel stable • https://x',
      );
      final r = run(['--version-file', pinFile('3.44.9\n')]);
      expect(r.exitCode, _match);
    });

    test('exits 2 when no version can be read at all', () {
      installFakeFlutter(machineOutput: '', humanOutput: 'who knows');
      final r = run(['--version-file', pinFile('3.44.9\n')]);
      expect(r.exitCode, _cannotRun);
    });
  });

  group('cannot run', () {
    test('missing .flutter-version', () {
      installFakeFlutter();
      final r = run(['--version-file', p.join(tmp.path, 'absent')]);
      expect(r.exitCode, _cannotRun);
      expect(r.stderr, contains('missing'));
    });

    test('empty .flutter-version', () {
      installFakeFlutter();
      final r = run(['--version-file', pinFile('\n  \n')]);
      expect(r.exitCode, _cannotRun);
      expect(r.stderr, contains('empty'));
    });

    test('no flutter on PATH', () {
      final r = run(
        ['--version-file', pinFile('3.44.9\n')],
        withFakeFlutter: false,
      );
      expect(r.exitCode, _cannotRun);
      expect(r.stderr, contains('no `flutter` on PATH'));
    });

    test('unknown option', () {
      installFakeFlutter();
      final r = run(['--bogus']);
      expect(r.exitCode, _cannotRun);
      expect(r.stderr, contains('unknown option'));
    });

    test('--version-file with no argument', () {
      installFakeFlutter();
      final r = run(['--version-file']);
      expect(r.exitCode, _cannotRun);
      expect(r.stderr, contains('needs a path'));
    });
  });

  test('--help explains itself', () {
    final r = run(['--help']);
    expect(r.exitCode, _match);
    expect(r.stdout, contains('--warn-only'));
    expect(r.stdout, contains('TFC_ALLOW_FLUTTER_SKEW'));
  });

  test('finds the repo .flutter-version with no arguments', () {
    // No --version-file: the script has to locate the repo root itself. The
    // verdict depends on whoever is running this, so assert only that it got
    // far enough to reach one — exit 2 would mean discovery broke.
    installFakeFlutter();
    final r = run([]);
    expect(r.exitCode, anyOf(_match, _mismatch),
        reason: 'repo-root discovery failed: ${r.stderr}');
  });
}
