import 'dart:io';

/// Typedef for process starting — injectable for testing.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

/// Typedef for running commands and getting output — injectable for testing.
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Typedef for loading Flutter assets — injectable for testing.
typedef AssetLoader = Future<List<int>> Function(String key);

/// Typedef for resolving the manager path — injectable for testing.
typedef PathResolver = Future<String> Function();

/// Handles extraction and launching of the bundled centroidx-manager binary.
class ManagerLauncher {
  final ProcessStarter? _processStarter;
  final CommandRunner? _commandRunner;
  final AssetLoader? _assetLoader;
  final PathResolver? _pathResolver;
  final bool platformIsWindows;
  final bool platformIsMacOS;

  ManagerLauncher({
    ProcessStarter? processStarter,
    CommandRunner? commandRunner,
    AssetLoader? assetLoader,
    PathResolver? pathResolver,
    bool? platformIsWindows,
    bool? platformIsMacOS,
  })  : _processStarter = processStarter,
        _commandRunner = commandRunner,
        _assetLoader = assetLoader,
        _pathResolver = pathResolver,
        platformIsWindows = platformIsWindows ?? Platform.isWindows,
        platformIsMacOS = platformIsMacOS ?? Platform.isMacOS;

  /// Resolves the path where the manager binary should reside.
  Future<String> resolveManagerPath() {
    throw UnimplementedError('ManagerLauncher.resolveManagerPath not yet implemented');
  }

  /// Ensures the manager binary is extracted from Flutter assets to [resolveManagerPath].
  Future<void> ensureExtracted() {
    throw UnimplementedError('ManagerLauncher.ensureExtracted not yet implemented');
  }

  /// Strips macOS quarantine attribute from [path]. No-op on non-macOS.
  Future<void> stripQuarantine(String path) {
    throw UnimplementedError('ManagerLauncher.stripQuarantine not yet implemented');
  }

  /// Extracts manager binary and launches it as a detached process.
  ///
  /// Returns the PID of the launched manager process.
  Future<int> launchForUpdate({
    required String version,
    int? flutterPid,
  }) {
    throw UnimplementedError('ManagerLauncher.launchForUpdate not yet implemented');
  }
}
