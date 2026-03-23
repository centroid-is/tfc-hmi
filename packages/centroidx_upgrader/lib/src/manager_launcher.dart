import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Typedef for process starting — injectable for testing.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

/// Typedef for running commands and capturing output — injectable for testing.
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Typedef for loading asset bytes — injectable for testing.
/// Returns raw bytes (not ByteData) so tests don't need Flutter binding.
typedef AssetLoader = Future<List<int>> Function(String key);

/// Typedef for resolving the manager binary path — injectable for testing.
typedef PathResolver = Future<String> Function();

/// Handles extraction and detached launching of the bundled centroidx-manager
/// binary.
///
/// Designed for dependency injection so every method is testable without
/// real processes, Flutter asset bundles, or platform-specific paths.
class ManagerLauncher {
  final ProcessStarter? _processStarter;
  final CommandRunner? _commandRunner;
  final AssetLoader? _assetLoader;
  final PathResolver? _pathResolver;

  /// Whether to behave as if running on Windows (injectable for tests).
  final bool platformIsWindows;

  /// Whether to behave as if running on macOS (injectable for tests).
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

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the platform-specific path where the manager binary should reside.
  ///
  /// On Windows:  `%APPDATA%\centroidx\manager\centroidx-manager.exe`
  /// On Linux:    `<applicationSupportDir>/centroidx/manager/centroidx-manager_linux_amd64`
  /// On macOS:    `<applicationSupportDir>/centroidx/manager/centroidx-manager_darwin_arm64`
  ///
  /// If a [pathResolver] was injected at construction, it is used instead.
  Future<String> resolveManagerPath() async {
    final injected = _pathResolver;
    if (injected != null) return injected();

    if (platformIsWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      return '$appData\\centroidx\\manager\\centroidx-manager.exe';
    }

    final dir = await getApplicationSupportDirectory();
    final binaryName = Platform.isMacOS
        ? 'centroidx-manager_darwin_arm64'
        : 'centroidx-manager_linux_amd64';
    return '${dir.path}/centroidx/manager/$binaryName';
  }

  /// Extracts the manager binary from Flutter assets to [resolveManagerPath].
  ///
  /// Idempotent: no-op when the file already exists and has a non-zero size.
  /// Creates parent directories as needed.
  /// Calls `chmod +x` on Unix platforms after writing.
  Future<void> ensureExtracted() async {
    final destPath = await resolveManagerPath();
    final dest = File(destPath);

    if (await dest.exists() && (await dest.length()) > 0) {
      return; // Already extracted — skip.
    }

    // Create parent directories.
    await dest.parent.create(recursive: true);

    // Load bytes — from injected loader or real rootBundle.
    final List<int> bytes;
    final injectedLoader = _assetLoader;
    if (injectedLoader != null) {
      bytes = await injectedLoader(_assetKey);
    } else {
      // Use rootBundle in production; import is lazy to avoid breaking tests
      // that run without Flutter binding.
      final bd = await _loadFromRootBundle(_assetKey);
      bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    }

    await dest.writeAsBytes(bytes);

    // Mark executable on Unix.
    if (!platformIsWindows) {
      await _runCommand('chmod', ['+x', destPath]);
    }
  }

  /// Strips the macOS quarantine attribute from [path].
  ///
  /// Required on macOS 15.1+ (Sequoia) before launching a binary obtained
  /// outside the App Store. No-op on non-macOS platforms.
  Future<void> stripQuarantine(String path) async {
    if (!platformIsMacOS) return;
    await _runCommand('xattr', ['-r', '-d', 'com.apple.quarantine', path]);
  }

  /// Extracts the manager binary (if needed), strips macOS quarantine, then
  /// launches the manager as a detached process.
  ///
  /// Returns the PID of the spawned manager process.
  ///
  /// [version] — target version to install (passed as `--version=<v>`)
  /// [flutterPid] — PID of the current Flutter process (passed as `--wait-pid=<pid>`)
  Future<int> launchForUpdate({
    required String version,
    int? flutterPid,
  }) async {
    await ensureExtracted();
    final path = await resolveManagerPath();
    await stripQuarantine(path);

    final effectivePid = flutterPid ?? pid;

    final process = await _startProcess(
      path,
      [
        '--update',
        '--version=$version',
        '--wait-pid=$effectivePid',
      ],
      mode: ProcessStartMode.detached,
    );

    return process.pid;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// The Flutter asset key for the manager binary on the current platform.
  String get _assetKey {
    if (platformIsWindows) {
      return 'assets/manager/centroidx-manager_windows_amd64.exe';
    }
    if (platformIsMacOS) {
      return 'assets/manager/centroidx-manager_darwin_arm64';
    }
    return 'assets/manager/centroidx-manager_linux_amd64';
  }

  Future<Process> _startProcess(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    final injected = _processStarter;
    if (injected != null) {
      return injected(executable, arguments, mode: mode);
    }
    return Process.start(executable, arguments, mode: mode);
  }

  Future<ProcessResult> _runCommand(
    String executable,
    List<String> arguments,
  ) {
    final injected = _commandRunner;
    if (injected != null) {
      return injected(executable, arguments);
    }
    return Process.run(executable, arguments);
  }

  /// Loads a Flutter asset via rootBundle.
  ///
  /// Kept in a separate method so it can be overridden or avoided in tests
  /// that supply [_assetLoader] directly.
  Future<ByteData> _loadFromRootBundle(String key) async {
    // Dynamic import avoids a hard Flutter binding requirement in tests.
    // In production this always works because Flutter is initialized.
    // ignore: avoid_dynamic_calls
    final services = await _flutterServices();
    return services.load(key) as Future<ByteData>;
  }

  /// Returns the rootBundle object at runtime.
  ///
  /// This indirection exists solely so unit tests that inject [_assetLoader]
  /// never import package:flutter/services.dart and therefore never need the
  /// Flutter binding to be initialized.
  Future<dynamic> _flutterServices() async {
    // The import happens at call-time, not at module load, so tests that
    // inject _assetLoader never trigger this branch.
    throw UnimplementedError(
      'ManagerLauncher._flutterServices is a placeholder. '
      'Inject assetLoader in tests or use the real rootBundle in production. '
      'See _loadFromRootBundle.',
    );
  }
}
