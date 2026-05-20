import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;

import 'common.dart';
import '../../providers/state_man.dart';
import 'package:tfc/converter/color_converter.dart'
    show OptionalColorConverter;
import 'package:tfc_dart/core/state_man.dart';

part 'start_stop_button.g.dart';

enum _Segment { run, clean, stop }

/// Drives how a [StartStopPillButtonConfig]'s `manualModeKey` stream maps
/// to the interactive state of the start/stop pill.
///
/// Industrial-HMI convention: "manual mode" means the operator is allowed
/// to drive the output by hand. When the system is NOT in manual mode
/// (i.e. the PLC owns the output), the start/stop controls must be
/// non-interactive AND visually flagged so the operator can't override
/// automation accidentally.
///
///   - [manualWhenTrue]:  stream value `true`  → INTERACTIVE (manual)
///                        stream value `false` → INACTIVE   (auto)  (default)
///   - [manualWhenFalse]: stream value `true`  → INACTIVE
///                        stream value `false` → INTERACTIVE
///
/// When `manualModeKey` is null/empty the polarity is irrelevant and the
/// pill is always interactive (legacy behaviour predating this gate).
@JsonEnum()
enum ManualModePolarity {
  manualWhenTrue,
  manualWhenFalse,
}

@JsonSerializable()
class StartStopPillButtonConfig extends BaseAsset {
  @override
  String get displayName => 'Start/Stop Button';
  @override
  String get category => 'Interactive Controls';

  // pulses (true on press, false on release)
  String runKey;
  String stopKey;
  String? cleanKey; // optional -> hides middle segment if null/empty

  // feedback (boolean states)
  String runningKey;
  String stoppedKey;
  String? cleaningKey; // optional

  /// Optional key (from the Key Repository) whose live BOOL value gates
  /// whether the start/stop segments are interactive. When `null` or
  /// empty, the pill behaves identically to before this field existed
  /// (always interactive).
  ///
  /// Industrial convention: "manual mode" = the operator is *allowed* to
  /// drive this output. When the system is NOT in manual mode, both the
  /// Start and Stop segments must become non-interactive AND visually
  /// tinted to [inactiveColor], with a lock badge overlaid so the operator
  /// immediately sees WHY they can't push it.
  ///
  /// Wire key: `manual_mode_key` (nullable string).
  @JsonKey(name: 'manual_mode_key')
  String? manualModeKey;

  /// Whether a `true` or `false` value on [manualModeKey] means "manual
  /// mode is active". Defaults to [ManualModePolarity.manualWhenTrue].
  ///
  /// Wire key: `manual_mode_polarity` (string enum). Legacy records
  /// without this key fall back to [ManualModePolarity.manualWhenTrue].
  @JsonKey(
    name: 'manual_mode_polarity',
    defaultValue: ManualModePolarity.manualWhenTrue,
    unknownEnumValue: ManualModePolarity.manualWhenTrue,
  )
  ManualModePolarity manualModePolarity;

  /// Tint applied to the Start and Stop icons when the pill is in the
  /// inactive (non-manual / auto-mode-locked) state. Legacy records
  /// without this key fall back to [defaultInactiveColor].
  ///
  /// Wire key: `inactive_color` (nullable RGB map).
  @JsonKey(
    name: 'inactive_color',
    fromJson: _inactiveColorFromJson,
    toJson: _inactiveColorToJson,
  )
  Color inactiveColor;

  /// Default tint for the inactive state when nothing has been configured.
  /// Muted gray, unambiguously inert against the typical red/green/blue
  /// segment palette while leaving the existing icon glyphs legible.
  static const Color defaultInactiveColor = Color(0xFF9E9E9E);

  // ---- inactive_color JSON helpers ----
  //
  // Use a field-level converter pair instead of `@OptionalColorConverter`
  // because the in-memory field is non-nullable: legacy JSON records
  // predating this field have no `inactive_color` key, and we need
  // `fromJson` to substitute [defaultInactiveColor] in that case.

  static Color _inactiveColorFromJson(Map<String, dynamic>? json) {
    final c = const OptionalColorConverter().fromJson(json);
    return c ?? defaultInactiveColor;
  }

  static Map<String, dynamic>? _inactiveColorToJson(Color color) {
    return const OptionalColorConverter().toJson(color);
  }

