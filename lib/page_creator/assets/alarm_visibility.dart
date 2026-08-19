import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tfc_dart/core/alarm.dart';

import '../../providers/alarm.dart';
import '../../widgets/alarm.dart'
    show AlarmNotificationColors, ViewActiveAlarm, alarmLevelColors;
import '../../widgets/fuzzy_search_bar.dart';
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'common.dart';

part 'alarm_visibility.g.dart';

// ---------------------------------------------------------------------------
// Alarm visibility asset
// ---------------------------------------------------------------------------
//
// A beacon the operator places wherever an alarm condition physically lives
// on the mimic. While any bound alarm is active it draws attention with
// expanding, fading rings in the linked alarm's own colours (highest active
// level wins); tapping it opens the alarm's title, description, level, and
// acknowledge button in the side pane. While idle it renders nothing in page
// view (a faint marker is opt-in), and always shows a placeholder on the
// editor canvas.

/// Filters [active] down to the alarms this beacon represents and orders them
/// most-severe first.
///
/// An empty [uids] list means "every alarm" — a freshly placed beacon lights
/// up for anything until it is narrowed down in the config editor.
///
/// Mirrors `AlarmMan.filterAlarms`: one entry per alarm uid (the highest
/// active level wins), sorted by level descending then timestamp descending —
/// so `first` is always the alarm the beacon should take its colour from.
List<AlarmActive> matchingActiveAlarms(
    Iterable<AlarmActive> active, List<String> uids) {
  final filtered = uids.isEmpty
      ? active
      : active.where((a) => uids.contains(a.alarm.config.uid));

  final Map<String, AlarmActive> highest = {};
  for (final a in filtered) {
    final existing = highest[a.alarm.config.uid];
    if (existing == null ||
        a.notification.rule.level.index >
            existing.notification.rule.level.index) {
      highest[a.alarm.config.uid] = a;
    }
  }

  return highest.values.toList()
    ..sort((a, b) {
      final byLevel = b.notification.rule.level.index
          .compareTo(a.notification.rule.level.index);
      if (byLevel != 0) return byLevel;
      return b.notification.timestamp.compareTo(a.notification.timestamp);
    });
}

@JsonSerializable(explicitToJson: true)
class AlarmVisibilityConfig extends BaseAsset {
  @override
  String get displayName => 'Alarm';

  @override
  String get category => 'Visualization';

  /// Uids of the `AlarmConfig`s this beacon represents. Empty means every
  /// alarm (see [matchingActiveAlarms]).
  @JsonKey(name: 'alarm_uids', defaultValue: <String>[])
  List<String> alarmUids;

  /// When true the beacon shows a faint tappable marker at runtime while no
  /// bound alarm is active. Default off: an idle beacon renders nothing in
  /// page view — no marker, no tap target. The editor canvas always shows a
  /// placeholder (via [AssetEditModeScope]) so it can be found and moved.
  @JsonKey(name: 'show_when_inactive', defaultValue: false)
  bool showWhenInactive;

  /// Palette/preview instance — renders a static active-look frame instead of
  /// subscribing to live alarms. Never persisted.
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool isPreview = false;

  AlarmVisibilityConfig({
    List<String>? alarmUids,
    this.showWhenInactive = false,
  }) : alarmUids = alarmUids ?? [] {
    textPos = TextPos.below;
  }

  AlarmVisibilityConfig.preview()
      : alarmUids = [],
        showWhenInactive = false {
    isPreview = true;
    textPos = TextPos.below;
  }

