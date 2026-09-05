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

/// Sections whose contents `GetSettings` blanks out, and which therefore have
/// to be fetched separately before any read-modify-write of a profile.
///
/// NetworkManager's `Update` replaces the profile wholesale, and `GetSettings`
/// never returns secrets — so `update(await getSettings())`, the obvious
/// shape, silently wipes the wifi PSK or the 802.1X keys. Renaming a wifi
/// profile would knock the station off the network.
const secretBearingSettings = {
  '802-11-wireless-security',
  '802-1x',
  'vpn',
  'pppoe',
  'gsm',
  'cdma',
  'wireguard',
};

/// Re-attaches the secrets `GetSettings` stripped, so [settings] is safe to
/// hand to `Update`.
///
/// Best-effort by design: `GetSecrets` is separately authorised, and a
/// profile whose secrets we may not read is still one whose name we may
/// change. Failing the rename because the PSK was unreadable would be worse
/// than leaving that section as NetworkManager already has it.
Future<Map<String, Map<String, DBusValue>>> withSecrets(
  NetworkManagerSettingsConnection connection,
  Map<String, Map<String, DBusValue>> settings,
) async {
  final merged = {
    for (final entry in settings.entries)
      entry.key: Map<String, DBusValue>.from(entry.value),
  };
  for (final name in settings.keys.toList()) {
    if (!secretBearingSettings.contains(name)) continue;
    try {
      final secrets = await connection.getSecrets(name);
      final section = secrets[name];
      if (section != null) merged[name]?.addAll(section);
    } catch (_) {
      // Not readable — leave the section as GetSettings returned it.
    }
  }
  return merged;
}

/// Why [name] is not usable as a connection id, or null when it is.
///
/// NetworkManager itself permits duplicates and almost any string; the
/// stricter rule here is for the operator's benefit, since the id is the only
/// thing distinguishing two profiles in a list.
String? validateConnectionName(
  String name, {
  String currentId = '',
  Iterable<String> existingIds = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Name cannot be empty';
  if (trimmed.length > 63) return 'Name is too long';
  if (trimmed == currentId) return null;
  if (existingIds.contains(trimmed)) {
    return 'Another connection is already called "$trimmed"';
  }
  return null;
}

/// Renames a saved profile, changing **only** its `connection.id`.
///
/// The id is the profile's label. `interface-name` — the kernel device it
/// binds to — is deliberately untouched: renaming bond0's profile to
/// something an operator recognises must not detach it from the bond0
/// interface, which is what makes this a distinct operation from editing the
/// connection.
Future<void> renameConnection(
  NetworkManagerSettingsConnection connection,
  String newId,
) async {
  final trimmed = newId.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(newId, 'newId', 'Name cannot be empty');
  }
  final settings = await withSecrets(connection, await connection.getSettings());
  final section = Map<String, DBusValue>.from(settings['connection'] ?? {});
  section['id'] = DBusString(trimmed);
  settings['connection'] = section;
  await connection.update(settings);
}

/// The profiles that deleting [connection] should take with it.
///
/// A bond master is not deletable on its own in any useful sense: its members
/// carry `master: <bond>` and would be left enslaved to a bond that no longer
/// exists, so NetworkManager leaves the ports down. The returned list always
/// starts with [connection] itself.
Future<List<NetworkManagerSettingsConnection>> connectionsRemovedWith(
  NetworkManagerClient client,
  NetworkManagerSettingsConnection connection,
) async {
  final removed = <NetworkManagerSettingsConnection>[connection];

  Map<String, Map<String, DBusValue>> settings;
  try {
    settings = await connection.getSettings();
  } catch (_) {
    return removed;
  }
  if (connectionField(settings, 'type') != 'bond') return removed;

  // Members name their master by interface, or by the master's uuid.
  final interfaceName = connectionField(settings, 'interface-name');
  final uuid = connectionField(settings, 'uuid');

  for (final other in client.settings.connections) {
    if (identical(other, connection)) continue;
    try {
      final otherSettings = await other.getSettings();
      final master = connectionField(otherSettings, 'master');
      if (master.isEmpty) continue;
      if (master == interfaceName || (uuid.isNotEmpty && master == uuid)) {
        removed.add(other);
      }
    } catch (_) {
      // Deleted mid-walk.
    }
  }
  return removed;
}

/// Deletes [connections], continuing past individual failures.
///
/// Returns the profiles that could not be removed, so the caller can say
/// which ones are still there rather than claiming a clean sweep.
Future<List<NetworkManagerSettingsConnection>> deleteConnections(
  Iterable<NetworkManagerSettingsConnection> connections,
) async {
  final failed = <NetworkManagerSettingsConnection>[];
  for (final connection in connections) {
    try {
      await connection.delete();
    } catch (_) {
      failed.add(connection);
    }
  }
  return failed;
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
