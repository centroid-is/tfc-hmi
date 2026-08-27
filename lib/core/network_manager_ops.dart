import 'package:dbus/dbus.dart';
import 'package:nm/nm.dart';

import 'network_settings.dart';

/// NetworkManager calls that survive a race in `nm` 0.5.0, plus the saved
/// profile lookups the IP settings page needs.
///
/// `NetworkManagerSettings.addConnection` and
/// `NetworkManagerClient.activateConnection` resolve the object path
/// NetworkManager hands back against the client's ObjectManager cache and then
/// force-unwrap it:
///
/// ```dart
/// return _client._getConnection(result.returnValues[0] as DBusObjectPath)!;
/// ```
///
/// The cache is filled asynchronously from `InterfacesAdded`, so when the
/// method reply arrives before that signal has been processed the lookup
/// misses and `!` throws `Null check operator used on a null value` — *after*
/// NetworkManager has already committed the change. Creating a bond hit this
/// repeatedly: the journal recorded `op="connection-add" result="success"` for
/// both the master and the member, yet the dialog reported a failure and the
/// member was never activated.
///
/// The helpers below therefore treat a client-side [TypeError] as "the call
/// went through, we only lost the wrapper", and recover the object by UUID
/// where the caller actually needs it.

/// Polls the saved connections for the profile carrying [uuid].
///
/// The profile may not be in the client's cache yet, hence the retries.
/// Returns null when it never shows up.
Future<NetworkManagerSettingsConnection?> findConnectionByUuid(
  NetworkManagerClient client,
  String uuid, {
  int attempts = 10,
  Duration retryDelay = const Duration(milliseconds: 100),
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    for (final connection in client.settings.connections) {
      try {
        final settings = await connection.getSettings();
        if (connectionField(settings, 'uuid') == uuid) return connection;
      } catch (_) {
        // A profile deleted while we were walking the list.
      }
    }
    if (attempt < attempts - 1) await Future<void>.delayed(retryDelay);
  }
  return null;
}

/// The saved profile bound to [interfaceName], if any.
///
/// This is what makes an inactive port editable instead of silently getting a
/// second, duplicate profile every time it is saved.
Future<NetworkManagerSettingsConnection?> findConnectionForInterface(
  NetworkManagerClient client,
  String interfaceName,
) async {
  for (final connection in client.settings.connections) {
    try {
      final settings = await connection.getSettings();
      if (connectionField(settings, 'interface-name') == interfaceName) {
        return connection;
      }
    } catch (_) {
      // A profile deleted while we were walking the list.
    }
  }
  return null;
}

/// Adds a connection, recovering it by UUID when `nm` loses the race above.
///
/// Rethrows when the profile genuinely is not there afterwards, so a real
/// NetworkManager rejection (bad settings, not authorized) still surfaces.
Future<NetworkManagerSettingsConnection> addConnectionResilient(
  NetworkManagerClient client,
  Map<String, Map<String, DBusValue>> settings, {
  int attempts = 10,
  Duration retryDelay = const Duration(milliseconds: 100),
}) async {
  try {
    return await client.settings.addConnection(settings);
  } on TypeError {
    final uuid = connectionField(settings, 'uuid');
    if (uuid.isEmpty) rethrow;
    final connection = await findConnectionByUuid(client, uuid,
        attempts: attempts, retryDelay: retryDelay);
    if (connection == null) rethrow;
    return connection;
  }
}

/// Activates [connection] on [device], tolerating the same race.
///
/// The returned `ActiveConnection` wrapper is discarded by every caller here,
/// so losing it to the cache miss is not a failure worth reporting.
Future<void> activateConnectionResilient(
  NetworkManagerClient client, {
  required NetworkManagerDevice device,
  NetworkManagerSettingsConnection? connection,
}) async {
  try {
    await client.activateConnection(device: device, connection: connection);
  } on TypeError {
    // NetworkManager accepted the activation; only the wrapper was lost.
  }
}

/// A saved profile resolved into the fields the page renders, so the widget
/// tree stays synchronous over an API that is async all the way down.
class SavedConnection {
  final NetworkManagerSettingsConnection connection;
  final String id;
  final String uuid;
  final String type;
  final String interfaceName;
  final Ipv4Prefill ipv4;

  const SavedConnection({
    required this.connection,
    required this.id,
    required this.uuid,
    required this.type,
    required this.interfaceName,
    required this.ipv4,
  });

  /// `ethernet`, `wifi`, `bond` — the type without D-Bus's spelling.
  String get typeLabel {
    switch (type) {
      case '802-3-ethernet':
        return 'ethernet';
      case '802-11-wireless':
        return 'wifi';
      default:
        return type;
    }
  }
}

/// Every saved profile of an [editableConnectionTypes] type, sorted by name.
///
/// Profiles that cannot be read (deleted mid-walk, or unreadable without
/// authorization) are skipped rather than failing the whole list.
Future<List<SavedConnection>> loadSavedConnections(
    NetworkManagerClient client) async {
  final saved = <SavedConnection>[];
  for (final connection in client.settings.connections) {
    try {
      final settings = await connection.getSettings();
      final type = connectionField(settings, 'type');
      if (!editableConnectionTypes.contains(type)) continue;
      saved.add(SavedConnection(
        connection: connection,
        id: connectionField(settings, 'id'),
        uuid: connectionField(settings, 'uuid'),
        type: type,
        interfaceName: connectionField(settings, 'interface-name'),
        ipv4: ipv4PrefillFromSettings(settings),
      ));
    } catch (_) {
      // Unreadable profile — nothing useful to show for it.
    }
  }
  saved.sort((a, b) => a.id.compareTo(b.id));
  return saved;
}
