@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('dart build cli', () {
    test('compiles tfc_mcp_server binary without FFI link errors', () async {
      final outputDir = '/tmp/tfc_mcp_test_build';

      // Clean up from any previous test run
      final outputDirectory = Directory(outputDir);
      if (outputDirectory.existsSync()) {
        outputDirectory.deleteSync(recursive: true);
      }

      final workingDir = Directory.current.path.contains('tfc_mcp_server')
          ? Directory.current.path
          : '${Directory.current.path}/packages/tfc_mcp_server';

      final result = await Process.run(
        'dart',
        [
          'build',
          'cli',
          'bin/tfc_mcp_server.dart',
          '-o',
          outputDir,
        ],
        workingDirectory: workingDir,
      );

      // Print stderr for debugging if compilation fails
      if (result.exitCode != 0) {
        stderr.writeln('STDOUT: ${result.stdout}');
        stderr.writeln('STDERR: ${result.stderr}');
      }

      expect(result.exitCode, equals(0),
          reason: 'dart build cli should succeed without FFI link errors');

      // dart build cli outputs to <dir>/bundle/bin/<name>
      final binaryPath = '$outputDir/bundle/bin/tfc_mcp_server';
      expect(File(binaryPath).existsSync(), isTrue,
          reason: 'Compiled binary should exist at $binaryPath');

      // Verify the binary is executable by running --version
      final versionResult = await Process.run(binaryPath, ['--version']);
      expect(versionResult.exitCode, equals(0));
      expect(versionResult.stderr.toString(), contains('tfc_mcp_server'));
    });
  });
}