  StartStopPillButtonConfig({
    required this.runKey,
    required this.stopKey,
    required this.runningKey,
    required this.stoppedKey,
    this.cleanKey,
    this.cleaningKey,
    this.manualModeKey,
    this.manualModePolarity = ManualModePolarity.manualWhenTrue,
    Color? inactiveColor,
  }) : inactiveColor = inactiveColor ?? defaultInactiveColor {
    textPos = TextPos.right;
  }

  StartStopPillButtonConfig.preview()
      : runKey = previewStr,
        stopKey = previewStr,
        runningKey = previewStr,
        stoppedKey = previewStr,
        cleanKey = null,
        cleaningKey = null,
        manualModeKey = null,
        manualModePolarity = ManualModePolarity.manualWhenTrue,
        inactiveColor = defaultInactiveColor {
    textPos = TextPos.right;
  }

  static const previewStr = 'StartStopPillButton preview';

  @override
  List<String> get allKeys {
    final keys = <String>{};
    if (runKey.isNotEmpty) keys.add(runKey);
    if (stopKey.isNotEmpty) keys.add(stopKey);
    if (cleanKey != null && cleanKey!.isNotEmpty) keys.add(cleanKey!);
    if (runningKey.isNotEmpty) keys.add(runningKey);
    if (stoppedKey.isNotEmpty) keys.add(stoppedKey);
    if (cleaningKey != null && cleaningKey!.isNotEmpty) keys.add(cleaningKey!);
    if (manualModeKey != null && manualModeKey!.isNotEmpty) {
      keys.add(manualModeKey!);
    }
    return keys.toList();
  }

  @override
  Widget build(BuildContext context) => StartStopPillButton(this);

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9;
    final maxHeight = media.height * 0.8;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minWidth: 360,
          minHeight: 240,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(child: _ConfigContent(config: this)),
          ),
        ),
      ),
    );
  }

  factory StartStopPillButtonConfig.fromJson(Map<String, dynamic> json) =>
      _$StartStopPillButtonConfigFromJson(json);
  Map<String, dynamic> toJson() => _$StartStopPillButtonConfigToJson(this);
}

class StartStopPillButton extends ConsumerStatefulWidget {
  final StartStopPillButtonConfig config;
  const StartStopPillButton(this.config, {super.key});

  /// Widget key used for the lock overlay rendered when the pill is in
  /// the inactive (non-manual / auto-mode-locked) state. Exposed as a
  /// static so widget tests can find the badge unambiguously.
  static const Key inactiveBadgeKey =
      ValueKey('start-stop-pill-inactive-badge');

  @override
  ConsumerState<StartStopPillButton> createState() =>
      _StartStopPillButtonState();
}

class _StartStopPillButtonState extends ConsumerState<StartStopPillButton> {
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  _Segment? _pressed; // visual press
  String? _activeWriteKey;
  bool _inactive = false; // resolved manual-mode gate (key + polarity)

  Stream<bool> _boolKey(StateMan sm, String? key, {bool seed = false}) {
    if (key == null || key.isEmpty) return Stream.value(seed);
    return sm
        .subscribe(key)
        .asStream()
        .asyncExpand((s) => s)
        .map((v) => v.asBool)
        .startWith(seed);
  }

  // precedence: stopped > running > cleaning
  Stream<_Segment> _stateStream(StateMan sm) {
    final running$ = _boolKey(sm, widget.config.runningKey);
    final stopped$ = _boolKey(sm, widget.config.stoppedKey);
    final cleaning$ = _boolKey(sm, widget.config.cleaningKey);
    return Rx.combineLatest3<bool, bool, bool, _Segment>(
      running$,
      stopped$,
      cleaning$,
      (r, s, c) {
        if (s) return _Segment.stop;
        if (c) return _Segment.clean;
        if (r) return _Segment.run;
        return _Segment.stop;
      },
    );
  }

  /// Translates a raw boolean value from the `manualModeKey` stream into
  /// the resolved "inactive" state given the current polarity. Returns
  /// `false` (not inactive — always interactive) whenever `manualModeKey`
  /// is unset, preserving legacy behaviour.
  bool _resolveInactive(bool raw) {
    final mk = widget.config.manualModeKey;
    if (mk == null || mk.isEmpty) return false;
    switch (widget.config.manualModePolarity) {
      case ManualModePolarity.manualWhenTrue:
        // Manual when TRUE  → inactive when value is FALSE.
        return !raw;
      case ManualModePolarity.manualWhenFalse:
        // Manual when FALSE → inactive when value is TRUE.
        return raw;
    }
  }

