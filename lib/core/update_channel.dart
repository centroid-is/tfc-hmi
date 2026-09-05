import 'package:tfc_dart/core/preferences.dart';

// A `core` file importing a provider file is unusual here, and deliberate:
// the factory is the single point spec §6's invariant is stated at, and
// importing it is what keeps these two functions inside the rule. Nothing
// riverpod is used — only the factory.
import '../providers/preferences.dart' show createDeviceLocalPreferences;

/// The release channel the app checks for updates on.
///
/// `stable` follows tagged releases; `latest` follows the rolling
/// `main-latest` prerelease republished on every merge to main. The string
/// values match the centroidx-manager `-channel` flag and the
/// `GitHubReleaseStore` channel names in package:centroidx_upgrader.
const String updateChannelStable = 'stable';
const String updateChannelLatest = 'latest';

/// SharedPreferences key holding the chosen channel. Local to the machine on
/// purpose — a dev box on the latest channel must not drag every HMI with it.
const String updateChannelPrefsKey = 'update_channel';

/// The git commit CI built this binary from (`--dart-define=GIT_SHA=...`).
/// Empty for local builds; used by the latest channel to tell whether the
/// current main build differs from the one running.
const String buildGitSha = String.fromEnvironment('GIT_SHA');

/// Reads the persisted update channel; anything unknown counts as stable.
Future<String> readUpdateChannel({PreferencesApi? prefs}) async {
  final p = prefs ?? createDeviceLocalPreferences();
  final stored = await p.getString(updateChannelPrefsKey);
  return stored == updateChannelLatest
      ? updateChannelLatest
      : updateChannelStable;
}

/// Persists the update channel; anything unknown is stored as stable.
Future<void> writeUpdateChannel(
  String channel, {
  PreferencesApi? prefs,
}) async {
  final p = prefs ?? createDeviceLocalPreferences();
  await p.setString(
    updateChannelPrefsKey,
    channel == updateChannelLatest ? updateChannelLatest : updateChannelStable,
  );
}
