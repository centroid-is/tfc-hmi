import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/mcp/app_capture.dart';
import 'package:tfc/mcp/app_screen_capturer.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show
        CapturedImage,
        ScreenCaptureRasterizationException,
        ScreenCaptureUnavailableException;

/// The eight bytes every PNG starts with.
const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Decodes [bytes] with the real image codec, so "it is a PNG" means the
/// engine agrees rather than the first eight bytes looking right.
Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  /// A recognisable little tree: a coloured ground with text on it, so a
  /// capture that silently produced an empty layer would still be caught by
  /// the size assertions.
  Widget shell() => Container(
        color: const Color(0xFF102030),
        alignment: Alignment.center,
        child: const Text(
          'HMI',
          textDirection: TextDirection.ltr,
          style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 32),
        ),
      );

  Future<void> pumpScope(
    WidgetTester tester,
    AppCaptureController controller, {
    Size surface = const Size(400, 300),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: AppCaptureScope(controller: controller, child: shell()),
    ));
  }

  group('captureWindow', () {
    testWidgets('returns a decodable PNG the size of the app shell',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-window');
      await pumpScope(tester, controller);

      expect(controller.isAttached, isTrue);
      expect(controller.windowSize, const Size(400, 300));

      final captured = await tester.runAsync(
        () => controller.captureWindow(maxWidth: 4096),
      );

      expect(captured, isNotNull);
      final image = captured!;
      expect(image.pngBytes.take(8), _pngMagic);
      expect(image.width, 400);
      expect(image.height, 300);
      expect(image.logicalWidth, 400);
      expect(image.logicalHeight, 300);
      expect(image.pixelRatio, 1.0);

      final decoded = await tester.runAsync(() => _decode(image.pngBytes));
      expect(decoded!.width, 400);
      expect(decoded.height, 300);
      decoded.dispose();
    });

    testWidgets('max_width renders at a smaller pixel ratio', (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-narrow');
      await pumpScope(tester, controller);

      final image = (await tester.runAsync(
        () => controller.captureWindow(maxWidth: 200),
      ))!;

      // Half the width, so half the pixel ratio and half the height -- the
      // layout is unchanged, only the rasterization is smaller.
      expect(image.width, 200);
      expect(image.height, 150);
      expect(image.pixelRatio, 0.5);
      expect(image.logicalWidth, 400);

      final decoded = await tester.runAsync(() => _decode(image.pngBytes));
      expect(decoded!.width, 200);
      decoded.dispose();
    });

    testWidgets('a wider max_width than the window does not upscale',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-noupscale');
      await pumpScope(tester, controller);

      final image = (await tester.runAsync(
        () => controller.captureWindow(maxWidth: 4000),
      ))!;

      expect(image.width, 400);
      expect(image.pixelRatio, 1.0);
    });

    test('with nothing mounted it says so instead of throwing a null error',
        () async {
      final controller = AppCaptureController(debugLabel: 'test-unmounted');
      expect(controller.isAttached, isFalse);
      expect(controller.windowSize, isNull);
      await expectLater(
        controller.captureWindow(),
        throwsA(isA<ScreenCaptureUnavailableException>()),
      );
    });
  });

  group('offscreen render', () {
    testWidgets('the slot is empty until something asks for a render',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-slot');
      await pumpScope(tester, controller);

      // Exactly one boundary from the scope itself -- the offscreen one is
      // not built until a render is requested, so an idle app pays nothing
      // for this feature.
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(controller.isRendering, isFalse);
    });

    testWidgets('mounts the subtree beside the window, at the asked-for size',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-offscreen');
      await pumpScope(tester, controller);

      const marker = Key('offscreen-probe');
      final pending = controller.captureOffscreen(
        child: Container(key: marker, color: const Color(0xFF00FF00)),
        size: const Size(800, 600),
        maxWidth: 4096,
      );
      // This test is about what gets mounted; the capture itself is left
      // hanging (no frames are driven) and its failure must not surface as
      // an unhandled error after the test ends.
      unawaited(pending.catchError((Object _) => _unreachableImage));

      // One frame to build the offscreen slot.
      await tester.pump();
      expect(find.byKey(marker), findsOneWidget);
      expect(controller.isRendering, isTrue);

      // It is laid out at the size that was asked for, not the window's --
      // which is the whole point: a page previewed at 1920x1080 must not be
      // squeezed into a 400-px-wide test window.
      expect(tester.getSize(find.byKey(marker)), const Size(800, 600));

      // And it is parked outside the window rather than drawn over it.
      expect(tester.getTopLeft(find.byKey(marker)).dx, lessThan(-800));
    });

    testWidgets('captures the offscreen subtree as a PNG at its own size',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-offpng');
      await pumpScope(tester, controller);

      const marker = Key('offscreen-probe');

      // toImage needs the real event loop, and the offscreen render needs
      // frames -- and tester.pump() cannot be called inside runAsync. So the
      // frames are driven by hand from inside it, which is exactly what
      // pump() does, minus the fake-async bookkeeping.
      final image = await tester.runAsync(() async {
        final pending = controller.captureOffscreen(
          child: Container(key: marker, color: const Color(0xFF00FF00)),
          size: const Size(800, 600),
          maxWidth: 4096,
        );
        for (var i = 1; i <= 4; i++) {
          await Future<void>.delayed(Duration.zero);
          WidgetsBinding.instance
              .handleBeginFrame(Duration(milliseconds: 16 * i));
          WidgetsBinding.instance.handleDrawFrame();
        }
        return pending;
      });

      expect(image, isNotNull);
      expect(image!.pngBytes.take(8), _pngMagic);
      expect(image.width, 800);
      expect(image.height, 600);
      expect(image.logicalWidth, 800);
      expect(image.logicalHeight, 600);

      final decoded = await tester.runAsync(() => _decode(image.pngBytes));
      expect(decoded!.width, 800);
      expect(decoded.height, 600);
      decoded.dispose();

      // The slot is cleared again, and the operator's window is untouched --
      // an offscreen render must leave no trace on screen.
      await tester.pump();
      expect(find.byKey(marker), findsNothing);
      expect(controller.isRendering, isFalse);
      expect(controller.windowSize, const Size(400, 300));

      final window = (await tester.runAsync(
        () => controller.captureWindow(maxWidth: 4096),
      ))!;
      expect(window.width, 400);
      expect(window.height, 300);
    });

    testWidgets('a second render is refused while the first is in flight',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-busy');
      await pumpScope(tester, controller);

      unawaited(controller
          .captureOffscreen(
            child: const SizedBox.expand(),
            size: const Size(800, 600),
          )
          .catchError((Object _) => _unreachableImage));
      await tester.pump();

      await expectLater(
        controller.captureOffscreen(
          child: const SizedBox.expand(),
          size: const Size(800, 600),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AppScreenCapturer', () {
    testWidgets('reports the window size the tools default a render to',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-capturer');
      await pumpScope(tester, controller, surface: const Size(1024, 768));

      final capturer = AppScreenCapturer(
        controller: controller,
        pageKeys: () => ['home', 'wet-area'],
        buildPage: (key) => Text(key, textDirection: TextDirection.ltr),
      );

      expect(capturer.windowSize, (width: 1024, height: 768));
      expect(capturer.canRenderPages, isTrue);
      expect(capturer.pageKeys, ['home', 'wet-area']);

      final image = (await tester.runAsync(
        () => capturer.captureWindow(maxWidth: 512),
      ))!;
      expect(image.width, 512);
    });

    testWidgets('capturePage renders whatever the page builder returns',
        (tester) async {
      final controller = AppCaptureController(debugLabel: 'test-page');
      await pumpScope(tester, controller);

      final built = <String>[];
      final capturer = AppScreenCapturer(
        controller: controller,
        pageKeys: () => ['home'],
        buildPage: (key) {
          built.add(key);
          return Container(color: const Color(0xFFFF0000));
        },
      );

      final image = await tester.runAsync(() async {
        final pending = capturer.capturePage(
          pageKey: 'home',
          width: 640,
          height: 480,
          maxWidth: 320,
        );
        for (var i = 1; i <= 4; i++) {
          await Future<void>.delayed(Duration.zero);
          WidgetsBinding.instance
              .handleBeginFrame(Duration(milliseconds: 16 * i));
          WidgetsBinding.instance.handleDrawFrame();
        }
        return pending;
      });

      expect(built, ['home']);
      // Laid out at 640x480, rasterized at half that to honour max_width.
      expect(image!.logicalWidth, 640);
      expect(image.logicalHeight, 480);
      expect(image.width, 320);
      expect(image.height, 240);
    });

    test('without a page builder it never advertises render_page', () {
      final capturer = AppScreenCapturer(
        controller: AppCaptureController(debugLabel: 'test-nopages'),
      );
      expect(capturer.canRenderPages, isFalse);
      expect(capturer.pageKeys, isEmpty);
      expect(capturer.windowSize, isNull);
    });

    test('a page-key source that throws degrades to an empty list', () {
      final capturer = AppScreenCapturer(
        controller: AppCaptureController(debugLabel: 'test-throwing'),
        pageKeys: () => throw StateError('no page manager yet'),
        buildPage: (key) => const SizedBox.shrink(),
      );
      expect(capturer.pageKeys, isEmpty);
      expect(capturer.canRenderPages, isTrue);
    });
  });

  group('an image the engine never drew', () {
    // A profile-mode engine that cannot rasterise a frame does not fail the
    // future: it completes it with a ui.Image whose native image is null,
    // which reports 0 x 0. Passing that to toByteData is an access violation
    // on the IO thread, not a Dart exception -- it killed the HMI on
    // 2026-09-02. The size is the only warning there is, so it is checked
    // before the encode.
    test('is refused by its size, with a message that says why', () {
      expect(
        () => AppCaptureController.checkRasterized(0, 0),
        throwsA(isA<ScreenCaptureRasterizationException>().having(
          (e) => e.message,
          'message',
          allOf(contains('empty image'), contains('could not be rasterised')),
        )),
      );
    });

    test('a half-empty image is refused too', () {
      expect(() => AppCaptureController.checkRasterized(1280, 0),
          throwsA(isA<ScreenCaptureRasterizationException>()));
      expect(() => AppCaptureController.checkRasterized(0, 720),
          throwsA(isA<ScreenCaptureRasterizationException>()));
      expect(() => AppCaptureController.checkRasterized(-1, -1),
          throwsA(isA<ScreenCaptureRasterizationException>()));
    });

    test('an image with pixels in it is let through', () {
      expect(() => AppCaptureController.checkRasterized(1, 1), returnsNormally);
      expect(() => AppCaptureController.checkRasterized(1920, 1080),
          returnsNormally);
    });

    testWidgets('a real capture passes the check it is guarded by',
        (tester) async {
      // Ties the guard to the live path: whatever the engine hands back for
      // an ordinary capture must be something the guard accepts, or every
      // screenshot would start failing closed.
      final controller = AppCaptureController(debugLabel: 'test-guard');
      await pumpScope(tester, controller);

      final captured = await tester.runAsync(
        () => controller.captureWindow(maxWidth: 4096),
      );

      expect(captured!.width, greaterThan(0));
      expect(captured.height, greaterThan(0));
      expect(
        () => AppCaptureController.checkRasterized(
            captured.width, captured.height),
        returnsNormally,
      );
    });
  });

  group('the pixel budget', () {
    test('leaves an ordinary capture alone', () {
      expect(
        AppCaptureController.capToPixelBudget(1.0, const Size(1920, 1080)),
        1.0,
      );
      expect(
        AppCaptureController.capToPixelBudget(0.5, const Size(2560, 1440)),
        0.5,
      );
    });

    test('lowers the ratio rather than let a huge render target be asked for',
        () {
      const logical = Size(8192, 8192);
      final ratio = AppCaptureController.capToPixelBudget(1.0, logical);

      expect(ratio, lessThan(1.0));
      final pixels = (logical.width * ratio) * (logical.height * ratio);
      expect(pixels,
          lessThanOrEqualTo(AppCaptureController.kMaxCapturePixels + 1));
    });

    test('a degenerate size does not divide by zero', () {
      expect(AppCaptureController.capToPixelBudget(1.0, Size.zero), 1.0);
    });
  });
}

/// Never actually used -- it only satisfies `catchError`'s return type on a
/// future the test deliberately abandons.
final CapturedImage _unreachableImage = CapturedImage(
  pngBytes: Uint8List(0),
  width: 0,
  height: 0,
  logicalWidth: 0,
  logicalHeight: 0,
  pixelRatio: 1,
);