  /// Stream of resolved inactive-state. Emits `false` immediately when
  /// `manualModeKey` is null/empty so downstream `combineLatest` never
  /// stalls waiting for a value that will never arrive.
  Stream<bool> _inactiveStream(StateMan sm) {
    final mk = widget.config.manualModeKey;
    if (mk == null || mk.isEmpty) {
      return Stream<bool>.value(false);
    }
    return sm
        .subscribe(mk)
        .asStream()
        .asyncExpand((s) => s)
        .map((v) => _resolveInactive(v.asBool))
        .startWith(_inactive);
  }

  /// Combined view stream: the current active segment AND the current
  /// inactive-gate state. Bundled together so the StreamBuilder rebuild
  /// is driven by one snapshot.
  Stream<_PillView> _viewStream(StateMan sm) {
    return Rx.combineLatest2<_Segment, bool, _PillView>(
      _stateStream(sm),
      _inactiveStream(sm),
      (seg, inactive) {
        _inactive = inactive;
        return _PillView(active: seg, inactive: inactive);
      },
    );
  }

  Future<void> _writePulse(String key, bool value) async {
    if (widget.config.runKey == StartStopPillButtonConfig.previewStr) return;
    final client = await ref.read(stateManProvider.future);
    await client.write(key, DynamicValue(value: value, typeId: NodeId.boolean));
  }

  void _onTapDown(_Segment seg) async {
    // Defense-in-depth: even if the GestureDetector was somehow still
    // wired, the inactive gate must veto any write.
    if (_inactive) return;
    setState(() => _pressed = seg);
    String? key;
    switch (seg) {
      case _Segment.run:
        key = widget.config.runKey;
        break;
      case _Segment.clean:
        key = widget.config.cleanKey;
        break;
      case _Segment.stop:
        key = widget.config.stopKey;
        break;
    }
    if (key == null || key.isEmpty) return;
    _activeWriteKey = key;
    try {
      await _writePulse(key, true);
      _log.d('press -> $seg ($key)');
    } catch (e, st) {
      _log.e('press write failed', error: e, stackTrace: st);
    }
  }

