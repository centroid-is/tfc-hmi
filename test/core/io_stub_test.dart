import 'package:flutter_test/flutter_test.dart';

// Import the stub directly to test its behavior in isolation.
// In the real app, this file is only loaded on web via conditional import.
import 'package:tfc/core/io_stub.dart';

void main() {
  group('io_stub Platform', () {
    test('isLinux returns false', () {
      expect(Platform.isLinux, isFalse);
    });

    test('isWindows returns false', () {
      expect(Platform.isWindows, isFalse);
    });

    test('isMacOS returns false', () {
      expect(Platform.isMacOS, isFalse);
    });

    test('isAndroid returns false', () {
      expect(Platform.isAndroid, isFalse);
    });

    test('isIOS returns false', () {
      expect(Platform.isIOS, isFalse);
    });

    test('environment returns empty map', () {
      expect(Platform.environment, isEmpty);
    });

    test('localeName returns empty string', () {
      expect(Platform.localeName, '');
    });
  });

  group('io_stub File', () {
    test('constructor throws UnsupportedError', () {
      // On native, dart:io's File shadows the stub, so this only works on web.
    }, skip: 'io_stub File only active on web; dart:io shadows it on native');
  });
}
