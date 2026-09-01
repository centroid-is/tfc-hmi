// Ten minutes, not three. This test shells out to `dart build cli`, which
// AOT-compiles the package and runs its native build hooks from cold -- the
// wall clock here measures the toolchain and the runner, not the code under
// test. Measured on CI run 33506143133: 39 s on ubuntu-latest, 65 s on a
// healthy macos-latest, and over 180 s on a macos-latest that was merely
// slow, which is what tripped the old budget. The timeout is a hang guard.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('dart build cli', () {
    test('compiles tfc_mcp_server binary without FFI link errors', () async {
      // A unique directory under the platform's own temp root. The hardcoded
      // `/tmp` this used to write to is not a temp directory on Windows, and
      // sharing one path between runs means two of them race.
      final outputDirectory =
          Directory.systemTemp.createTempSync('tfc_mcp_build_');
      addTearDown(() {
        if (outputDirectory.existsSync()) {
          outputDirectory.deleteSync(recursive: true);
        }
      });
      final outputDir = outputDirectory.path;

      final workingDir = Directory.current.path.contains('tfc_mcp_server')
          ? Directory.current.path
          : '${Directory.current.path}/packages/tfc_mcp_server';

      // No entry point argument. `dart build cli` takes the package's
      // `bin/<package name>.dart` by convention, and as of Dart 3.13 passing
      // it explicitly is a usage error -- "Unexpected arguments:
      // bin/tfc_mcp_server.dart", exit 64. Dart 3.12 (what Flutter 3.44.9
      // bundles) accepts its absence too, so this works either side of that.
      //
      // The elapsed time is printed on success too, so the log carries the
      // margin against the file timeout rather than only reporting it once
      // that budget has already been blown.
      final clock = Stopwatch()..start();
      final result = await Process.run(
        'dart',
        ['build', 'cli', '-o', outputDir],
        workingDirectory: workingDir,
      );
      stdout.writeln('dart build cli took ${clock.elapsed.inSeconds}s');

      // Print stderr for debugging if compilation fails
      if (result.exitCode != 0) {
        stderr.writeln('STDOUT: ${result.stdout}');
        stderr.writeln('STDERR: ${result.stderr}');
      }

      expect(result.exitCode, equals(0),
          reason: 'dart build cli should succeed without FFI link errors');

      // dart build cli outputs to <dir>/bundle/bin/<name>. Forward slashes are
      // fine on Windows; the .exe the old path was missing is not optional.
      final exe = Platform.isWindows ? 'tfc_mcp_server.exe' : 'tfc_mcp_server';
      final binaryPath = '$outputDir/bundle/bin/$exe';
      expect(File(binaryPath).existsSync(), isTrue,
          reason: 'Compiled binary should exist at $binaryPath');

      // Verify the binary is executable by running --version
      final versionResult = await Process.run(binaryPath, ['--version']);
      expect(versionResult.exitCode, equals(0));
      expect(versionResult.stderr.toString(), contains('tfc_mcp_server'));
    });
  });
}