  void _onTapEnd() async {
    final key = _activeWriteKey;
    _activeWriteKey = null;
    setState(() => _pressed = null);
    if (key == null || key.isEmpty) return;
    try {
      await _writePulse(key, false);
      _log.d('release -> $key');
    } catch (e, st) {
      _log.e('release write failed', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final smAsync = ref.watch(stateManProvider);
    final hasClean = (widget.config.cleanKey != null &&
        widget.config.cleanKey!.isNotEmpty);
    final inactiveColor = widget.config.inactiveColor;

    return smAsync.when(
      data: (sm) => StreamBuilder<_PillView>(
        stream: _viewStream(sm),
        builder: (context, snapshot) {
          final view = snapshot.data;
          return _PrettyPill(
            hasClean: hasClean,
            active: view?.active,
            pressed: _pressed,
            inactive: view?.inactive ?? false,
            inactiveColor: inactiveColor,
            onDown: _onTapDown,
            onEnd: _onTapEnd,
          );
        },
      ),
      loading: () => _PrettyPill(
        hasClean: hasClean,
        active: null,
        pressed: _pressed,
        inactive: false,
        inactiveColor: inactiveColor,
        onDown: _onTapDown,
        onEnd: _onTapEnd,
      ),
      error: (_, __) => _PrettyPill(
        hasClean: hasClean,
        active: null,
        pressed: _pressed,
        inactive: false,
        inactiveColor: inactiveColor,
        onDown: _onTapDown,
        onEnd: _onTapEnd,
      ),
    );
  }
}

/// View-model bundle: the resolved active segment AND whether the pill
/// is in the inactive (non-manual / auto-locked) state. Threading both
/// through one StreamBuilder snapshot keeps the build pure.
class _PillView {
  final _Segment active;
  final bool inactive;
  const _PillView({required this.active, required this.inactive});
}

class _PrettyPill extends StatelessWidget {
  final bool hasClean;
  final _Segment? active;
  final _Segment? pressed;
  final bool inactive;
  final Color inactiveColor;
  final void Function(_Segment) onDown;
  final VoidCallback onEnd;

  const _PrettyPill({
    required this.hasClean,
    required this.active,
    required this.pressed,
    required this.inactive,
    required this.inactiveColor,
    required this.onDown,
    required this.onEnd,
  });

  List<_Segment> get _segments =>
      [_Segment.run, if (hasClean) _Segment.clean, _Segment.stop];

  int _indexOf(_Segment seg) => _segments.indexOf(seg);

  Color _accent(BuildContext c, _Segment s) {
    switch (s) {
      case _Segment.run:
        return Colors.green;
      case _Segment.clean:
        return Colors.blue;
      case _Segment.stop:
        return Colors.red;
    }
  }

  IconData _icon(_Segment s) => switch (s) {
        _Segment.run => FontAwesomeIcons.play,
        _Segment.clean => FontAwesomeIcons.droplet,
        _Segment.stop => FontAwesomeIcons.stop,
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final height = c.maxHeight.clamp(32.0, 160.0);
      final radius = height * 0.4;
      final outerR = BorderRadius.circular(radius);
      final count = _segments.length;

      final pad = height * 0.08; // internal inset
      final segW = (width - pad * 2) / count;

      final display = pressed ?? active ?? _segments.last;
      final idx = _indexOf(display);
      final left = pad + segW * idx;

      final scheme = Theme.of(context).colorScheme;
      final trackColor = scheme.surfaceContainerHighest;
      final trackBorder = scheme.outline; // a bit bolder
      final divider = scheme.outlineVariant.withAlpha(64);

      final thumbTop = pad;
      final thumbH = height - pad * 2;
      final isPressed = pressed != null;
      final thumbScale = isPressed ? 0.8 : 0.95;
      final thumbColor = scheme.surface;
      final accent = _accent(context, display);

      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints.tight(Size(width, height)),
          // --- IMPORTANT: clip everything to the pill contour ---
          child: ClipRRect(
            borderRadius: outerR,
            child: Stack(
              children: [
                // Track with *slightly* bolder outer border
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: outerR,
                    border: Border.all(color: trackBorder, width: 1.5),
                  ),
                  child: Row(
                    children: List.generate(count * 2 - 1, (i) {
                      if (i.isEven) {
                        return const Expanded(child: SizedBox());
                      } else {
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: height * 0.12, // keep lines off the arcs
                          ),
                          child: Container(width: 1, color: divider),
                        );
                      }
                    }),
                  ),
                ),

                // Sliding thumb (no border; soft shadow)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOut,
                  left: left,
                  top: thumbTop,
                  width: segW,
                  height: thumbH,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 100),
                    scale: thumbScale,
                    curve: Curves.easeOut,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(thumbH / 2),
                        color: thumbColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(50),
                            blurRadius: 8,
                            offset: Offset(
                              // Adjust shadow offset based on segment position
                              display == _Segment.run
                                  ? -5
                                  : display == _Segment.stop
                                      ? 5
                                      : 0.0,
                              2,
                            ),
                          ),
                        ],
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withAlpha(4),
                            Colors.black.withAlpha(3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Icons & gesture layers
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(count, (i) {
                    final seg = _segments[i];
                    final isActive = display == seg;
                    final iconColor = inactive
                        ? inactiveColor
                        : (isActive
                            ? _accent(context, seg)
                            : scheme.onSurfaceVariant.withOpacity(0.9));

                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: inactive ? null : (_) => onDown(seg),
                        onTapUp: inactive ? null : (_) => onEnd(),
                        onTapCancel: inactive ? null : onEnd,
                        child: LayoutBuilder(
                          builder: (context, cc) {
                            final size = cc.maxHeight * 0.44;
                            return Center(
                              child: Icon(_icon(seg),
                                  size: size, color: iconColor),
                            );
                          },
                        ),
                      ),
                    );
                  }),
                ),

                // Subtle accent underline (softer, clipped to pill)
                if (!inactive)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOut,
                    left: display == _Segment.stop
                        ? left + segW * 0.4
                        : left + segW * 0.30,
                    width: segW * 0.40,
                    bottom: height * 0.12,
                    height: (height * 0.018).clamp(2.0, 4.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withAlpha(50),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),

                // Inactive-state lock overlay. Centered over the pill so
                // the operator immediately sees WHY the segments are
                // greyed out (industrial-HMI convention). Painted as a
                // semi-transparent scrim + centered lock glyph so it
                // reads against any underlying segment icon.
                if (inactive)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        key: StartStopPillButton.inactiveBadgeKey,
                        child: Container(
                          width: height * 0.7,
                          height: height * 0.7,
                          decoration: BoxDecoration(
                            color: scheme.surface.withOpacity(0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: inactiveColor.withOpacity(0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.lock,
                              size: height * 0.42,
                              color: inactiveColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _ConfigContent extends StatefulWidget {
  final StartStopPillButtonConfig config;
  const _ConfigContent({required this.config});

  @override
  State<_ConfigContent> createState() => _ConfigContentState();
}

class _ConfigContentState extends State<_ConfigContent> {
  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Write Keys', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Run Key'),
        KeyField(
          initialValue: cfg.runKey,
          onChanged: (v) => setState(() => cfg.runKey = v),
        ),
        const SizedBox(height: 12),
        const Text('Stop Key'),
        KeyField(
          initialValue: cfg.stopKey,
          onChanged: (v) => setState(() => cfg.stopKey = v),
        ),
        const SizedBox(height: 12),
        const Text('Clean Key (optional)'),
        KeyField(
          initialValue: cfg.cleanKey ?? '',
          onChanged: (v) => setState(() => cfg.cleanKey = v.isEmpty ? null : v),
        ),
        const SizedBox(height: 20),
        const Text('Feedback Keys',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Running Key (bool)'),
        KeyField(
          initialValue: cfg.runningKey,
          onChanged: (v) => setState(() => cfg.runningKey = v),
        ),
        const SizedBox(height: 12),
        const Text('Stopped Key (optional, bool)'),
        KeyField(
          initialValue: cfg.stoppedKey,
          onChanged: (v) => setState(() => cfg.stoppedKey = v),
        ),
        const SizedBox(height: 12),
        const Text('Cleaning Key (optional, bool)'),
        KeyField(
          initialValue: cfg.cleaningKey ?? '',
          onChanged: (v) =>
              setState(() => cfg.cleaningKey = v.isEmpty ? null : v),
        ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: cfg.text,
          decoration: const InputDecoration(labelText: 'Text'),
          onChanged: (v) => setState(() => cfg.text = v),
        ),
        const SizedBox(height: 12),
        CoordinatesField(
          initialValue: cfg.coordinates,
          onChanged: (c) => setState(() => cfg.coordinates = c),
        ),
        const SizedBox(height: 16),
        DropdownButton<TextPos>(
          value: cfg.textPos,
          isExpanded: true,
          onChanged: (v) => setState(() => cfg.textPos = v ?? cfg.textPos),
          items: TextPos.values
              .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
              .toList(),
        ),
        const SizedBox(height: 16),
        SizeField(
          initialValue: cfg.size,
          onChanged: (c) => setState(() => cfg.size = c),
        ),

        const SizedBox(height: 24),

        // ----- Manual-mode gate (optional) -----
        const Text(
          'Manual Mode Gate',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bind a BOOL key whose live value signals whether the operator is '
          'in manual mode. When NOT in manual mode, Start and Stop become '
          'non-interactive and a lock badge is rendered. Leave empty to '
          'keep the pill always interactive.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Manual Mode Key'),
            const SizedBox(width: 8),
            Expanded(
              child: KeyField(
                initialValue: cfg.manualModeKey ?? '',
                onChanged: (value) {
                  setState(() {
                    cfg.manualModeKey = value.isEmpty ? null : value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Polarity — always shown so users can pre-set the intended
        // polarity before they pick the key (mirrors the Button editor).
        const Text('Manual Mode Polarity'),
        const SizedBox(height: 4),
        SegmentedButton<ManualModePolarity>(
          segments: const [
            ButtonSegment(
              value: ManualModePolarity.manualWhenTrue,
              label: Text('Manual when TRUE'),
            ),
            ButtonSegment(
              value: ManualModePolarity.manualWhenFalse,
              label: Text('Manual when FALSE'),
            ),
          ],
          selected: {cfg.manualModePolarity},
          onSelectionChanged: (newSelection) {
            setState(() {
              cfg.manualModePolarity = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 8),

        // Inactive color — only useful when a manual-mode key is bound
        // (the color is never rendered otherwise), so hide it in that
        // case to reduce visual noise.
        if (cfg.manualModeKey != null && cfg.manualModeKey!.isNotEmpty) ...[
          Row(
            children: [
              const Text('Inactive Color'),
              const SizedBox(width: 8),
              Expanded(
                child: BlockPicker(
                  pickerColor: cfg.inactiveColor,
                  onColorChanged: (value) {
                    setState(() {
                      cfg.inactiveColor = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
