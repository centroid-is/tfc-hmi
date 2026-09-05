import 'dart:io';

import 'package:test/test.dart';

/// The one-way dependency rule is not expressible in the type system: nothing
/// objects when somebody adds `import 'package:flutter/material.dart';` to a
/// file in `lib/`, or drops `tfc_dart` into the pubspec because it happened to
/// have the constant they wanted. This suite is the only thing standing between
/// that edit and the open62541 FFI landing in the relay server's dependency
/// graph, so it asserts on file text rather than on types.

/// Strings that must not appear in `pubspec.yaml` outside a comment.
const _forbiddenInPubspec = <String>[
  'tfc_dart',
  'flutter',
  'open62541',
  'cryptography_flutter',
];

/// Imports that must not appear anywhere under `lib/`.
const _forbiddenImports = <String>[
  'package:flutter',
  'dart:ui',
];

/// Walk up from the current directory until the `tfc_access` pubspec is found.
///
/// `dart test` runs with the package root as its working directory, but a test
/// invoked from the repo root or from an IDE may not, and a purity test that
/// silently passes because it could not find the file it was meant to read is
/// worse than no test at all.
Directory _packageRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: tfc_access')) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('could not locate the tfc_access package root from '
          '${Directory.current.path}');
    }
    dir = parent;
  }
}

/// `pubspec.yaml` with comment lines removed, so the comment that *explains*
/// the rule cannot satisfy or break the assertion that enforces it.
String _pubspecWithoutComments(Directory root) {
  final lines = File('${root.path}/pubspec.yaml').readAsLinesSync();
  return lines
      .where((line) => !RegExp(r'^\s*#').hasMatch(line))
      .join('\n')
      .toLowerCase();
}

void main() {
  final root = _packageRoot();

  group('pubspec purity', () {
    test('the pubspec was actually found and read', () {
      // Guards the guard: every assertion below is vacuously true against an
      // empty string.
      final body = _pubspecWithoutComments(root);
      expect(body, contains('name: tfc_access'));
      expect(body, contains('dependencies:'));
    });

    for (final forbidden in _forbiddenInPubspec) {
      test('pubspec.yaml does not mention $forbidden outside a comment', () {
        expect(
          _pubspecWithoutComments(root),
          isNot(contains(forbidden)),
          reason: 'tfc_access is pure Dart. Depending on $forbidden pulls the '
              'open62541 FFI and native assets into every consumer, including '
              'the relay server and a later web client. The dependency runs '
              'one way only: tfc_dart -> tfc_access, never the reverse.',
        );
      });
    }

    test('comment lines are stripped before matching', () {
      // The explanatory comment block in pubspec.yaml names every forbidden
      // string. If stripping ever broke, the assertions above would fail —
      // this test states the dependency between the two out loud.
      final raw = File('${root.path}/pubspec.yaml').readAsStringSync();
      expect(raw, contains('tfc_dart'),
          reason: 'the pubspec comment should still explain the rule');
      expect(_pubspecWithoutComments(root), isNot(contains('tfc_dart')));
    });
  });

  group('lib/ purity', () {
    final libFiles = Directory('${root.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('there is something under lib/ to check', () {
      expect(libFiles, isNotEmpty);
    });

    for (final forbidden in _forbiddenImports) {
      test('nothing under lib/ imports $forbidden', () {
        final offenders = <String>[];
        for (final file in libFiles) {
          if (file.readAsStringSync().contains(forbidden)) {
            offenders.add(file.path.substring(root.path.length + 1));
          }
        }
        expect(
          offenders,
          isEmpty,
          reason: 'tfc_access must not reach Flutter. Move whatever needs '
              '$forbidden into the consumer that already depends on Flutter.',
        );
      });
    }
  });
}
