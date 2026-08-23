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

    // Test 5a: the real Windows branch, exercised. Tests 4 and 5 inject a
    // pathResolver and therefore never run the code that builds the path, so
    // nothing covered the APPDATA lookup itself.
    test('resolveManagerPath builds the APPDATA path on Windows', () async {
      final launcher = ManagerLauncher(
        envProvider: (key) => key == 'APPDATA'
            ? r'C:\Users\Jón\AppData\Roaming'
            : null,
        platformIsWindows: true,
        platformIsMacOS: false,
      );

      expect(
        await launcher.resolveManagerPath(),
        equals(
            r'C:\Users\Jón\AppData\Roaming\centroidx\manager\centroidx-manager.exe'),
      );
    });

    // Test 5b: with APPDATA unset the old code interpolated an empty string
    // and produced `\centroidx\manager\centroidx-manager.exe` — an absolute
    // path at the root of the current drive, which it would then quietly try
    // to create. The Go side (extract_windows.go) errors explicitly here; the
    // Dart side now does too.
    test('resolveManagerPath refuses to build a path when APPDATA is unset',
        () async {
      final launcher = ManagerLauncher(
        envProvider: (_) => null,
        platformIsWindows: true,
        platformIsMacOS: false,
      );

      await expectLater(
        launcher.resolveManagerPath(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('APPDATA'))),
      );
    });

    test('resolveManagerPath refuses to build a path when APPDATA is empty',
        () async {
      final launcher = ManagerLauncher(
        envProvider: (_) => '',
        platformIsWindows: true,
        platformIsMacOS: false,
      );

      await expectLater(
          launcher.resolveManagerPath(), throwsA(isA<StateError>()));
    });

    // -----------------------------------------------------------------------
    // ensureExtracted tests
    // -----------------------------------------------------------------------

    // Test 6: an on-disk binary that already matches the bundle is left alone.
    //
    // "Left alone" is asserted through chmod rather than through the asset
    // loader: the loader now runs unconditionally, because comparing against
    // the bundled asset is the only way to know whether the copy on disk is
    // the current one. chmod only happens after a write, so no chmod means no
    // rewrite.
    test('ensureExtracted leaves the binary alone when it matches the bundle',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      await managerFile.writeAsBytes(_fakeAssetBytes);

      final recorder = _RecordingCommandRunner();

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: recorder.call,
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(recorder.executables, isNot(contains('chmod')),
            reason: 'an identical binary must not be rewritten');
        expect(await managerFile.readAsBytes(), equals(_fakeAssetBytes));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 6a: THE DELIVERY-CHAIN TEST. A stale manager left over from an
    // earlier CentroidX version must be replaced by the one this build
    // bundles. Before this was fixed, ensureExtracted returned early on
    // "exists && length > 0", so every manager fix we shipped sat undelivered
    // on any station that had ever extracted one.
    test('ensureExtracted replaces a stale binary that differs from the bundle',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6a_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      // A previous version's manager: non-empty, so the old exists-check
      // considered it good, but neither the size nor the bytes this build
      // ships. Deliberately a different length from test 6b, so the two
      // together separate "no comparison at all" from "size-only comparison".
      final stale = Uint8List.fromList(List<int>.filled(4, 0xEE));
      expect(stale.length, isNot(_fakeAssetBytes.length));
      await managerFile.writeAsBytes(stale);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(await managerFile.readAsBytes(), equals(_fakeAssetBytes),
            reason: 'a manager from an older build must be replaced');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 6b: same length, different content. Guards against a size-only
    // comparison, which is what the Go side does and what would silently miss
    // a rebuilt manager that happens to land on the same byte count.
    test('ensureExtracted replaces a binary of equal length but different bytes',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6b_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      final sameLength =
          Uint8List.fromList(List<int>.filled(_fakeAssetBytes.length, 0x7F));
      expect(sameLength.length, equals(_fakeAssetBytes.length));
      await managerFile.writeAsBytes(sameLength);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(await managerFile.readAsBytes(), equals(_fakeAssetBytes),
            reason: 'comparison must be by content, not by size');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 6c: a zero-length file is a failed earlier extraction, not a
    // manager. It must be replaced (this held before the change too).
    test('ensureExtracted replaces a zero-length file', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6c_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      await managerFile.writeAsBytes(<int>[]);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(await managerFile.readAsBytes(), equals(_fakeAssetBytes));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 6d: a read-only installed binary gets replaced anyway.
    //
    // This test used to assert the opposite, and it was right to at the time:
    // writing straight to the destination needed write permission on the file
    // itself, so a read-only manager could never be refreshed. Staging changed
    // that — a rename needs write permission on the directory, not on the file
    // being replaced — and the refresh now succeeds. That is the better
    // behaviour, so it is pinned rather than preserved.
    //
    // The best-effort fallback still exists for writes that genuinely cannot
    // complete; test 6f covers it with a failure that staging cannot route
    // around.
    //
    // POSIX only — Windows ignores the mode bits, so there is nothing to prove
    // there.
    test('ensureExtracted replaces a read-only installed binary', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6d_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      await managerFile.writeAsBytes(Uint8List.fromList(List<int>.filled(10, 0xEE)));
      await Process.run('chmod', ['444', managerFile.path]);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(await managerFile.readAsBytes(), equals(_fakeAssetBytes),
            reason: 'staging replaces the file rather than writing through it');
      } finally {
        await Process.run('chmod', ['644', managerFile.path]);
        await tempDir.delete(recursive: true);
      }
    }, skip: Platform.isWindows ? 'read-only mode bits are a POSIX thing' : null);

    // Test 6e: with nothing usable on disk, a failed write is fatal — there is
    // no older manager to fall back to, so swallowing it would leave the
    // caller launching a path that does not exist.
    test('ensureExtracted rethrows when the first extraction cannot be written',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6e_');
      // A directory where the binary should go: writeAsBytes cannot replace it.
      final managerPath = '${tempDir.path}/centroidx-manager';
      await Directory(managerPath).create(recursive: true);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await expectLater(
            launcher.ensureExtracted(), throwsA(isA<FileSystemException>()));

        // The staged write succeeds here and only the rename fails, so this
        // is the path that can strand a full-sized staging file next to the
        // manager. Clean up even while failing.
        expect(await File('$managerPath.new').exists(), isFalse,
            reason: 'a failed refresh must not leave its staging file behind');
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

    // Test 6f: a refresh that fails PART WAY through must not destroy the
    // binary it was replacing.
    //
    // writeAsBytes truncates on open, so writing straight to the destination
    // stakes the installed manager on the write completing. If it dies in the
    // middle -- disk full is the realistic one on a station that has been
    // logging for months -- the old copy is already gone, and the best-effort
    // branch then reports "continuing with the copy already installed" about
    // a file it has just truncated. The warning would be a lie and the caller
    // would go on to launch a partial binary.
    //
    // Staging to a sibling and renaming in makes the destination change all at
    // once or not at all. Forced here by occupying the staging path with a
    // directory, which no write can replace.
    test('a refresh that cannot be staged leaves the installed binary intact',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6f_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      final installed = Uint8List.fromList(List<int>.filled(6, 0xAB));
      await managerFile.writeAsBytes(installed);
      // Occupy the staging path so the staged write cannot succeed.
      await Directory('${managerFile.path}.new').create(recursive: true);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(await managerFile.readAsBytes(), equals(installed),
            reason: 'the installed manager must survive a failed refresh '
                'whole, not truncated');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 6g: staging must not leave litter behind on the happy path.
    test('a successful refresh leaves no staging file behind', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest6g_');
      final managerFile = File('${tempDir.path}/centroidx-manager');
      await managerFile.writeAsBytes(<int>[0xAB]);

      try {
        final launcher = ManagerLauncher(
          pathResolver: () async => managerFile.path,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.ensureExtracted();

        expect(await managerFile.readAsBytes(), equals(_fakeAssetBytes));
        expect(await File('${managerFile.path}.new').exists(), isFalse,
            reason: 'the staging file must be renamed away, not left behind');
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

    // -----------------------------------------------------------------------
    // launchForPicker behavior tests
    // -----------------------------------------------------------------------

    // Test 10: launchForPicker passes --picker flag (and nothing else)
    test('launchForPicker passes --picker flag', () async {
      late List<String> capturedArgs;

      final tempDir = await Directory.systemTemp.createTemp('mltest10_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async {
            capturedArgs = List.unmodifiable(args);
            return _FakeProcess(42);
          },
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.launchForPicker();

        expect(capturedArgs, equals(['--picker']),
            reason: 'launchForPicker should pass only --picker, not --update/--version/--wait-pid');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 11: launchForPicker uses ProcessStartMode.normal
    test('launchForPicker uses ProcessStartMode.normal', () async {
      late ProcessStartMode capturedMode;

      final tempDir = await Directory.systemTemp.createTemp('mltest11_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async {
            capturedMode = mode;
            return _FakeProcess(42);
          },
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.launchForPicker();

        expect(capturedMode, equals(ProcessStartMode.normal),
            reason: 'Picker window stays open alongside Flutter — must not be detached');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 12: launchForPicker returns the PID of the spawned process
    test('launchForPicker returns spawned process PID', () async {
      final tempDir = await Directory.systemTemp.createTemp('mltest12_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async =>
              _FakeProcess(5678),
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        final resultPid = await launcher.launchForPicker();

        expect(resultPid, equals(5678));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 13: launchForPicker calls ensureExtracted (invokes assetLoader when file missing)
    test('launchForPicker calls ensureExtracted', () async {
      var assetLoaderCalled = false;

      final tempDir = await Directory.systemTemp.createTemp('mltest13_');
      // Use a path that doesn't exist so ensureExtracted actually writes
      final managerPath = '${tempDir.path}/nested/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async =>
              _FakeProcess(42),
          pathResolver: () async => managerPath,
          assetLoader: (key) async {
            assetLoaderCalled = true;
            return _fakeAssetBytes;
          },
          commandRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        await launcher.launchForPicker();

        expect(assetLoaderCalled, isTrue,
            reason: 'ensureExtracted should be called, which invokes assetLoader when file is missing');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    // Test 14: launchForPicker calls stripQuarantine on macOS
    test('launchForPicker strips quarantine on macOS', () async {
      final recorder = _RecordingCommandRunner();

      final tempDir = await Directory.systemTemp.createTemp('mltest14_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async =>
              _FakeProcess(42),
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          commandRunner: recorder.call,
          platformIsWindows: false,
          platformIsMacOS: true,
        );

        await launcher.launchForPicker();

        expect(recorder.executables, contains('xattr'),
            reason: 'stripQuarantine should call xattr on macOS');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('ManagerLauncher channels', () {
    /// Launches an update with the given arguments and returns the CLI args
    /// the manager was started with.
    Future<List<String>> capturedUpdateArgs({
      String? version,
      String? channel,
    }) async {
      late List<String> capturedArgs;
      final tempDir = await Directory.systemTemp.createTemp('mlchan_');
      final managerPath = '${tempDir.path}/centroidx-manager';

      try {
        final launcher = ManagerLauncher(
          processStarter: (exe, args, {mode = ProcessStartMode.normal}) async {
            capturedArgs = List.unmodifiable(args);
            return _FakeProcess(42);
          },
          pathResolver: () async => managerPath,
          assetLoader: (_) async => _fakeAssetBytes,
          platformIsWindows: false,
          platformIsMacOS: false,
        );

        if (channel != null) {
          await launcher.launchForUpdate(
            version: version,
            channel: channel,
            flutterPid: 9999,
          );
        } else {
          await launcher.launchForUpdate(version: version, flutterPid: 9999);
        }
        return capturedArgs;
      } finally {
        await tempDir.delete(recursive: true);
      }
    }

    test('defaults to the stable channel', () async {
      final args = await capturedUpdateArgs(version: '2026.4.1');

      expect(
          args,
          containsAllInOrder(
              ['--update', '--channel=stable', '--version=2026.4.1']));
    });

    test('passes the latest channel and omits the version when not given',
        () async {
      final args = await capturedUpdateArgs(channel: kUpdateChannelLatest);

      expect(args, containsAllInOrder(['--update', '--channel=latest']));
      expect(args.where((a) => a.startsWith('--version')), isEmpty,
          reason: 'the manager resolves the newest release on the channel');
    });

    test('omits the version when it is empty', () async {
      final args = await capturedUpdateArgs(version: '');

      expect(args.where((a) => a.startsWith('--version')), isEmpty);
    });
  });
}
