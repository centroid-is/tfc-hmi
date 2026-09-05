/// This station's transport choice, read from the device-local store.
///
/// A separate file from `preferences.dart` on purpose: that file owns the two
/// stores themselves, and a setting that reads one of them belongs beside the
/// other settings rather than inside the plumbing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/gateway_config.dart';
import 'preferences.dart';

/// Where this panel gets its values from.
///
/// Reads [localPreferencesProvider] and never the shared, DB-backed store: a
/// gateway URL is per-station, exactly as the Postgres address is, and a
/// synced row would re-point one station from another. See
/// `lib/core/gateway_config.dart`.
///
/// Watched by `stateManProvider`, which is `keepAlive`, so invalidating this
/// after a save does **not** by itself swap the transport — restart-to-apply
/// is the deliberate behaviour. Tearing an OPC UA session and a Postgres pool
/// down under widgets that hold live subscriptions is not something a settings
/// toggle should attempt.
final gatewayConfigProvider = FutureProvider<GatewayConfig>(
  (ref) async => readGatewayConfig(ref.watch(localPreferencesProvider)),
);
