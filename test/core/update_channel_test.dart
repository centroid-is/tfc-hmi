import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/core/update_channel.dart';

void main() {
  late SharedPreferencesAsync prefs;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
  });

  test('defaults to stable when nothing is stored', () async {
    expect(await readUpdateChannel(prefs: prefs), updateChannelStable);
  });

  test('round-trips the latest channel', () async {
    await writeUpdateChannel(updateChannelLatest, prefs: prefs);
    expect(await readUpdateChannel(prefs: prefs), updateChannelLatest);

    await writeUpdateChannel(updateChannelStable, prefs: prefs);
    expect(await readUpdateChannel(prefs: prefs), updateChannelStable);
  });

  test('unknown stored value reads as stable', () async {
    await prefs.setString(updateChannelPrefsKey, 'nightly');
    expect(await readUpdateChannel(prefs: prefs), updateChannelStable);
  });

  test('unknown value is normalised to stable on write', () async {
    await writeUpdateChannel('nightly', prefs: prefs);
    expect(await prefs.getString(updateChannelPrefsKey), updateChannelStable);
  });
}
