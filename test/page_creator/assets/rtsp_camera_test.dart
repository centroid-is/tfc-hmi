import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/page_creator/assets/rtsp_camera.dart';

/// Stands in for the media_kit backend: the view must never construct a real
/// player in tests (libmpv is not loadable under `flutter test`).
class _FakePlayback implements RtspCameraPlayback {
  _FakePlayback(this.config);
  final RtspCameraConfig config;
  final statusNotifier = ValueNotifier<RtspCameraStatus>(
    RtspCameraStatus.connecting,
  );
  bool disposed = false;

  @override
  ValueListenable<RtspCameraStatus> get status => statusNotifier;

  @override
  Widget buildVideo(BuildContext context, BoxFit fit) =>
      const ColoredBox(key: Key('fake-video'), color: Color(0xFF223344));

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  tearDown(() => RtspCameraView.debugPlaybackFactory = null);

  group('RtspCameraConfig JSON', () {
    test('fields survive a round trip', () {
      final config = RtspCameraConfig(
        url: 'rtsp://10.0.0.5:554/stream1',
        fit: BoxFit.contain,
        muted: false,
      )
        ..text = 'Packing hall'
        ..coordinates = Coordinates(x: 0.25, y: 0.5);
      final restored = RtspCameraConfig.fromJson(config.toJson());
      expect(restored.url, 'rtsp://10.0.0.5:554/stream1');
      expect(restored.fit, BoxFit.contain);
      expect(restored.muted, false);
      expect(restored.text, 'Packing hall');
    });

    test('registry parses it back out of page JSON', () {
      final config = RtspCameraConfig(url: 'rtsp://cam/1');
      final parsed = AssetRegistry.parse({
        'page': [config.toJson()],
      });
      expect(parsed, hasLength(1));
      expect(parsed.single, isA<RtspCameraConfig>());
      expect((parsed.single as RtspCameraConfig).url, 'rtsp://cam/1');
    });

    test('palette default is unconfigured and muted', () {
      final preview =
          AssetRegistry.createDefaultAsset(RtspCameraConfig) as RtspCameraConfig;
      expect(preview.url, isEmpty);
      expect(preview.muted, isTrue);
    });
  });

  group('RtspCameraView', () {
    testWidgets('empty url renders placeholder and starts no playback',
        (tester) async {
      var factoryCalls = 0;
      RtspCameraView.debugPlaybackFactory = (config) {
        factoryCalls++;
        return _FakePlayback(config);
      };
      await tester.pumpWidget(_hostView(RtspCameraConfig()));
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
      expect(factoryCalls, 0);
    });

    testWidgets('status drives spinner, video + LIVE badge, and no-signal',
        (tester) async {
      late _FakePlayback playback;
      RtspCameraView.debugPlaybackFactory = (config) {
        playback = _FakePlayback(config);
        return playback;
      };
      await tester
          .pumpWidget(_hostView(RtspCameraConfig(url: 'rtsp://cam/1')));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);

      playback.statusNotifier.value = RtspCameraStatus.live;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('LIVE'), findsOneWidget);

      playback.statusNotifier.value = RtspCameraStatus.noSignal;
      await tester.pump();
      expect(find.text('LIVE'), findsNothing);
      expect(find.text('No signal'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
    });

    testWidgets('a throwing backend degrades to the unavailable placeholder',
        (tester) async {
      RtspCameraView.debugPlaybackFactory =
          (config) => throw UnsupportedError('no libmpv here');
      await tester
          .pumpWidget(_hostView(RtspCameraConfig(url: 'rtsp://cam/1')));
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('url change disposes the old playback and opens a new one',
        (tester) async {
      final created = <_FakePlayback>[];
      RtspCameraView.debugPlaybackFactory = (config) {
        final p = _FakePlayback(config);
        created.add(p);
        return p;
      };
      await tester
          .pumpWidget(_hostView(RtspCameraConfig(url: 'rtsp://cam/1')));
      expect(created, hasLength(1));

      await tester
          .pumpWidget(_hostView(RtspCameraConfig(url: 'rtsp://cam/2')));
      expect(created, hasLength(2));
      expect(created.first.disposed, isTrue);
      expect(created.first.config.url, 'rtsp://cam/1');
      expect(created.last.config.url, 'rtsp://cam/2');

      await tester.pumpWidget(const SizedBox());
      expect(created.last.disposed, isTrue);
    });
  });

  group('config editor', () {
    testWidgets('edits url, fit and muted on the config', (tester) async {
      final config = RtspCameraConfig();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => config.configure(context)),
        ),
      ));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Stream URL'),
          ' rtsp://cam/1 ');
      expect(config.url, 'rtsp://cam/1');

      await tester.tap(find.text('Muted'));
      await tester.pump();
      expect(config.muted, isFalse);

      await tester.tap(find.text('cover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('contain').last);
      await tester.pumpAndSettle();
      expect(config.fit, BoxFit.contain);
    });
  });
}

Widget _hostView(RtspCameraConfig config) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 240,
            child: RtspCameraView(config: config),
          ),
        ),
      ),
    );
