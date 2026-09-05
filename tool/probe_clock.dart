/// Reads the clock + time-sync status off a real station over SSH, so the
/// D-Bus parsing can be checked against live systemd rather than fixtures.
///
///   dart run tool/probe_clock.dart 10.50.10.11 centroid ~/.ssh/id_ed25519
import 'package:tfc/core/system_clock.dart';
import 'package:tfc/dbus/remote.dart';

Future<void> main(List<String> args) async {
  final client = await connectRemoteSystemBus(
    remoteHost: args[0],
    sshUser: args[1],
    sshPrivateKeyPath: args[2],
  );

  final clock = await DBusTimeDate(client).readStatus();
  print('--- timedate1 ---');
  print('time            ${clock.time}');
  print('rtc             ${clock.rtcTime}  drift=${clock.rtcDrift}');
  print('timezone        ${clock.timezone}');
  print('localRtc        ${clock.localRtc}');
  print('ntpEnabled      ${clock.ntpEnabled}');
  print('ntpSynchronized ${clock.ntpSynchronized}');
  print('canNtp          ${clock.canNtp}');
  print('health          ${timeSyncHealth(clock)}');

  final sync = await DBusTimeSync(client).readStatus();
  print('--- timesync1 ---');
  if (sync == null) {
    print('(timesyncd not reachable)');
  } else {
    print('serverName      ${sync.serverName}');
    print('serverAddress   ${sync.serverAddress}');
    print('link/system/runtime/fallback  ${sync.linkServers} '
        '${sync.systemServers} ${sync.runtimeServers} ${sync.fallbackServers}');
    print('effective       ${sync.effectiveServers}');
    print('fallbackOnly    ${sync.usingFallbackOnly}');
    print('pollInterval    ${formatSyncDuration(sync.pollInterval)}');
    final m = sync.lastMessage;
    if (m == null) {
      print('lastMessage     (none yet)');
    } else {
      print('stratum         ${m.stratum}');
      print('reference       ${m.referenceId}');
      print('offset          ${formatSyncDuration(m.offset)}');
      print('roundTrip       ${formatSyncDuration(m.roundTrip)}');
      print('jitter          ${formatSyncDuration(m.jitter)}');
      print('rootDelay       ${formatSyncDuration(m.rootDelay)}');
      print('packets         ${m.packetCount}');
      print('ignored         ${m.ignored}');
    }
  }
  await client.close();
}
