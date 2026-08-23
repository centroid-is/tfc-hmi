/// Starting an update, and saying so when it does not start.
///
/// The update itself is done by forking the bundled centroidx-manager, which
/// waits for this process to exit, installs, and relaunches. So the happy
/// path never returns: the app has to be gone before the manager can replace
/// the install.
///
/// That shape left a failure with nowhere to go. `main()` calls this inside
/// `unawaited(...)`, and the closure had no catch, so anything thrown went to
/// the zone error handler and its only trace was a line on stderr — which, on
/// a station started by `run-hmi.ps1`, is redirected into a log file nobody is
/// reading. The operator pressed Update and the app sat there.
///
/// Of the three things that can happen, that is the worst. A successful update
/// is obvious, because the app exits. A crash is obvious. "Nothing happened"
/// reads as a misclick, so it gets pressed again.
library;

import 'update_channel.dart' show updateChannelLatest;

/// Forks the manager for [version] on [channel].
typedef ManagerLaunch = Future<void> Function(String? version, String channel);

/// What the operator is told when the manager will not start.
///
/// Deliberately free of exception text: a `FileSystemException` in a snackbar
/// is noise to someone standing at a machine, and the detail is already in the
/// log where a technician can find it. What it does carry is the next move,
/// because "Update failed" tells the reader only what they can already see.
const String updateLaunchFailureMessage =
    'Could not start the update. The app is still running normally — '
    'try Update again, and restart CentroidX if it keeps failing.';

/// Starts the update and hands the machine over to the manager.
///
/// On success [onHandedOff] runs and does not return: in production it is
/// `exit(0)`, which is what lets the manager replace a binary that would
/// otherwise be locked.
///
/// On failure it logs the detail AND shows [updateLaunchFailureMessage],
/// then returns without handing off. Both, never one: the log is the only
/// place the cause survives, and the snackbar is the only place the operator
/// looks.
Future<void> startManagerUpdate({
  required String targetVersion,
  required Future<String> Function() readChannel,
  required ManagerLaunch launch,
  required void Function(String) log,
  required void Function(String) show,
  required void Function() onHandedOff,
}) async {
  try {
    final channel = await readChannel();
    await launch(
      // On the latest channel the announced version is a date stand-in that
      // matches no tag — let the manager resolve the channel head itself.
      channel == updateChannelLatest ? null : targetVersion,
      channel,
    );
  } catch (e, stack) {
    log('[update] could not start the manager: $e\n$stack');
    show(updateLaunchFailureMessage);
    return;
  }
  onHandedOff();
}
