import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dbus/dbus.dart';
import 'package:nm/nm.dart' as nm;

import '../widgets/base_scaffold.dart';

import '../dbus/generated/hostname1.dart';

class AboutLinuxPage extends StatefulWidget {
  final DBusClient dbusClient;
  const AboutLinuxPage({super.key, required this.dbusClient});

  @override
  State<AboutLinuxPage> createState() => _AboutLinuxPageState();
}

class _AboutLinuxPageState extends State<AboutLinuxPage> {
  late final OrgFreedesktopDBusPeer _hostnamed;
  StreamSubscription<OrgFreedesktopDBusPeerPropertiesChanged>? _sub;
  Future<_HostInfo>? _infoFuture;

  @override
  void initState() {
    super.initState();
    _hostnamed = OrgFreedesktopDBusPeer(
      widget.dbusClient,
      'org.freedesktop.hostname1',
      DBusObjectPath('/org/freedesktop/hostname1'),
    );

    // initial load
    _infoFuture = _load();

    // react to live property changes (hostname, kernel, etc.)
    _sub = _hostnamed.customPropertiesChanged.listen((_) {
      setState(() {
        _infoFuture = _load();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<_HostInfo> _load() async {
    // 1) Pull everything in a single roundtrip
    Map<String, DBusValue> props = {};
    try {
      props = await _hostnamed.callGetAll('org.freedesktop.hostname1');
    } catch (_) {
      // Fallbacks below still rely on specific getters, but keep it quiet on systems that restrict GetAll.
    }

    // Helpers to read typed values (works for both direct & DBusVariant)
    String? _str(String key) {
      final v = props[key];
      if (v is DBusString) return v.value;
      if (v is DBusVariant && v.value is DBusString) {
        return (v.value as DBusString).value;
      }
      return null;
    }

    int? _u64(String key) {
      final v = props[key];
      if (v is DBusUint64) return v.value;
      if (v is DBusVariant && v.value is DBusUint64) {
        return (v.value as DBusUint64).value;
      }
      return null;
    }

    // 2) Best-effort Describe() — your generator says it returns a string
    String? describe;
    try {
      final d = await _hostnamed.callDescribe();
      if (d.trim().isNotEmpty) describe = d.trim();
    } catch (_) {}

    // 3) Optionally discover a "main" IPv4 via NetworkManager (quietly skip if absent)
    List<String> activeIPs = [];
    try {
      final client = nm.NetworkManagerClient(bus: widget.dbusClient);
      await client.connect();
      for (final dev in client.devices) {
        final active = dev.activeConnection;
        final ok = active != null &&
            active.state == nm.NetworkManagerActiveConnectionState.activated;
        if (!ok) continue;
        final cfg = dev.ip4Config;
        if (cfg != null && cfg.addressData.isNotEmpty) {
          final first = cfg.addressData.first;
          final addr = first['address']?.toString();
          if (addr != null && addr.isNotEmpty) {
            if (addr == '127.0.0.1' || addr.startsWith('127.')) {
              continue;
            }
            activeIPs.add(addr);
            break;
          }
        }
      }
      await client.close();
    } catch (_) {
      // ignore
    }

    // 4) Prefer PrettyHostname → Hostname → StaticHostname, use getters as fallback if GetAll wasn’t allowed.
    String hostname = _str('PrettyHostname') ??
        _str('Hostname') ??
        _str('StaticHostname') ??
        '';

    if (hostname.isEmpty) {
      try {
        final pretty = await _hostnamed.getPrettyHostname();
        if (pretty.isNotEmpty) hostname = pretty;
      } catch (_) {}
    }
    if (hostname.isEmpty) {
      try {
        final runtime = await _hostnamed.getHostname();
        if (runtime.isNotEmpty) hostname = runtime;
      } catch (_) {}
    }
    if (hostname.isEmpty) {
      try {
        final stat = await _hostnamed.getStaticHostname();
        if (stat.isNotEmpty) hostname = stat;
      } catch (_) {}
    }

    // Kernel & OS strings, with per-property fallbacks
    Future<String?> _fallbackStr(
      String current,
      Future<String> Function() getter,
    ) async {
      if (current.isNotEmpty) return current;
      try {
        final v = await getter();
        return v.isNotEmpty ? v : null;
      } catch (_) {
        return null;
      }
    }

    final kernelName = await _fallbackStr(
            _str('KernelName') ?? '', _hostnamed.getKernelName) ??
        '';
    final kernelRelease = await _fallbackStr(
            _str('KernelRelease') ?? '', _hostnamed.getKernelRelease) ??
        '';
    final kernelVersion = await _fallbackStr(
            _str('KernelVersion') ?? '', _hostnamed.getKernelVersion) ??
        '';
    final osPretty = await _fallbackStr(_str('OperatingSystemPrettyName') ?? '',
            _hostnamed.getOperatingSystemPrettyName) ??
        '';

    // Support end (uint64 microseconds since epoch in systemd)
    DateTime? osSupportEnd;
    final t = _u64('OperatingSystemSupportEnd');
    if (t != null && t > 0) {
      try {
        osSupportEnd =
            DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true).toLocal();
      } catch (_) {
        // fallback if units differ on some impls
        osSupportEnd =
            DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true)
                .toLocal();
      }
    } else {
      // last-ditch single property read
      try {
        final v = await _hostnamed.getOperatingSystemSupportEnd();
        if (v > 0) {
          osSupportEnd =
              DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true).toLocal();
        }
      } catch (_) {}
    }

    return _HostInfo(
      hostname: hostname,
      kernelName: kernelName,
      kernelRelease: kernelRelease,
      kernelVersion: kernelVersion,
      osPretty: osPretty,
      osSupportEnd: osSupportEnd,
      activeIPs: activeIPs,
      describe: describe,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'About Linux',
      body: FutureBuilder<_HostInfo>(
        future: _infoFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return Center(
              child: Text(
                'Could not fetch system information.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            );
          }

          final info = snap.data!;
          final chips = <Widget>[];
          if (info.activeIPs.isNotEmpty) {
            for (final ip in info.activeIPs) {
              chips.add(Chip(
                avatar: const Icon(Icons.public, size: 16),
                label: Text(ip),
              ));
            }
          }

          // small helper to render a “fact” card
          Widget fact({
            required IconData icon,
            required String label,
            required String value,
            String? caption,
          }) {
            if (value.isEmpty) return const SizedBox.shrink();
            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon,
                        size: 22, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(value,
                              style: Theme.of(context).textTheme.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 4),
                          if (caption != null && caption.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              caption,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // Header card
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.linux, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hostname',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer)),
                            const SizedBox(height: 4),
                            Text(
                              info.hostname.isEmpty ? '—' : info.hostname,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (chips.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 6, children: chips),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Facts
                fact(
                  icon: FontAwesomeIcons.microchip,
                  label: 'Kernel',
                  value: [
                    if (info.kernelName.isNotEmpty) info.kernelName,
                    if (info.kernelRelease.isNotEmpty) info.kernelRelease,
                  ].join(' ').trim(),
                  caption: info.kernelVersion,
                ),
                if (info.osPretty.isNotEmpty)
                  fact(
                    icon: FontAwesomeIcons.boxArchive,
                    label: 'Operating System',
                    value: info.osPretty,
                  ),
                if (info.osSupportEnd != null)
                  fact(
                    icon: FontAwesomeIcons.calendarDay,
                    label: 'Support End',
                    value: _fmtDate(info.osSupportEnd!),
                    caption: 'From org.freedesktop.hostname1 (local time).',
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}

class _HostInfo {
  final String hostname;
  final String kernelName;
  final String kernelRelease;
  final String kernelVersion;
  final String osPretty;
  final DateTime? osSupportEnd;
  final List<String> activeIPs;
  final String? describe;

  const _HostInfo({
    required this.hostname,
    required this.kernelName,
    required this.kernelRelease,
    required this.kernelVersion,
    required this.osPretty,
    required this.osSupportEnd,
    required this.activeIPs,
    required this.describe,
  });
}
