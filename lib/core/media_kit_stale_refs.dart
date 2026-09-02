/// A guard against package:media_kit's NativeReferenceHolder dereferencing a
/// dead pointer on stations.
///
/// The holder persists the ADDRESS of a malloc'd buffer to
/// `$TMP/com.alexmercerind.media_kit.NativeReferenceHolder.$pid` so a
/// hot-restart — same process, allocation still alive — can find and dispose
/// the players the previous run leaked. Across a REAL restart the address is
/// garbage, and the holder dereferences it anyway. On a desktop that never
/// bites: a fresh process gets a fresh pid, so the filename never matches. In
/// a container the entrypoint hands the app the SAME pid every start and /tmp
/// outlives `docker restart`, so every boot reads its predecessor's file and
/// segfaults — a crash-loop the supervisor then feeds forever. hq-skjar,
/// 2026-09-02: 173 restarts, exit 139, one line after
/// `NativeReferenceHolder: Located`.
///
/// The rule: at the FIRST media_kit initialisation in this process, nothing in
/// this process has written that file, so a file bearing OUR pid is a dead
/// predecessor's — delete it, and the holder allocates fresh. Files bearing
/// other pids belong to other live processes (a dev machine mid-hot-restart)
/// and are left alone.
///
/// The cost, stated rather than hidden: on a dev machine a hot-restart re-runs
/// the caller, which purges the file THIS process wrote, so the holder's
/// hot-restart cleanup degrades to a handle leak until full restart. That
/// cleanup is best-effort and debug-only upstream; a leak in development
/// against a segfault loop in production is not a close call.
library;

import 'dart:io';

/// Deletes this process's stale NativeReferenceHolder file, returning the
/// deleted path, or null when there was nothing to delete.
///
/// Call before `MediaKit.ensureInitialized()` / the first `Player()`.
/// Failures degrade to the pre-purge behaviour rather than preventing boot.
String? purgeStaleNativeReferenceFile({Directory? tempDirectory}) {
  final dir = tempDirectory ?? Directory.systemTemp;
  final file = File(
    '${dir.path}/com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
  );
  try {
    if (!file.existsSync()) return null;
    file.deleteSync();
    return file.path;
  } on FileSystemException {
    return null;
  }
}
