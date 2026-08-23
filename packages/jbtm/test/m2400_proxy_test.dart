import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:jbtm/jbtm.dart';
import 'package:test/test.dart';

/// Number of *socket* descriptors this process currently holds.
///
/// Deliberately not "every descriptor". A raw count is not a leak detector:
/// the Dart VM opens epoll/eventfd/timerfd handles lazily, `Directory.listSync`
/// holds a descriptor for the directory it is reading, and on macOS
/// `Process.runSync` needs a pipe to read lsof's own output. Any of those can
/// move a raw count by one between two samples with nothing leaked — which is
/// exactly how the first version of this test failed on Linux while passing on
/// macOS.
///
/// The subject of these tests is sockets, so count sockets and nothing else.
/// That is *tighter* than the raw count, not looser: it removes the noise, so
/// the assertions below can demand an exact figure instead of carrying slack.
///
/// POSIX only — `fdLeakSkip` guards the call sites, so this is never reached
/// on Windows.
int socketFdCount() {
  if (Platform.isLinux) {
    var count = 0;
    for (final entry in Directory('/proc/self/fd').listSync()) {
      try {
        // A socket descriptor's /proc link target is literally "socket:[inode]".
        if (Link(entry.path).targetSync().startsWith('socket:[')) count++;
      } on FileSystemException {
        // The descriptor went away between readdir and readlink — including
        // the listing's own directory descriptor. Not a socket either way.
      }
    }
    return count;
  }
  // macOS has no /proc, and listing /dev/fd races against the listing's own
  // descriptor. lsof is part of the base system and is present on the GitHub
  // macos runners. Column 4 is TYPE.
  final result = Process.runSync('lsof', ['-nP', '-p', '$pid']);
  if (result.exitCode != 0) {
    throw StateError('lsof failed: ${result.stderr}');
  }
  return (result.stdout as String).split('\n').where((line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    return fields.length > 4 &&
        const {'IPv4', 'IPv6', 'unix'}.contains(fields[4]);
  }).length;
}

// ---- TEMPORARY fdlinux probe 3 -------------------------------------------
int rawFdCount() => Platform.isLinux
    ? Directory('/proc/self/fd').listSync().length
    : (Process.runSync('lsof', ['-p', '$pid']).stdout as String)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .length;

Map<String, String> fdSnapshot() {
  final out = <String, String>{};
  if (!Platform.isLinux) return out;
  for (final e in Directory('/proc/self/fd').listSync()) {
    try {
      out[e.path.split('/').last] = Link(e.path).targetSync();
    } catch (_) {
      out[e.path.split('/').last] = '<unreadable/self>';
    }
  }
  return out;
}

void dumpFd(String label, Map<String, String> before, Map<String, String> now) {
  if (!Platform.isLinux) return;
  print('[fdlinux] $label before=${before.length} now=${now.length}');
  for (final e in before.entries) {
    if (now[e.key] != e.value) print('[fdlinux] $label  -fd ${e.key} ${e.value}');
  }
  for (final e in now.entries) {
    if (before[e.key] != e.value) print('[fdlinux] $label  +fd ${e.key} ${e.value}');
  }
}
// ---- end TEMPORARY --------------------------------------------------------

/// Skip reason for descriptor-counting tests, or null when they can run.
final String? fdLeakSkip =
    Platform.isWindows ? 'no POSIX file-descriptor table on Windows' : null;