  factory AlarmVisibilityConfig.fromJson(Map<String, dynamic> json) =>
      _$AlarmVisibilityConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$AlarmVisibilityConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return AlarmVisibility(config: this);
  }

  @override
  Widget configure(BuildContext context) {
    return _AlarmVisibilityConfigEditor(config: this);
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// The active beacon: a solid centre dot plus [rings] concentric rings that
/// expand from the dot to the asset edge and fade out, staggered evenly in
/// phase so one ring is always mid-flight.
///
/// [progress] is the animation phase in [0, 1); the painter is pure so a
/// static frame (palette thumbnail, config preview, goldens) is just a fixed
/// progress value.
///
/// Takes the alarm system's (background, foreground) pair from
/// [alarmLevelColors]. The rings and the dot fill carry [color] — the
/// container role the alarm card is painted in, i.e. the colour operators
/// already read as "this alarm" (Solarized: yellow warning, red error). The
/// dot is outlined in [dotOutlineColor] (the card's text colour) for
/// definition. The rings must NOT use the foreground role: it is chosen for
/// contrast against the card surface, not the page — in the Solarized light
/// theme it is the same cream as the scaffold, which made the rings vanish.
class AlarmPulsePainter extends CustomPainter {
  final Color color;
  final Color dotOutlineColor;
  final double progress;
  final int rings;

  AlarmPulsePainter({
    required this.color,
    required this.dotOutlineColor,
    required this.progress,
    this.rings = 3,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;
    final dotRadius = maxRadius * 0.22;

    for (var i = 0; i < rings; i++) {
      final t = (progress + i / rings) % 1.0;
      // Linear fade: quadratic killed the ring before it reached the edge,
      // so the expansion — the whole point of the beacon — went unseen.
      final fade = (1 - t) * 0.9;
      final paint = Paint()
        ..color = color.withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        // Rings thin out as they expand — reads as energy dissipating.
        ..strokeWidth = 1.0 + 3.0 * (1 - t);
      canvas.drawCircle(
        center,
        dotRadius + (maxRadius - dotRadius) * t,
        paint,
      );
    }

    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..color = dotOutlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(AlarmPulsePainter oldDelegate) =>
      color != oldDelegate.color ||
      dotOutlineColor != oldDelegate.dotOutlineColor ||
      progress != oldDelegate.progress ||
      rings != oldDelegate.rings;
}

/// The idle marker: a small dot inside a thin outline ring. Faint on purpose —
/// an inactive alarm must not compete with live process graphics, it only has
/// to be findable (and tappable, to read what the beacon watches).
class AlarmIdlePainter extends CustomPainter {
  final Color color;

  AlarmIdlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, maxRadius * 0.4, paint);
    canvas.drawCircle(
      center,
      maxRadius * 0.12,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(AlarmIdlePainter oldDelegate) =>
      color != oldDelegate.color;
}

// ---------------------------------------------------------------------------
// Runtime widget
// ---------------------------------------------------------------------------

class AlarmVisibility extends ConsumerStatefulWidget {
  final AlarmVisibilityConfig config;
  const AlarmVisibility({super.key, required this.config});

  @override
  ConsumerState<AlarmVisibility> createState() => _AlarmVisibilityState();
}

class _AlarmVisibilityState extends ConsumerState<AlarmVisibility>
    with SingleTickerProviderStateMixin {
  // Created in initState, not lazily — a `late final` initializer whose first
  // touch is `dispose()` (idle widget, no alarm event ever arrived) would
  // construct the controller during teardown, where the vsync's TickerMode
  // ancestor lookup is illegal.
  late final AnimationController _controller;

  StreamSubscription<List<AlarmActive>>? _sub;
  List<AlarmActive> _active = const [];

  /// The uid list `_sub` was built for. Compared by content, not identity —
  /// the config editor mutates `alarmUids` in place, so the reference never
  /// changes (same invariant as `_SensorState._hoistedKey`).
  String? _subscribedUids;

  String get _paneId => 'alarm-visibility:${identityHashCode(widget.config)}';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AlarmVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_subscribedUids != widget.config.alarmUids.join('\x00')) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    // The pane is docked to the root overlay and would outlive this route.
    closeSidePane(id: _paneId);
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// (Re)builds the active-alarm subscription. Called from `initState` and
  /// from `didUpdateWidget` only when the uid list changes — never from
  /// `build`.
  void _subscribe() {
    _sub?.cancel();
    _sub = null;
    _subscribedUids = widget.config.alarmUids.join('\x00');
    if (widget.config.isPreview) return;

    _sub = ref
        .read(alarmManProvider.future)
        .asStream()
        .switchMap((alarmMan) => alarmMan.activeAlarms())
        .map((set) => matchingActiveAlarms(set, widget.config.alarmUids))
        .listen((list) {
      if (!mounted) return;
      setState(() => _active = list);
      _syncAnimation();
    }, onError: (Object e, StackTrace s) {
      // No alarm service (e.g. editor harness) — behave as idle.
      if (!mounted) return;
      setState(() => _active = const []);
      _syncAnimation();
    });
  }

  /// The ticker runs only while something is active — an idle beacon costs
  /// zero repaints, which matters on a panel showing dozens of these 24/7.
  void _syncAnimation() {
    if (_active.isNotEmpty) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  /// Test-only window: drives the widget into the same state a live
  /// `AlarmMan` emission would, without needing a `StateMan` behind it.
  @visibleForTesting
  void debugSetActive(List<AlarmActive> active) {
    setState(() => _active = matchingActiveAlarms(active, const []));
    _syncAnimation();
  }

  void _showPane(BuildContext context) {
    showSidePane(
      context: context,
      id: _paneId,
      builder: (_) => AlarmVisibilityPane(config: widget.config),
    );
  }

  /// Sensor's sizing pattern: bounded constraints (the asset rect) win,
  /// otherwise fall back to the config size resolved against the screen.
  Widget _sizedPaint(CustomPainter painter) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size paintSize;
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          paintSize = Size(constraints.maxWidth, constraints.maxHeight);
        } else {
          paintSize = widget.config.size.toSize(MediaQuery.of(context).size);
        }
        return CustomPaint(size: paintSize, painter: painter);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    // Palette thumbnail / static previews: one mid-animation frame of the
    // worst-case look. Static on purpose — the palette builds every default
    // asset live, and a repeating ticker there would never let tests settle.
    if (config.isPreview) {
      final (fill, ring) = alarmLevelColors(context, AlarmLevel.error);
      return _sizedPaint(AlarmPulsePainter(
        color: fill,
        dotOutlineColor: ring,
        progress: 0.35,
      ));
    }

    if (_active.isNotEmpty) {
      // The linked alarm's own colours — the exact pair its card renders
      // with in the alarm list and app-bar banner.
      final (fill, ring) = _active.first.notification.getColors(context);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showPane(context),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _sizedPaint(
            AlarmPulsePainter(
              color: fill,
              dotOutlineColor: ring,
              progress: _controller.value,
            ),
          ),
        ),
      );
    }

    // Idle. On the editor canvas always show the marker — an invisible asset
    // cannot be found, selected, or moved. In page view the marker is opt-in
    // (showWhenInactive) and off by default.
    final editing = AssetEditModeScope.isEditing(context);
    if (!editing && !config.showWhenInactive) {
      return const SizedBox.shrink();
    }
    final outline = Theme.of(context).colorScheme.outline;
    final marker = _sizedPaint(
      AlarmIdlePainter(color: outline.withValues(alpha: editing ? 0.9 : 0.5)),
    );
    if (editing) return marker;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPane(context),
      child: marker,
    );
  }
}

