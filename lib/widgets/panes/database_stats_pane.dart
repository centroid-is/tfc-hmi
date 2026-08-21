/// What the database's connection slots are being spent on.
///
/// On 2026-08-21 the Postgres server ran out of connections and refused every
/// write. There was no way to see who was holding them: the slots reserved for
/// the superuser had gone the same way, so psql could not get in to ask. This
/// pane asks from inside the application, which is holding a connection of its
/// own and can therefore still get an answer while the server has none left to
/// give.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/database_connections.dart';

import '../../providers/database.dart';
import 'pane_chrome.dart';
import 'side_pane.dart';

/// Pane id, so a second tap on the info button closes it again.
const String kDatabaseStatsPaneId = 'database:connections';

/// How often the pane re-counts while it is open.
///
/// Slow on purpose: the count itself takes a connection, and this pane exists
/// for a fault where connections are the thing in short supply.
const Duration kCensusRefreshInterval = Duration(seconds: 10);

/// Opens (or toggles shut) the connection census pane.
bool showDatabaseStatsPane(BuildContext context) => showSidePane(
      context: context,
      id: kDatabaseStatsPaneId,
      builder: (_) => const DatabaseStatsPane(),
    );

/// How the census reads as equipment state.
PaneStatus censusPaneStatus(ConnectionCensus census) => censusIsAlarming(census)
    ? const PaneStatus.warning('Nearly full')
    : const PaneStatus.running('Healthy');

/// The pane: fetches the census on a timer for as long as it is open.
class DatabaseStatsPane extends ConsumerStatefulWidget {
  const DatabaseStatsPane({super.key});

  @override
  ConsumerState<DatabaseStatsPane> createState() => _DatabaseStatsPaneState();
}

class _DatabaseStatsPaneState extends ConsumerState<DatabaseStatsPane> {
  Timer? _timer;
  ConnectionCensus? _census;
  Object? _error;
  bool _postgres = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(kCensusRefreshInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final db = await ref.read(databaseProvider.future);
      if (db == null || db.db.config.postgres == null) {
        if (!mounted) return;
        setState(() {
          _postgres = false;
          _loading = false;
        });
        return;
      }
      final rows = await db.db.customSelect(connectionCensusSql).get();
      final census = parseConnectionCensus(rows.map((r) => r.data));
      if (!mounted) return;
      setState(() {
        _census = census;
        _error = null;
        _postgres = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final census = _census;
    return SidePane(
      title: 'DB connections',
      subtitle: 'Refreshed every ${kCensusRefreshInterval.inSeconds} s',
      icon: Icons.storage,
      status: census == null ? const PaneStatus.unknown() : censusPaneStatus(census),
      child: !_postgres
          ? const PaneSection(
              child: Text('This database is local storage, not a Postgres '
                  'server, so there are no connections to count.'),
            )
          : census != null
              ? DatabaseCensusView(census: census, staleError: _error)
              : _loading
                  ? const PaneSection(
                      child: Center(child: CircularProgressIndicator()))
                  : PaneSection(child: _CensusError(error: _error)),
    );
  }
}

/// The census itself, given numbers.
///
/// Split out from the fetching so it can be rendered from fabricated data: the
/// goldens must not carry the plant's real addresses into a public repository.
class DatabaseCensusView extends StatelessWidget {
  final ConnectionCensus census;

  /// A refresh that failed after a census had already been shown. The old
  /// numbers stay up — stale counts beat an empty pane when the reason the
  /// refresh failed is very likely the thing being counted.
  final Object? staleError;

  const DatabaseCensusView({super.key, required this.census, this.staleError});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alarming = censusIsAlarming(census);
    final peers = census.peersByShare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneSection(
          child: PaneTileRow(
            children: [
              PaneMetricTile(
                label: 'In use',
                value: '${census.total}',
                valueColor: alarming ? theme.colorScheme.error : null,
              ),
              PaneMetricTile(label: 'Limit', value: '${census.max}'),
              PaneMetricTile(
                label: 'Used',
                value: '${census.percentUsed}',
                unit: '%',
                valueColor: alarming ? theme.colorScheme.error : null,
              ),
            ],
          ),
        ),
        PaneSection(
          title: 'Connections by client',
          child: peers.isEmpty
              ? Text('The server reported no clients.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in peers)
                      PaneDetailRow(
                        label: p.app == '-' || p.app.isEmpty
                            ? p.peer
                            : '${p.peer} · ${p.app}',
                        value: '${p.count}',
                      ),
                  ],
                ),
        ),
        PaneSection(
          child: Text(
            // Kept in step with `resolvePoolSize`, whose default pool is one
            // connection: that is the "1 per client" figure below.
            'Expect one connection for each HMI client, and fewer than ten for '
            'the collector — roughly one per OPC UA server, with the weighers '
            'sharing one between them. Much more than that means a client is '
            'pooling connections it does not need, or is not handing them back. '
            'On 21 August 2026 two clients held 13 and 12, and the collector '
            'held 75, which filled a 100-connection server.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        if (staleError != null)
          PaneSection(
            child: Text(
              'Last refresh failed, showing the previous count: $staleError',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _CensusError extends StatelessWidget {
  final Object? error;

  const _CensusError({this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Could not count connections.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 6),
        Text('$error',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