void main() {
  // TestTcpServer acts as the fake upstream M2400 device.
  late TestTcpServer upstream;

  // The proxy under test.
  late M2400Proxy proxy;

  // Track downstream sockets for cleanup.
  final downstreamSockets = <Socket>[];

  setUp(() async {
    upstream = TestTcpServer();
    await upstream.start();

    proxy = M2400Proxy(
      upstreamHost: 'localhost',
      upstreamPort: upstream.port,
      listenPort: 0, // OS-assigned
      listenAddress: InternetAddress.loopbackIPv4,
    );
  });

  tearDown(() async {
    for (final s in downstreamSockets) {
      s.destroy();
    }
    downstreamSockets.clear();
    await proxy.shutdown();
    await upstream.shutdown();
  });

  /// Connect a raw downstream client to the proxy.
  Future<Socket> connectClient(int port) async {
    final socket = await Socket.connect('localhost', port);
    downstreamSockets.add(socket);
    return socket;
  }

  /// Collect all data from a socket into a list of byte chunks.
  List<Uint8List> collectData(Socket socket) {
    final chunks = <Uint8List>[];
    socket.listen(
      (data) => chunks.add(Uint8List.fromList(data)),
      onError: (_) {},
    );
    return chunks;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  group('lifecycle', () {
    test('start() binds listen port and connects upstream', () async {
      await proxy.start();

      // Upstream should see the proxy connect
      await upstream.waitForClient();
      expect(upstream.clientCount, equals(1));
    });

    test('shutdown() closes all downstream clients', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      final disconnected = Completer<void>();
      client.listen((_) {}, onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      }, onError: (_) {
        if (!disconnected.isCompleted) disconnected.complete();
      });

      await proxy.shutdown();
      await disconnected.future.timeout(const Duration(seconds: 2));
    });

    test('shutdown() is safe to call multiple times', () async {
      await proxy.start();
      await proxy.shutdown();
      await proxy.shutdown(); // should not throw
    });
  });

  // ---------------------------------------------------------------------------
  // Fan-out
  // ---------------------------------------------------------------------------
  group('fan-out', () {
    test('upstream data reaches a single downstream client', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      final chunks = collectData(client);
      final payload = [1, 2, 3, 4, 5];
      upstream.sendToAll(payload);

      await Future.delayed(const Duration(milliseconds: 100));
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals(payload));
    });

    test('upstream data reaches multiple clients simultaneously', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client1 = await connectClient(proxy.listenPort);
      final client2 = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      final chunks1 = collectData(client1);
      final chunks2 = collectData(client2);

      final payload = [10, 20, 30];
      upstream.sendToAll(payload);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(chunks1.expand((c) => c).toList(), equals(payload));
      expect(chunks2.expand((c) => c).toList(), equals(payload));
    });

    test('new client receives only data sent after connection (no replay)',
        () async {
      await proxy.start();
      await upstream.waitForClient();

      // Send data before any client connects
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Now connect a client
      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send new data
      upstream.sendToAll([4, 5, 6]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Client should only see [4, 5, 6], not [1, 2, 3]
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([4, 5, 6]));
    });
  });

  // ---------------------------------------------------------------------------
  // Client management
  // ---------------------------------------------------------------------------
  group('client management', () {
    test('clientCount tracks connections accurately', () async {
      await proxy.start();
      await upstream.waitForClient();
      expect(proxy.clientCount, equals(0));

      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(2));
    });

    test('handles client disconnect gracefully', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client1 = await connectClient(proxy.listenPort);
      final client2 = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(2));

      // Disconnect client1
      client1.destroy();
      downstreamSockets.remove(client1);
      // Wait for the server-side done handler to fire
      await Future.delayed(const Duration(milliseconds: 300));
      expect(proxy.clientCount, equals(1));

      // client2 should still receive data
      final chunks = collectData(client2);
      upstream.sendToAll([7, 8, 9]);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(chunks.expand((c) => c).toList(), equals([7, 8, 9]));
    });
  });

  // ---------------------------------------------------------------------------
  // Network loss — upstream
  // ---------------------------------------------------------------------------
  group('upstream network loss', () {
    test('downstream clients stay connected when upstream disconnects',
        () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      // Simulate upstream device reboot
      upstream.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 200));

      // Client should still be connected (proxy doesn't drop clients on
      // upstream loss)
      expect(proxy.clientCount, equals(1));

      // Verify client socket is still writable (not errored)
      expect(() => client.add([0]), returnsNormally);
    });

    test('data resumes flowing after upstream reconnects', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send initial data
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Disconnect upstream
      upstream.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 200));

      // MSocket will auto-reconnect — wait for it
      await upstream.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send data on the new upstream connection
      upstream.sendToAll([4, 5, 6]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Client should have received both payloads
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, containsAllInOrder([1, 2, 3]));
      expect(allBytes, containsAllInOrder([4, 5, 6]));
    });

    test('proxy stays up when upstream never connects', () async {
      // Create proxy pointing at a port nothing is listening on
      final nowhereProxy = M2400Proxy(
        upstreamHost: 'localhost',
        upstreamPort: 59999, // nothing here
        listenPort: 0,
        listenAddress: InternetAddress.loopbackIPv4,
      );

      await nowhereProxy.start();

      // Clients can still connect to the proxy
      final client =
          await Socket.connect('localhost', nowhereProxy.listenPort);
      downstreamSockets.add(client);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(nowhereProxy.clientCount, equals(1));

      await nowhereProxy.shutdown();
    });
  });

  // ---------------------------------------------------------------------------
  // Network loss — downstream
  // ---------------------------------------------------------------------------
  group('downstream network loss', () {
    test('abrupt client disconnect handled without error', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      // Abrupt disconnect
      client.destroy();
      downstreamSockets.remove(client);

      // Send data — proxy should handle the dead client without crashing
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 100));

      // No crash, clientCount updated
      expect(proxy.clientCount, equals(0));
    });

    test('all clients disconnect, proxy continues', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client1 = await connectClient(proxy.listenPort);
      final client2 = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      client1.destroy();
      client2.destroy();
      downstreamSockets.clear();
      // Wait for the server-side done handlers to fire
      await Future.delayed(const Duration(milliseconds: 300));

      expect(proxy.clientCount, equals(0));

      // New client can still connect
      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));
    });

    test('client connects during upstream disconnect, receives data on recovery',
        () async {
      await proxy.start();
      await upstream.waitForClient();

      // Disconnect upstream
      upstream.disconnectAll();
      await Future.delayed(const Duration(milliseconds: 100));

      // Client connects while upstream is down
      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      expect(proxy.clientCount, equals(1));

      // Wait for upstream to reconnect
      await upstream.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send data on the new upstream connection
      upstream.sendToAll([10, 20, 30]);
      await Future.delayed(const Duration(milliseconds: 100));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([10, 20, 30]));
    });
  });

  // ---------------------------------------------------------------------------
  // Packet fragmentation / chunking
  // ---------------------------------------------------------------------------
  group('packet handling', () {
    test('large payload forwarded correctly', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send a large payload (64KB)
      final bigPayload = List<int>.generate(65536, (i) => i % 256);
      upstream.sendToAll(bigPayload);

      // Wait enough for all data to arrive
      await Future.delayed(const Duration(milliseconds: 500));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals(bigPayload));
    });

    test('rapid burst of small packets all forwarded', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send 100 tiny packets rapidly
      for (var i = 0; i < 100; i++) {
        upstream.sendToAll([i]);
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, hasLength(100));
      for (var i = 0; i < 100; i++) {
        expect(allBytes[i], equals(i));
      }
    });

    test('partial M2400 frames forwarded transparently', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      final chunks = collectData(client);

      // Send a partial frame (STX but no ETX) — proxy shouldn't care
      final partialFrame = [0x02, 0x41, 0x42, 0x43]; // STX + "ABC"
      upstream.sendToAll(partialFrame);

      await Future.delayed(const Duration(milliseconds: 100));

      // Then send the rest
      final rest = [0x44, 0x45, 0x03]; // "DE" + ETX
      upstream.sendToAll(rest);

      await Future.delayed(const Duration(milliseconds: 100));

      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([...partialFrame, ...rest]));
    });
  });

  // ---------------------------------------------------------------------------
  // Stress / edge cases
  // ---------------------------------------------------------------------------
  group('edge cases', () {
    test('client connects and immediately disconnects', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      client.destroy();
      downstreamSockets.remove(client);

      // Send data — should not crash
      await Future.delayed(const Duration(milliseconds: 100));
      upstream.sendToAll([1, 2, 3]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Proxy still operational
      expect(proxy.clientCount, equals(0));
    });

    test('multiple clients connect simultaneously', () async {
      await proxy.start();
      await upstream.waitForClient();

      // Connect 10 clients at once
      final futures = List.generate(
        10,
        (_) => connectClient(proxy.listenPort),
      );
      await Future.wait(futures);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(proxy.clientCount, equals(10));

      // All should receive data
      final allChunks = <List<Uint8List>>[];
      for (final client in downstreamSockets) {
        allChunks.add(collectData(client));
      }

      upstream.sendToAll([42]);
      await Future.delayed(const Duration(milliseconds: 100));

      for (final chunks in allChunks) {
        final bytes = chunks.expand((c) => c).toList();
        expect(bytes, equals([42]));
      }
    });

    test('shutdown during active data flow', () async {
      await proxy.start();
      await upstream.waitForClient();

      await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));

      // Start sending data and immediately shutdown — should not crash
      upstream.sendToAll([1, 2, 3]);
      await proxy.shutdown();
      // If we get here without exception, the test passes
    });
  });

  // ---------------------------------------------------------------------------
  // Descriptor lifetime
  //
  // Every other downstream-disconnect test above uses `client.destroy()` — an
  // abrupt RST, which self-cleans. The *graceful* path (peer sends FIN, i.e.
  // `close()`) is what the docker healthcheck in docker/weigher-proxy does
  // every 30s, and it closes only the read half. dart:io frees the descriptor
  // when both halves are shut, and Socket carries no NativeFinalizer, so an
  // unreachable Socket the proxy simply dropped from `_clients` keeps its
  // descriptor for the life of the process.
  // ---------------------------------------------------------------------------
  group('descriptor lifetime', () {
    test('graceful client close makes the proxy close its half too', () async {
      await proxy.start();
      await upstream.waitForClient();

      final client = await connectClient(proxy.listenPort);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(proxy.clientCount, equals(1));

      // The proxy closing its side surfaces on this client as either a FIN
      // (done) or an RST (error) depending on timing; both mean the peer
      // descriptor is gone.
      final peerClosed = Completer<void>();
      void signal() {
        if (!peerClosed.isCompleted) peerClosed.complete();
      }

      client.listen((_) {}, onDone: signal, onError: (_) => signal());

      // Half-close: shut the write side only, exactly like
      // `exec 3<>/dev/tcp/host/port` returning in the healthcheck.
      unawaited(client.close());

      await peerClosed.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail(
          'proxy never closed its half of a gracefully-closed client — '
          'the accepted socket (and its descriptor) is leaked',
        ),
      );
      expect(proxy.clientCount, equals(0));
    });

    test('repeated graceful connect/close cycles return fds to baseline',
        () async {
      await proxy.start();
      await upstream.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      const cycles = 60;
      final baseline = socketFdCount();

      for (var i = 0; i < cycles; i++) {
        final client = await Socket.connect(
          InternetAddress.loopbackIPv4,
          proxy.listenPort,
        );
        client.listen((_) {}, onError: (_) {});
        // Graceful close, then release this side entirely so the only
        // descriptor a growing count can be attributed to is the proxy's.
        unawaited(client.close());
        client.destroy();
        await Future.delayed(const Duration(milliseconds: 2));
      }

      await Future.delayed(const Duration(milliseconds: 300));

      expect(proxy.clientCount, equals(0));

      final after = socketFdCount();
      // No slack. Every socket opened by a cycle — the test's client and the
      // proxy's accepted peer — is closed by the end of that cycle, so the
      // socket count must land exactly back on the baseline. (A socket in
      // TIME_WAIT is a kernel table entry, not a descriptor, so it does not
      // show up here.) The leak this test was written for is 1:1 with the
      // cycle count, but an off-by-one leak is just as real, and counting only
      // sockets is what makes it safe to say so.
      expect(
        after - baseline,
        lessThanOrEqualTo(0),
        reason: 'leaked ${after - baseline} socket descriptors over $cycles '
            'graceful connect/close cycles (baseline $baseline, now $after)',
      );
    }, skip: fdLeakSkip);

    test('shutdown() leaves no descriptors behind after graceful churn',
        () async {
      await proxy.start();
      await upstream.waitForClient();
      await Future.delayed(const Duration(milliseconds: 100));

      // TEMPORARY fdlinux probe 3.
      // (a) Is the RAW descriptor count stable while nothing happens, and is
      //     the SOCKET count stable over the same window?
      final idleRaw = <int>[];
      final idleSock = <int>[];
      for (var i = 0; i < 120; i++) {
        idleRaw.add(rawFdCount());
        idleSock.add(socketFdCount());
        await Future.delayed(const Duration(milliseconds: 20));
      }
      int lo(List<int> v) => v.reduce((a, b) => a < b ? a : b);
      int hi(List<int> v) => v.reduce((a, b) => a > b ? a : b);
      print('[fdlinux] idle raw=${lo(idleRaw)}..${hi(idleRaw)} '
          'sock=${lo(idleSock)}..${hi(idleSock)}');

      // (b) 100 repeats of the exact sequence, RAW count, dumping descriptor
      //     identity for any repeat that does not land on -2.
      final deviations = <String>[];
      var repeats = 0;
      for (var iter = 0; iter < 100; iter++) {
        final up = TestTcpServer();
        await up.start();
        final p = M2400Proxy(
          upstreamHost: 'localhost',
          upstreamPort: up.port,
          listenPort: 0,
          listenAddress: InternetAddress.loopbackIPv4,
        );
        await p.start();
        await up.waitForClient();
        await Future.delayed(const Duration(milliseconds: 100));

        final rawBase = rawFdCount();
        final sockBase = socketFdCount();
        final snapBase = fdSnapshot();

        for (var i = 0; i < 30; i++) {
          final c = await Socket.connect(
            InternetAddress.loopbackIPv4,
            p.listenPort,
          );
          c.listen((_) {}, onError: (_) {});
          unawaited(c.close());
          c.destroy();
          await Future.delayed(const Duration(milliseconds: 2));
        }

        await p.shutdown();
        await Future.delayed(const Duration(milliseconds: 300));
        final rawDelta = rawFdCount() - rawBase;
        final sockDelta = socketFdCount() - sockBase;
        repeats++;
        if (rawDelta != -2 || sockDelta != -2) {
          deviations.add('#$iter rawDelta=$rawDelta sockDelta=$sockDelta '
              'clientsAfter=${p.clientCount}');
          dumpFd('#$iter', snapBase, fdSnapshot());
        }
        await up.shutdown();
      }
      fail('fdlinux probe3: $repeats repeats, '
          '${deviations.length} deviations\n${deviations.join('\n')}');

      // ignore: dead_code
      final baseline = socketFdCount();

      for (var i = 0; i < 30; i++) {
        final client = await Socket.connect(
          InternetAddress.loopbackIPv4,
          proxy.listenPort,
        );
        client.listen((_) {}, onError: (_) {});
        unawaited(client.close());
        client.destroy();
        await Future.delayed(const Duration(milliseconds: 2));
      }

      await proxy.shutdown();
      await Future.delayed(const Duration(milliseconds: 300));

      // shutdown() only walks `_clients`; anything already dropped from that
      // list is unreachable and cannot be reclaimed here. So the churn must
      // already have returned to baseline before shutdown ran, and shutdown
      // itself must then reclaim exactly two sockets: the listen socket and
      // the upstream connection.
      //
      // Naming that figure — rather than asserting a slack-carrying "no worse
      // than baseline" — is the point. `<= baseline` would still pass with the
      // listen socket left open.
      final after = socketFdCount();
      expect(
        after,
        equals(baseline - 2),
        reason: 'after shutdown, $after socket fds vs baseline $baseline; '
            'shutdown() must reclaim the listen socket and the upstream '
            'connection and leave nothing else behind',
      );
    }, skip: fdLeakSkip, timeout: const Timeout(Duration(minutes: 10)));
  });
}
