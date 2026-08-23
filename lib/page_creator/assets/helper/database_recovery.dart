import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/database.dart';

import '../../../providers/database.dart';

/// Calls [onDatabaseAvailable] whenever [databaseProvider] produces a
/// [Database] that is not the one the caller is already using.
///
/// `databaseProvider` yields `null` rather than throwing while Postgres is
/// unreachable, and retries itself in the background until it connects. An
/// asset that grabs it once with `ref.read` in `initState` takes that null,
/// bails, and stays blank for the rest of the session — nothing ever rebuilds
/// it. On a plant-wide power cut Flutter is drawing in a couple of seconds
/// while Postgres is still replaying WAL, so that is the normal outcome, not
/// an edge case.
///
/// Call this from `initState` (or from the async init it kicks off). It is
/// deliberately **not** `ref.watch`: `ConsumerStatefulElement.build` moves
/// `_dependencies` aside, lets the build re-register whatever it watches, and
/// then closes everything left over — so a watch registered in `initState` is
/// silently closed at the end of the first build and never fires again.
/// `listenManual` is the subscription that survives rebuilds and is closed for
/// us when the element unmounts.
///
/// [currentDatabase] is read at notification time, so a re-emission of the
/// instance the caller already holds costs nothing. A genuinely new instance —
/// a reconnect, or the operator applying new database settings, which
/// invalidates the provider — re-runs [onDatabaseAvailable].
ProviderSubscription<AsyncValue<Database?>> reinitOnDatabaseAvailable(
  WidgetRef ref, {
  required Database? Function() currentDatabase,
  required void Function(Database database) onDatabaseAvailable,
}) {
  return ref.listenManual<AsyncValue<Database?>>(
    databaseProvider,
    (previous, next) {
      final database = next.valueOrNull;
      if (database == null) return;
      if (identical(database, currentDatabase())) return;
      onDatabaseAvailable(database);
    },
  );
}
