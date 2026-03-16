import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads a real font so golden tests render readable text instead of Ahem blocks.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fontFile = File('lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
  final fontData = fontFile.readAsBytesSync();
  final byteData = ByteData.view(fontData.buffer);

  // Register as 'Roboto' — Material's default font family.
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(byteData));
  await loader.load();

  await testMain();
}