// ---------------------------------------------------------------------------
// Side pane
// ---------------------------------------------------------------------------

/// The operator pane behind a beacon tap.
///
/// Data layer only: subscribes to the alarm service (an independent
/// subscription that lives and dies with the pane) and hands the resolved
/// state to [AlarmVisibilityPaneView] for rendering.
class AlarmVisibilityPane extends ConsumerWidget {
  final AlarmVisibilityConfig config;

  const AlarmVisibilityPane({super.key, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<(AlarmMan, List<AlarmActive>)>(
      stream: ref.watch(alarmManProvider.future).asStream().switchMap(
            (alarmMan) => alarmMan.activeAlarms().map(
                (set) => (alarmMan, matchingActiveAlarms(set, config.alarmUids))),
          ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AlarmVisibilityPaneView.message(
            config: config,
            status: const PaneStatus.unknown('Unavailable'),
            message: 'Alarm service unavailable.',
          );
        }
        if (!snapshot.hasData) {
          return AlarmVisibilityPaneView.message(
            config: config,
            status: const PaneStatus.unknown('Connecting'),
            message: 'Connecting to alarm service…',
          );
        }
        final (alarmMan, active) = snapshot.data!;
        return AlarmVisibilityPaneView(
          config: config,
          active: active,
          allAlarms: alarmMan.alarms.map((a) => a.config).toList(),
        );
      },
    );
  }
}

/// Pure rendering of the beacon's pane — driven entirely by resolved data,
/// so tests and goldens can pump it without an `AlarmMan` (which cannot be
/// constructed without a live `StateMan`).
///
/// Active alarms render as full [ViewActiveAlarm] cards — title, timestamps,
/// description, level, expression, and the acknowledge button. With nothing
/// active it lists what the beacon is watching instead, so a tap always
/// answers "what alarm is this?".
class AlarmVisibilityPaneView extends StatelessWidget {
  final AlarmVisibilityConfig config;

