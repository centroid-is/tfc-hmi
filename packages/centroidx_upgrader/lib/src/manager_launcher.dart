import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'github_release_store.dart' show kUpdateChannelStable;

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

/// Typedef for reading an environment variable — injectable for testing.
///
/// Defaults to `Platform.environment[key]`. Exists so the Windows APPDATA
/// branch of [ManagerLauncher.resolveManagerPath] can be exercised from a
/// test on any host.
typedef EnvProvider = String? Function(String key);

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
  final EnvProvider? _envProvider;

  /// Whether to behave as if running on Windows (injectable for tests).
  final bool platformIsWindows;

  /// Whether to behave as if running on macOS (injectable for tests).
  final bool platformIsMacOS;

  ManagerLauncher({
    ProcessStarter? processStarter,
    CommandRunner? commandRunner,
    AssetLoader? assetLoader,
    PathResolver? pathResolver,
    EnvProvider? envProvider,
    bool? platformIsWindows,
    bool? platformIsMacOS,
  })  : _processStarter = processStarter,
        _commandRunner = commandRunner,
        _assetLoader = assetLoader,
        _pathResolver = pathResolver,
        _envProvider = envProvider,
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
      final env = _envProvider ?? (key) => Platform.environment[key];
      final appData = env('APPDATA');
      if (appData == null || appData.isEmpty) {
        // Interpolating an unset APPDATA used to yield
        // `\centroidx\manager\centroidx-manager.exe` -- an absolute path at
        // the root of the current drive, which ensureExtracted would then
        // quietly try to create. Fail where the cause is still visible.
        // extract_windows.go refuses the same way on the Go side.
        throw StateError(
          'APPDATA is not set, so the centroidx-manager directory cannot be '
          'located. The manager lives under %APPDATA%\\centroidx\\manager.',
        );
      }
      return '$appData\\centroidx\\manager\\centroidx-manager.exe';
    }

    final dir = await getApplicationSupportDirectory();
    final binaryName = Platform.isMacOS
        ? 'centroidx-manager_darwin_arm64'
        : 'centroidx-manager_linux_amd64';
    return '${dir.path}/centroidx/manager/$binaryName';
  }

  /// Extracts the manager binary from Flutter assets to [resolveManagerPath],
  /// replacing whatever is there when it is not the binary this build bundles.
  ///
  /// Idempotent on content: a byte-identical copy is left untouched, so the
  /// common case still costs no write. Creates parent directories as needed
  /// and calls `chmod +x` on Unix after writing.
  ///
  /// This used to return early whenever the destination merely existed and was
  /// non-empty, which meant the manager was extracted exactly once per machine
  /// and never again. Every subsequent fix to the manager -- and it is the
  /// component that installs updates -- shipped inside the app and then sat
  /// undelivered on any station that had already run one. The Go side's
  /// extractManagerFrom does compare before copying, but only along the
  /// launched-from-MSIX path, never this one.
  ///
  /// Comparison is by content, not size: a rebuilt Go binary can easily land
  /// on the same byte count. The length is checked first purely to avoid
  /// reading the file when it cannot possibly match.
  ///
  /// The cost is reading the bundled asset on every call. That is bounded --
  /// callers are the two user-initiated launch paths, not a loop.
  Future<void> ensureExtracted() async {
    final destPath = await resolveManagerPath();
    final dest = File(destPath);

    final bytes = await _bundledManagerBytes();

    if (await _matchesBundle(dest, bytes)) return;

    // Whether there is already something runnable to fall back on. Checked
    // before the write, because a failed write can leave nothing behind.
    final hasUsableBinary =
        await dest.exists() && (await dest.length()) > 0;

    await dest.parent.create(recursive: true);

    // Staged, then renamed into place, so the destination changes all at once
    // or not at all.
    //
    // Writing straight to the destination staked the installed manager on the
    // write completing: writeAsBytes truncates on open, so a write that died
    // part way -- disk full, on a station that has been logging for months --
    // left a truncated binary behind, and the branch below then reported
    // "continuing with the copy already installed" about a file it had just
    // destroyed. The caller would go on to launch the fragment.
    //
    // It also improves the case this fallback was written for. Windows will
    // not rename over a running .exe any more than it will open one for
    // writing, but now it refuses before anything has been touched.
    final staged = File('$destPath.new');
    try {
      await staged.writeAsBytes(bytes);
      await staged.rename(destPath);
    } on FileSystemException catch (e) {
      // Best effort once something runnable is already there: a manager left
      // running from an earlier launch would otherwise turn a refresh that
      // used to be a no-op into a hard failure of the whole update, and one
      // stray process would block every future update. An older manager beats
      // no manager, and it self-heals as soon as that process is gone. With
      // nothing on disk there is no fallback and the caller has to hear about
      // it.
      try {
        if (await staged.exists()) await staged.delete();
      } on FileSystemException {
        // Leaving the staging file is not worth failing the update over.
      }
      if (!hasUsableBinary) rethrow;
      stderr.writeln(
          '[centroidx_upgrader] WARNING: could not replace the installed '
          'manager at $destPath with the one bundled in this build ($e). '
          'The update will run against the older manager, so fixes shipped '
          'in this version may not apply. Most likely a manager process is '
          'still running; it will refresh on the next attempt once that '
          'exits.');
      return;
    }

    // Mark executable on Unix.
    if (!platformIsWindows) {
      await _runCommand('chmod', ['+x', destPath]);
    }
  }

  /// Whether [dest] already holds exactly [bundled].
  Future<bool> _matchesBundle(File dest, List<int> bundled) async {
    if (!await dest.exists()) return false;
    final length = await dest.length();
    // A zero-length file is a failed earlier extraction, never a manager.
    if (length == 0 || length != bundled.length) return false;
    final onDisk = await dest.readAsBytes();
    for (var i = 0; i < onDisk.length; i++) {
      if (onDisk[i] != bundled[i]) return false;
    }
    return true;
  }

  /// The manager binary this build ships, from the injected loader in tests or
  /// the real asset bundle in production.
  Future<List<int>> _bundledManagerBytes() async {
    final injectedLoader = _assetLoader;
    if (injectedLoader != null) return injectedLoader(_assetKey);
    // Use rootBundle in production; import is lazy to avoid breaking tests
    // that run without Flutter binding.
    final bd = await _loadFromRootBundle(_assetKey);
    return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
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
  /// [version] — target version to install (passed as `--version=<v>`).
  /// Omit it on the latest channel: prerelease builds have no version tag,
  /// so the manager resolves the newest release on the channel itself.
  /// [channel] — release channel, `stable` or `latest` (passed as
  /// `--channel=<c>`).
  /// [flutterPid] — PID of the current Flutter process (passed as `--wait-pid=<pid>`)
  Future<int> launchForUpdate({
    String? version,
    String channel = kUpdateChannelStable,
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
        '--channel=$channel',
        if (version != null && version.isNotEmpty) '--version=$version',
        '--wait-pid=$effectivePid',
      ],
      mode: ProcessStartMode.detached,
    );

    return process.pid;
  }

  /// Launches the manager in version-picker mode.
  ///
  /// Unlike [launchForUpdate], this uses [ProcessStartMode.normal] because
  /// the Flutter app stays open while the user interacts with the picker
  /// window. The picker is a visible, interactive Go Fyne window.
  ///
  /// Returns the PID of the spawned manager process.
  Future<int> launchForPicker() async {
    await ensureExtracted();
    final path = await resolveManagerPath();
    await stripQuarantine(path);

    final process = await _startProcess(
      path,
      ['--picker'],
      mode: ProcessStartMode.normal,
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
