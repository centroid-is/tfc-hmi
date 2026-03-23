import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:centroidx_upgrader/centroidx_upgrader.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A fake [Process] implementation that returns a fixed PID.
class _FakeProcess implements Process {
  final int _pid;

  _FakeProcess(this._pid);

  @override
  int get pid => _pid;

  @override
  Future<int> get exitCode => Future.value(0);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError('stdin not used in tests');
}

/// Minimal 10-byte "binary" content used as fake asset data.
final Uint8List _fakeAssetBytes = Uint8List.fromList(
  List<int>.generate(10, (i) => i + 1),
);

/// Captures calls made to the [CommandRunner].
class _RecordingCommandRunner {
  final List<String> executables = [];
  final List<List<String>> argumentLists = [];

  Future<ProcessResult> call(String executable, List<String> args) async {
    executables.add(executable);
    argumentLists.add(args);
    return ProcessResult(0, 0, '', '');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ManagerLauncher', () {
    // -----------------------------------------------------------------------
    // launchForUpdate behavior tests
    // -----------------------------------------------------------------------

    // Test 1: passes correct CLI args to processStarter
    test('launchForUpdate passes --update, --version, --wait-pid args to process starter', () async {
      late String capturedExecutable;
      late List<String> capturedArgs;

      // Use a temp directory so ensureExtracted has a real path to write to.
      final tempDir = await Directory.systemTemp.createTemp('mltest1_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        Future<Process> fakeStarter(
          String exe,
          List<String> args, {
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          capturedExecutable = exe;
          capturedArgs = List.unmodifiable(args);
          return _FakeProcess(42);
        }

        Future<String> pathResolver() async => managerPath;

        Future<List<int>> assetLoader(String key) async =>
            _fakeAssetBytes;

        final launcher = ManagerLauncher(
          processStarter: fakeStarter,
          pathResolver: pathResolver,
          assetLoader: assetLoader,
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.launchForUpdate(version: '2026.4.1', flutterPid: 9999);

        expect(capturedArgs, containsAllInOrder([
          '--update',
          '--version=2026.4.1',
          '--wait-pid=9999',
        ]));
        expect(capturedExecutable, equals(managerPath));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 2: uses ProcessStartMode.detached
    test('launchForUpdate uses ProcessStartMode.detached', () async {
      late ProcessStartMode capturedMode;

      final tempDir = await Directory.systemTemp.createTemp('mltest2_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        Future<Process> fakeStarter(
          String exe,
          List<String> args, {
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          capturedMode = mode;
          return _FakeProcess(42);
        }

        final launcher = ManagerLauncher(
          processStarter: fakeStarter,
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.launchForUpdate(version: '2026.4.1', flutterPid: 1);

        expect(capturedMode, equals(ProcessStartMode.detached));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 3: returns the PID of the spawned process
    test('launchForUpdate returns the PID from the spawned process', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest3_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async =>
              _FakeProcess(1234),
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        final pid = await launcher.launchForUpdate(
            version: '2026.4.1', flutterPid: 1);

        expect(pid, equals(1234));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // resolveManagerPath tests
    // -----------------------------------------------------------------------

    // Test 4: resolveManagerPath returns APPDATA-based path on Windows
    test('resolveManagerPath returns APPDATA-based path on Windows', () async {
      // Inject a pathResolver that mimics the Windows path.
      const fakeAppData = r'C:\Users\User\AppData\Roaming';
      final launcher = ManagerLauncher(
        pathResolver: () async =>
            '$fakeAppData\\centroidx\\manager\\centroidx-manager.exe',
        platformIsWindows: true,
        platformIsMacOS: false,
      );

      final path = await launcher.resolveManagerPath();

      expect(path, contains('centroidx'));
      expect(path, contains('manager'));
      expect(path, endsWith('centroidx-manager.exe'));
    });

    // Test 5: resolveManagerPath returns application support path on non-Windows
    test('resolveManagerPath returns application support path on non-Windows', () async {
      const fakeSupportDir = '/home/user/.local/share';
      final launcher = ManagerLauncher(
        pathResolver: () async =>
            '$fakeSupportDir/centroidx/manager/centroidx-manager_linux_amd64',
        platformIsWindows: false,
        platformIsMacOS: false,
      );

      final path = await launcher.resolveManagerPath();

      expect(path, contains('centroidx'));
      expect(path, contains('manager'));
      expect(path, contains('centroidx-manager_linux_amd64'));
    });

    // -----------------------------------------------------------------------
    // ensureExtracted tests
    // -----------------------------------------------------------------------

    // Test 6: ensureExtracted skips extraction when file already exists with non-zero size
    test('ensureExtracted skips extraction when file already exists with non-zero size', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      // Write existing content so the file is non-empty
      await managerFile.writeAsBytes([1, 2, 3, 4, 5]);

      var assetLoaderCalled = false;

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (key) async {
            assetLoaderCalled = true;
            return _fakeAssetBytes;
          },
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(assetLoaderCalled, isFalse,
            reason: 'Should not load asset when file already exists');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 7: ensureExtracted creates parent dirs and writes bytes when file missing
    test('ensureExtracted creates parent directories and writes bytes when file missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest7_');
      // Nested path that does not exist yet
      final managerPath =
          '${tempDir.path}/nested/dir/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          platformIsWindows: false,
          platformIsMacOS: false,
          // Override commandRunner so chmod doesn't fail (no real binary)
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
        );

        await launcher.ensureExtracted();

        final dest = File(managerPath);
        expect(await dest.exists(), isTrue);
        expect(await dest.length(), equals(_fakeAssetBytes.length));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // stripQuarantine and chmod tests
    // -----------------------------------------------------------------------

    // Test 8: stripQuarantine calls xattr on macOS
    test('stripQuarantine calls xattr on macOS', () async {
      final recorder = _RecordingCommandRunner();

      final launcher = ManagerLauncher(
        commandRunner: recorder.call,
        platformIsWindows: false,
        platformIsMacOS: true,
      );

      await launcher.stripQuarantine('/path/to/centroidx-manager');

      expect(recorder.executables, contains('xattr'));
      expect(recorder.argumentLists.first,
          containsAllInOrder(['-r', '-d', 'com.apple.quarantine', '/path/to/centroidx-manager']));
    });

    // Test 9: ensureExtracted calls chmod +x on non-Windows platforms
    test('ensureExtracted calls chmod +x on non-Windows platforms', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest9_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      final recorder = _RecordingCommandRunner();

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: recorder.call,
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        final chmodCalls = recorder.executables
            .asMap()
            .entries
            .where((e) => e.value == 'chmod')
            .toList();

        expect(chmodCalls, isNotEmpty, reason: 'chmod should be called on Unix');
        final chmodArgs = recorder.argumentLists[chmodCalls.first.key];
        expect(chmodArgs, containsAllInOrder(['+x', managerPath]));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
