/// package:media_kit's NativeReferenceHolder persists the ADDRESS of a
/// malloc'd buffer to `$TMP/com.alexmercerind.media_kit.NativeReferenceHolder.$pid`
/// and, when that file exists at startup, dereferences the stored address.
/// That is built for hot-restart, where the process — and the allocation —
/// survive. In a container the process gets the SAME pid every start and /tmp
/// outlives `docker restart`, so a fresh process reads its predecessor's file
/// and dereferences a dead address: segfault, restart, same pid, same file,
/// crash-loop. 173 restarts on hq-skjar, 2026-09-02.
///
/// Written RED first, against a purge that did not exist.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/media_kit_stale_refs.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('stale-refs-test'));
  tearDown(() => temp.deleteSync(recursive: true));

  File holderFile(int forPid) => File(
      '${temp.path}/com.alexmercerind.media_kit.NativeReferenceHolder.$forPid');

  test('deletes the file bearing OUR pid — the pid-reuse corpse', () {
    holderFile(pid).writeAsStringSync('140269479105360');

    final purged = purgeStaleNativeReferenceFile(tempDirectory: temp);

    expect(purged, isNotNull);
    expect(holderFile(pid).existsSync(), isFalse,
        reason: "at first media_kit init nothing in THIS process has written "
            "it, so a file with our pid is a dead predecessor's");
  });

  test("leaves other pids' files alone", () {
    // Another live app on the same host may be mid-hot-restart; its cleanup
    // is not ours to break.
    holderFile(pid + 1).writeAsStringSync('1');

    final purged = purgeStaleNativeReferenceFile(tempDirectory: temp);

    expect(purged, isNull);
    expect(holderFile(pid + 1).existsSync(), isTrue);
  });

  test('nothing to purge is not an error', () {
    expect(purgeStaleNativeReferenceFile(tempDirectory: temp), isNull);
  });

  test('an undeletable file reports rather than throws', () {
    // The purge runs on the app's startup path; a permissions oddity must
    // degrade to the pre-purge behaviour, not prevent boot.
    final dir = Directory('${temp.path}/gone')..createSync();
    final f = File(
        '${dir.path}/com.alexmercerind.media_kit.NativeReferenceHolder.$pid')
      ..writeAsStringSync('1');
    expect(f.existsSync(), isTrue);
    dir.deleteSync(recursive: true);

    expect(() => purgeStaleNativeReferenceFile(tempDirectory: dir),
        returnsNormally);
  });
}