  /// Active alarms this beacon matches, most severe first.
  final List<AlarmActive> active;

  /// Every configured alarm; filtered down to the watched set for the idle
  /// body.
  final List<AlarmConfig> allAlarms;

  /// When non-null, replaces the body with a plain message (service
  /// unavailable / still connecting) under [statusOverride].
  final String? message;
  final PaneStatus? statusOverride;

  const AlarmVisibilityPaneView({
    super.key,
    required this.config,
    this.active = const [],
    this.allAlarms = const [],
  })  : message = null,
        statusOverride = null;

  const AlarmVisibilityPaneView.message({
    super.key,
    required this.config,
    required PaneStatus status,
    required String this.message,
  })  : active = const [],
        allAlarms = const [],
        statusOverride = status;

  String get _title {
    final text = config.text;
    return (text == null || text.isEmpty) ? 'Alarms' : text;
  }

  PaneStatus _statusFor(List<AlarmActive> active) {
    if (active.isEmpty) return const PaneStatus.stopped('No active alarms');
    switch (active.first.notification.rule.level) {
      case AlarmLevel.error:
        return const PaneStatus.fault('Alarm');
      case AlarmLevel.warning:
        return const PaneStatus.warning('Warning');
      case AlarmLevel.info:
        return const PaneStatus.running('Info');
    }
  }

  SidePane _pane({
    String? subtitle,
    required PaneStatus status,
    required Widget child,
  }) {
    return SidePane(
      title: _title,
      subtitle: subtitle,
      icon: Icons.notifications_active,
      status: status,
      child: child,
    );
  }

  /// The idle body: every alarm this beacon is bound to, title + description.
  Widget _watchedAlarms(BuildContext context) {
    final bound = allAlarms
        .where(
            (c) => config.alarmUids.isEmpty || config.alarmUids.contains(c.uid))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return PaneSection(
      title:
          config.alarmUids.isEmpty ? 'Watching all alarms' : 'Watched alarms',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bound.isEmpty) const Text('No matching alarms are configured.'),
          for (final alarm in bound)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(alarm.title,
                      style: Theme.of(context).textTheme.titleSmall),
                  if (alarm.description.isNotEmpty)
                    Text(alarm.description,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (message != null) {
      return _pane(
        status: statusOverride ?? const PaneStatus.unknown('Unknown'),
        child: PaneSection(
          title: 'Alarms',
          child: Text(message!),
        ),
      );
    }
    if (active.isEmpty) {
      return _pane(
        status: _statusFor(active),
        child: _watchedAlarms(context),
      );
    }
    return _pane(
      subtitle: '${active.length} active',
      status: _statusFor(active),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final alarm in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ViewActiveAlarm(alarm: alarm),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Config editor
// ---------------------------------------------------------------------------

/// Searchable multi-select alarm list for the config editor.
///
/// A plant can have hundreds of alarms, so a flat checkbox column is
/// unusable — this caps the list's height and puts the same fuzzy search on
/// top as the alarm list page. Mutates [selectedUids] in place and calls
/// [onSelectionChanged], preserving the editor's live-config contract.
class AlarmPickerList extends StatefulWidget {
  final List<AlarmConfig> alarms;
  final List<String> selectedUids;
  final VoidCallback onSelectionChanged;
  final double maxHeight;

  const AlarmPickerList({
    super.key,
    required this.alarms,
    required this.selectedUids,
    required this.onSelectionChanged,
    this.maxHeight = 280,
  });

  @override
  State<AlarmPickerList> createState() => _AlarmPickerListState();
}

class _AlarmPickerListState extends State<AlarmPickerList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.alarms]
      ..sort((a, b) => a.title.compareTo(b.title));
    final filtered = fuzzyFilter<AlarmConfig>(sorted, _query, [
      (a) => a.title,
      (a) => a.description,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FuzzySearchBar(
          hintText: 'Search alarms...',
          decoration: const InputDecoration(
            hintText: 'Search alarms...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No alarms match the search.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final alarm = filtered[index];
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(alarm.title),
                      subtitle: alarm.description.isEmpty
                          ? null
                          : Text(
                              alarm.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      value: widget.selectedUids.contains(alarm.uid),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            widget.selectedUids.add(alarm.uid);
                          } else {
                            widget.selectedUids.remove(alarm.uid);
                          }
                        });
                        widget.onSelectionChanged();
                      },
                    );
                  },
                ),
        ),
        if (widget.selectedUids.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.selectedUids.length} of ${widget.alarms.length} '
                  'selected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => widget.selectedUids.clear());
                  widget.onSelectionChanged();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
      ],
    );
  }
}

/// Editor body for [AlarmVisibilityConfig]. All edits mutate the live config
/// instance in place — the page editor's config pane mirrors them back onto
/// the canvas (same contract as `_SensorConfigEditor`).
class _AlarmVisibilityConfigEditor extends ConsumerStatefulWidget {
  final AlarmVisibilityConfig config;
  const _AlarmVisibilityConfigEditor({required this.config});

  @override
  ConsumerState<_AlarmVisibilityConfigEditor> createState() =>
      _AlarmVisibilityConfigEditorState();
}

class _AlarmVisibilityConfigEditorState
    extends ConsumerState<_AlarmVisibilityConfigEditor>
    with SingleTickerProviderStateMixin {
  /// Drives the preview only while the Play toggle is on. Never auto-runs:
  /// the editor's tests (and `pumpAndSettle`) need a quiescent default.
  late final AnimationController _previewController;

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  void _togglePreview() {
    setState(() {
      if (_previewController.isAnimating) {
        _previewController.stop();
        _previewController.value = 0;
      } else {
        _previewController.repeat();
      }
    });
  }

  Widget _alarmPicker(BuildContext context) {
    return FutureBuilder<AlarmMan>(
      future: ref.watch(alarmManProvider.future),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Alarm service unavailable — cannot list alarms.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        if (!snapshot.hasData) {
          return Text(
            'Loading alarms…',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        final alarms = snapshot.data!.alarms.map((a) => a.config).toList();
        if (alarms.isEmpty) {
          return Text(
            'No alarms configured yet — this beacon will react to every '
            'alarm added later.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return AlarmPickerList(
          alarms: alarms,
          selectedUids: widget.config.alarmUids,
          onSelectionChanged: () => setState(() {}),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Live preview + Play toggle --
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: AnimatedBuilder(
                      animation: _previewController,
                      builder: (context, _) {
                        final (fill, ring) =
                            alarmLevelColors(context, AlarmLevel.error);
                        return CustomPaint(
                          painter: AlarmPulsePainter(
                            color: fill,
                            dotOutlineColor: ring,
                            progress: _previewController.isAnimating
                                ? _previewController.value
                                : 0.35,
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: _previewController.isAnimating
                        ? 'Stop preview'
                        : 'Play preview',
                    icon: Icon(_previewController.isAnimating
                        ? Icons.stop
                        : Icons.play_arrow),
                    onPressed: _togglePreview,
                  ),
                ],
              ),
            ),
            const Divider(),

            // -- Alarm selection --
            Text('Alarms', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            _alarmPicker(context),
            const SizedBox(height: 4),
            Text(
              'The beacon pulses in the colour of the highest active level. '
              'No selection means it reacts to every alarm.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // -- Show idle marker --
            SwitchListTile(
              title: const Text('Show idle marker'),
              subtitle: Text(
                config.showWhenInactive
                    ? 'Shows a faint tappable marker while idle'
                    : 'Invisible until an alarm activates (editor always '
                        'shows a placeholder)',
              ),
              value: config.showWhenInactive,
              onChanged: (v) => setState(() => config.showWhenInactive = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            // -- Label --
            TextFormField(
              initialValue: config.text,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Optional',
              ),
              onChanged: (v) {
                setState(() => config.text = v.isEmpty ? null : v);
              },
            ),
            const SizedBox(height: 16),

            // -- Label Position --
            Text('Label Position',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButton<TextPos>(
              value: config.textPos ?? TextPos.below,
              isExpanded: true,
              onChanged: (value) {
                setState(() => config.textPos = value!);
              },
              items: TextPos.values
                  .map((e) =>
                      DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // -- Size --
            SizeField(
              initialValue: config.size,
              useSingleSize: true,
              onChanged: (v) => setState(() => config.size = v),
            ),
            const SizedBox(height: 16),

            // -- Coordinates --
            CoordinatesField(
              initialValue: config.coordinates,
              onChanged: (c) => setState(() => config.coordinates = c),
            ),
          ],
        ),
      ),
    );
  }
}
