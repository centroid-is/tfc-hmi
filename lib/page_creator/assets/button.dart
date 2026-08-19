import 'dart:math';
import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:tfc/widgets/panes/color_picker_dialog.dart';
import 'package:tfc/widgets/panes/standard_dialog.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;

import 'common.dart';
import 'icon.dart'; // Reuse IconConfig + IconAsset
import '../../providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc/converter/color_converter.dart'
    show AssetColor, AssetColorConverter, ColorConverter, OptionalColorConverter;

part 'button.g.dart';

@JsonSerializable()
class FeedbackConfig {
  String key = "Default";
  @ColorConverter()
  Color color = Colors.green;

  FeedbackConfig();

  factory FeedbackConfig.fromJson(Map<String, dynamic> json) =>
      _$FeedbackConfigFromJson(json);
  Map<String, dynamic> toJson() => _$FeedbackConfigToJson(this);
}

@JsonEnum()
enum ButtonType {
  circle,
  square,
}

/// Internal segmented-button state for the [ButtonConfig] editor's
/// "Text Color" toggle. Not serialized — it's purely a UI mode derived
/// from `ButtonConfig.textColor == null` (useDefault) or non-null
/// (custom). Kept private to this library to avoid leaking editor
/// internals into asset JSON.
enum _TextColorMode { useDefault, custom }

/// Seed value used when the operator first switches the Text Color
/// toggle from "Default" to "Custom" — pure black so the picker swatch
/// renders something visible immediately. The operator is expected to
/// pick their actual color from the picker row that appears underneath.
const Color _defaultTextColorSeed = Color(0xFF000000);

/// Drives how a [ButtonConfig]'s `disabledKey` stream maps to the
/// disabled/enabled visual + interactive state of the button.
///
///   - [disableWhenTrue]:  stream value `true`  → disabled
///                         stream value `false` → enabled  (default)
///   - [disableWhenFalse]: stream value `true`  → enabled
///                         stream value `false` → disabled
///
/// When `disabledKey` is null/empty the polarity is irrelevant and the
/// button is always interactive.
@JsonEnum()
enum DisabledPolarity {
  disableWhenTrue,
  disableWhenFalse,
}

@JsonSerializable()
class ButtonConfig extends BaseAsset {
  @override
  String get displayName => 'Button';
  @override
  String get category => 'Interactive Controls';

  String key;

  /// Optional live feedback indicator (key + color)
  FeedbackConfig? feedback;

  /// Optional icon rendered on top of the button (centered, scaled)
  @JsonKey(name: 'icon')
  IconConfig? icon;

  @AssetColorConverter()
  @JsonKey(name: 'outward_color')
  AssetColor outwardColor;

  @AssetColorConverter()
  @JsonKey(name: 'inward_color')
  AssetColor inwardColor;

  @JsonKey(name: 'button_type')
  ButtonType buttonType;

  /// Whether the button should toggle (stick) when pressed
  @JsonKey(name: 'is_toggle')
  bool isToggle = false;

  @JsonKey(name: 'server_writes_low')
  bool serverWritesLow = false;

  /// Optional key (from the Key Repository) whose live BOOL value gates
  /// whether this button is interactive. When `null` or empty, the button
  /// behaves identically to before this field existed.
  ///
  /// Wire key: `disabled_key` (nullable string).
  @JsonKey(name: 'disabled_key')
  String? disabledKey;

  /// Whether a `true` or `false` value on [disabledKey] disables the
  /// button. Defaults to [DisabledPolarity.disableWhenTrue].
  ///
  /// Wire key: `disabled_polarity` (string enum). Legacy records without
  /// this key fall back to [DisabledPolarity.disableWhenTrue].
  @JsonKey(
    name: 'disabled_polarity',
    defaultValue: DisabledPolarity.disableWhenTrue,
    unknownEnumValue: DisabledPolarity.disableWhenTrue,
  )
  DisabledPolarity disabledPolarity;

  /// Background color rendered while the button is in the disabled state.
  /// Stored on disk as a nullable RGB map (same shape as the existing
  /// [ColorConverter]); legacy records without this key fall back to a
  /// muted gray via [_disabledColorFromJson].
  ///
  /// Wire key: `disabled_color` (nullable RGB map).
  @JsonKey(
    name: 'disabled_color',
    fromJson: _disabledColorFromJson,
    toJson: _disabledColorToJson,
  )
  Color disabledColor;

  /// Optional override for the button label color. When `null`, the label
  /// renders with the ambient theme default (current behaviour predating
  /// this field). When non-null, the label paints in this color.
  ///
  /// The editor's "Default" / "Custom" toggle derives its state from this
  /// field — there is no separate `useDefaultTextColor` JSON key. Existing
  /// persisted records without `text_color` load as `null`, preserving the
  /// pre-field rendering byte-for-byte.
  ///
  /// Wire key: `text_color` (nullable RGB map).
  @OptionalColorConverter()
  @JsonKey(name: 'text_color', defaultValue: null)
  Color? textColor;

  /// `Asset.labelColor` is consumed by `AssetStack` in `page_view.dart`
  /// to paint the label. For buttons it is just the configured
  /// `textColor` (see field above). Other asset types currently leave
  /// the default `null` from `BaseAsset` and so render with the ambient
  /// `DefaultTextStyle` color.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  Color? get labelColor => textColor;

  /// Default fill color for the disabled state when nothing has been
  /// configured. Picked to be unambiguously inert against the typical
  /// outward palette (green / red / blue) while still letting the button
  /// label / icon remain visible.
  static const Color defaultDisabledColor = Color(0xFF9E9E9E);

  // ---- disabled_color JSON helpers ----
  //
  // Use a field-level converter pair instead of `@OptionalColorConverter`
  // because the in-memory field is non-nullable: legacy JSON records
  // predating this field have no `disabled_color` key, and we need
  // `fromJson` to substitute [defaultDisabledColor] in that case.

  static Color _disabledColorFromJson(Map<String, dynamic>? json) {
    final c = const OptionalColorConverter().fromJson(json);
    return c ?? defaultDisabledColor;
  }

  static Map<String, dynamic>? _disabledColorToJson(Color color) {
    return const OptionalColorConverter().toJson(color);
  }

  @override
  Widget build(BuildContext context) {
    return Button(this);
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9; // Use 90% of screen width
    final maxHeight = media.height * 0.8; // Use 80% of screen height

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minWidth: 320,
          minHeight: 200,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  ButtonConfig({
    required this.key,
    this.outwardColor = AssetColor.primary,
    this.inwardColor = AssetColor.secondary,
    required this.buttonType,
    this.icon,
    this.feedback,
    this.isToggle = false,
    this.serverWritesLow = false,
    this.disabledKey,
    this.disabledPolarity = DisabledPolarity.disableWhenTrue,
    Color? disabledColor,
    this.textColor,
  }) : disabledColor = disabledColor ?? defaultDisabledColor;

  static const previewStr = 'Button preview';

  ButtonConfig.preview()
      : key = previewStr,
        outwardColor = AssetColor.primary,
        inwardColor = AssetColor.secondary,
        buttonType = ButtonType.circle,
        icon = null,
        feedback = null,
        isToggle = false,
        serverWritesLow = false,
        disabledKey = null,
        disabledPolarity = DisabledPolarity.disableWhenTrue,
        disabledColor = defaultDisabledColor,
        textColor = null {
    textPos = TextPos.right;
  }

  @override
  List<String> get allKeys {
    final keys = <String>{};
    if (key.isNotEmpty) keys.add(key);
    if (feedback != null && feedback!.key.isNotEmpty) {
      keys.add(feedback!.key);
    }
    if (disabledKey != null && disabledKey!.isNotEmpty) {
      keys.add(disabledKey!);
    }
    return keys.toList();
  }

  factory ButtonConfig.fromJson(Map<String, dynamic> json) =>
      _$ButtonConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ButtonConfigToJson(this);
}

class Button extends ConsumerStatefulWidget {
  final ButtonConfig config;

  const Button(this.config, {super.key});

  @override
  ConsumerState<Button> createState() => _ButtonState();
}

class _ButtonState extends ConsumerState<Button> {
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  final _pressedController = StreamController<bool>.broadcast();
  bool _isPressed = false;
  bool _feedbackActive = false;
  bool _isToggled = false; // Add toggle state
  bool _disabled = false; // Current resolved disabled state (key + polarity)

  @override
  void dispose() {
    _pressedController.close();
    super.dispose();
  }

  // Call this in onTapDown, onTapUp, onTapCancel
  void _setPressed(bool value) {
    if (_isPressed != value) {
      setState(() => _isPressed = value);
      _pressedController.add(value);
    }
  }

  // Handle toggle logic
  void _handleToggle() {
    if (widget.config.isToggle) {
      setState(() => _isToggled = !_isToggled);
      _pressedController.add(_isToggled);
    }
  }

  /// Translates a raw boolean value from the `disabledKey` stream into the
  /// resolved disabled state given the current polarity. Returns `false`
  /// (not disabled) whenever `disabledKey` is unset.
  bool _resolveDisabled(bool raw) {
    final dk = widget.config.disabledKey;
    if (dk == null || dk.isEmpty) return false;
    switch (widget.config.disabledPolarity) {
      case DisabledPolarity.disableWhenTrue:
        return raw;
      case DisabledPolarity.disableWhenFalse:
        return !raw;
    }
  }

  /// Stream of resolved disabled-state for this widget. Emits `false`
  /// immediately when `disabledKey` is null/empty so the combineLatest
  /// downstream never stalls.
  Stream<bool> _disabledStream(StateMan stateMan) {
    final dk = widget.config.disabledKey;
    if (dk == null || dk.isEmpty) {
      return Stream<bool>.value(false);
    }
    return stateMan
        .subscribe(dk)
        .asStream()
        .asyncExpand((s) => s)
        .map((value) => _resolveDisabled(value.asBool))
        .startWith(_disabled);
  }

  Stream<Color> colorStream(StateMan stateMan) {
    final feedbackStream = widget.config.feedback == null
        ? Stream<bool>.value(false)
        : stateMan
            .subscribe(widget.config.feedback!.key)
            .asStream()
            .asyncExpand((s) => s)
            .map((value) => value?.asBool ?? false)
            .startWith(_feedbackActive);

    final pressedStream = _pressedController.stream.startWith(_isPressed);
    final disabledStream = _disabledStream(stateMan);

    return Rx.combineLatest3<bool, bool, bool, Color>(
      feedbackStream,
      pressedStream,
      disabledStream,
      (feedbackActive, isPressed, disabled) {
        _feedbackActive = feedbackActive;
        // Update _disabled outside of setState — Flutter rebuilds via the
        // StreamBuilder's snapshot, and the build method reads _disabled
        // through `_buildButton`'s onPressed gating.
        _disabled = disabled;
        if (disabled) {
          return widget.config.disabledColor;
        }
        if (feedbackActive) {
          return widget.config.feedback!.color;
        }
        // For toggle buttons, use toggled state; for regular buttons, use pressed state
        final shouldShowPressed =
            widget.config.isToggle ? _isToggled : isPressed;
        return shouldShowPressed
            ? widget.config.inwardColor.resolve(context)
            : widget.config.outwardColor.resolve(context);
      },
    );
  }

  Widget _buildButton(Color color) {
    final isPreview = widget.config.key == ButtonConfig.previewStr;
    // When the disabled-key gate is asserted, all tap callbacks must be
    // null so InkWell renders + behaves as non-interactive.
    final disabled = _disabled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: widget.config.buttonType == ButtonType.circle
            ? const CircleBorder()
            : const RoundedRectangleBorder(),
        onTapDown: disabled
            ? null
            : (_) async {
                if (!widget.config.isToggle) {
                  _setPressed(true);
                }
                if (isPreview) return;

                if (widget.config.isToggle) {
                  // For toggle buttons, just handle the toggle
                  _handleToggle();
                } else {
                  // For regular buttons, write true
                  final client = await ref.read(stateManProvider.future);
                  try {
                    await client.write(widget.config.key,
                        DynamicValue(value: true, typeId: NodeId.boolean));
                    _log.d('Button ${widget.config.key} pressed');
                  } catch (e) {
                    _log.e('Error writing button press', error: e);
                  }
                }
              },
        onTapUp: disabled
            ? null
            : (_) async {
                if (!widget.config.isToggle) {
                  _setPressed(false);
                }
                if (isPreview) return;

                if (!widget.config.isToggle) {
                  // For regular buttons, write false
                  try {
                    if (!widget.config.serverWritesLow) {
                      final client = await ref.read(stateManProvider.future);
                      await client.write(widget.config.key,
                          DynamicValue(value: false, typeId: NodeId.boolean));
                      _log.d('Button ${widget.config.key} released');
                    }
                  } catch (e) {
                    _log.e('Error writing button release', error: e);
                  }
                }
              },
        onTapCancel: disabled
            ? null
            : () async {
                if (!widget.config.isToggle) {
                  _setPressed(false);
                }
                if (isPreview) return;

                if (!widget.config.isToggle) {
                  // For regular buttons, write false
                  final client = await ref.read(stateManProvider.future);
                  try {
                    await client.write(widget.config.key,
                        DynamicValue(value: false, typeId: NodeId.boolean));
                    _log.d('Button ${widget.config.key} tap cancelled');
                  } catch (e) {
                    _log.e('Error writing button cancel', error: e);
                  }
                }
              },
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            // Button face
            CustomPaint(
              painter: ButtonPainter(
                color: color,
                isPressed: widget.config.isToggle ? _isToggled : _isPressed,
                buttonType: widget.config.buttonType,
              ),
            ),

            // Icon overlay (non-interactive), sized from the face
            if (widget.config.icon != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final minSide = constraints.biggest.shortestSide;
                  final faceScale =
                      (widget.config.isToggle ? _isToggled : _isPressed)
                          ? 0.95
                          : 1.0;
                  final iconSide =
                      (minSide * 0.60 * faceScale).clamp(0.0, minSide);

                  final iconCfg = widget.config.icon!;
                  final iconColor =
                      iconCfg.color ?? Theme.of(context).iconTheme.color;

                  // No Center/FittedBox/SizedBox. A plain Icon aligned by the Stack.
                  return Icon(
                    iconCfg.iconData,
                    size: iconSide,
                    color: iconColor,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stateManAsync = ref.watch(stateManProvider);

    return stateManAsync.when(
      data: (stateMan) {
        return StreamBuilder<Color>(
          stream: colorStream(stateMan),
          builder: (context, snapshot) {
            final color =
                snapshot.data ?? widget.config.outwardColor.resolve(context);
            return _buildButton(color);
          },
        );
      },
      loading: () => _buildButton(widget.config.outwardColor.resolve(context)),
      error: (_, __) => _buildButton(widget.config.outwardColor.resolve(context)),
    );
  }
}

class ButtonPainter extends CustomPainter {
  final Color color;
  final bool isPressed;
  final ButtonType buttonType;

  ButtonPainter({
    required this.color,
    this.isPressed = false,
    required this.buttonType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final borderRadius =
        Radius.circular(size.shortestSide * 0.2); // 20% like LED/conveyor

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        isPressed ? 2 : 4,
      );

    if (buttonType == ButtonType.circle) {
      canvas.drawCircle(
        center + Offset(0, isPressed ? 1 : 2),
        radius * (isPressed ? 0.9 : 1.0),
        shadowPaint,
      );
    } else {
      final shadowRect = Rect.fromCenter(
        center: center + Offset(0, isPressed ? 1 : 2),
        width: size.width * (isPressed ? 0.9 : 1.0),
        height: size.height * (isPressed ? 0.9 : 1.0),
      );
      final shadowRRect = RRect.fromRectAndRadius(shadowRect, borderRadius);
      canvas.drawRRect(shadowRRect, shadowPaint);
    }

    // Fill
    final buttonPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (buttonType == ButtonType.circle) {
      canvas.drawCircle(
        center,
        radius * (isPressed ? 0.95 : 1.0),
        buttonPaint,
      );
    } else {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * (isPressed ? 0.95 : 1.0),
        height: size.height * (isPressed ? 0.95 : 1.0),
      );
      final rrect = RRect.fromRectAndRadius(rect, borderRadius);
      canvas.drawRRect(rrect, buttonPaint);
    }

    // Border
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    if (buttonType == ButtonType.circle) {
      canvas.drawCircle(
        center,
        radius * (isPressed ? 0.95 : 1.0),
        borderPaint,
      );
    } else {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * (isPressed ? 0.95 : 1.0),
        height: size.height * (isPressed ? 0.95 : 1.0),
      );
      final rrect = RRect.fromRectAndRadius(rect, borderRadius);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(ButtonPainter oldDelegate) =>
      color != oldDelegate.color ||
      isPressed != oldDelegate.isPressed ||
      buttonType != oldDelegate.buttonType;
}

class _ConfigContent extends StatefulWidget {
  final ButtonConfig config;

  const _ConfigContent({required this.config});

  @override
  State<_ConfigContent> createState() => _ConfigContentState();
}

class _ConfigContentState extends State<_ConfigContent> {
  Future<void> _openIconEditor() async {
    // Ensure an icon exists to edit
    widget.config.icon ??= IconConfig.preview();
    // Reuse the icon asset's own configure UI in a dialog
    await showStandardDialog<void>(
      context: context,
      title: 'Button icon',
      builder: (ctx) => widget.config.icon!.configure(ctx),
    );
    setState(() {}); // Refresh after closing
  }

  @override
  Widget build(BuildContext context) {
    final hasIcon = widget.config.icon != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyField(
          initialValue: widget.config.key,
          onChanged: (value) => setState(() => widget.config.key = value),
        ),
        const SizedBox(height: 16),

        TextFormField(
          initialValue: widget.config.text,
          decoration: const InputDecoration(labelText: 'Text'),
          onChanged: (value) => setState(() => widget.config.text = value),
        ),
        const SizedBox(height: 16),

        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (c) => setState(() => widget.config.coordinates = c),
        ),
        const SizedBox(height: 16),

        // Colors
        AssetColorPickerRow(
          label: 'Outward Color',
          color: widget.config.outwardColor,
          onChanged: (value) {
            setState(() {
              widget.config.outwardColor = value;
            });
          },
        ),
        const SizedBox(height: 16),

        AssetColorPickerRow(
          label: 'Inward Color',
          color: widget.config.inwardColor,
          onChanged: (value) {
            setState(() {
              widget.config.inwardColor = value;
            });
          },
        ),
        const SizedBox(height: 16),

        // ----- Text color (optional override) -----
        //
        // Mirrors the `disabledColor` editor pattern but adds an explicit
        // Default/Custom toggle so the operator can return to the theme
        // default at any time. State is derived from `textColor == null`
        // — there is no separate `useDefaultTextColor` JSON field.
        const Text('Text Color'),
        const SizedBox(height: 4),
        SegmentedButton<_TextColorMode>(
          key: const ValueKey('text-color-mode'),
          segments: const [
            ButtonSegment(
              value: _TextColorMode.useDefault,
              label: Text('Default'),
            ),
            ButtonSegment(
              value: _TextColorMode.custom,
              label: Text('Custom'),
            ),
          ],
          selected: {
            widget.config.textColor == null
                ? _TextColorMode.useDefault
                : _TextColorMode.custom,
          },
          onSelectionChanged: (newSelection) {
            setState(() {
              if (newSelection.first == _TextColorMode.useDefault) {
                widget.config.textColor = null;
              } else {
                // Seed a sensible default so the picker has something to
                // render and the operator can immediately see the
                // selection take effect.
                widget.config.textColor ??= _defaultTextColorSeed;
              }
            });
          },
        ),
        if (widget.config.textColor != null) ...[
          const SizedBox(height: 8),
          ColorPickerRow(
            label: 'Color',
            color: widget.config.textColor,
            onChanged: (value) {
              setState(() {
                widget.config.textColor = value;
              });
            },
          ),
        ],
        const SizedBox(height: 16),

        // Text position
        DropdownButton<TextPos>(
          value: widget.config.textPos,
          isExpanded: true,
          onChanged: (value) {
            setState(() {
              widget.config.textPos = value!;
            });
          },
          items: TextPos.values
              .map(
                (e) => DropdownMenuItem<TextPos>(
                  value: e,
                  child: Text(e.name),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),

        // Button type selector
        DropdownButton<ButtonType>(
          value: widget.config.buttonType,
          isExpanded: true,
          onChanged: (value) {
            setState(() {
              widget.config.buttonType = value!;
              // If switching to circle, normalize width/height
              if (value == ButtonType.circle) {
                final avg =
                    (widget.config.size.width + widget.config.size.height) / 2;
                widget.config.size = RelativeSize(width: avg, height: avg);
              }
            });
          },
          items: ButtonType.values
              .map(
                (e) => DropdownMenuItem<ButtonType>(
                  value: e,
                  child: Text(e.name[0].toUpperCase() + e.name.substring(1)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),

        // Size controls
        Row(
          children: [
            Text(widget.config.buttonType == ButtonType.square
                ? 'Width: '
                : 'Size: '),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue:
                    (widget.config.size.width * 100).toStringAsFixed(2),
                decoration: const InputDecoration(
                  suffixText: '%',
                  isDense: true,
                  helperText: '0.01-50%',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  final widthPercent = double.tryParse(value) ?? 0.0;
                  if (widthPercent >= 0.01 && widthPercent <= 50.0) {
                    setState(() {
                      widget.config.size = RelativeSize(
                        width: widthPercent / 100,
                        height: widget.config.buttonType == ButtonType.square
                            ? widget.config.size.height
                            : widthPercent / 100,
                      );
                    });
                  }
                },
              ),
            ),
            if (widget.config.buttonType == ButtonType.square) ...[
              const SizedBox(width: 16),
              const Text('Height: '),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue:
                      (widget.config.size.height * 100).toStringAsFixed(2),
                  decoration: const InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    helperText: '0.01-50%',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final heightPercent = double.tryParse(value) ?? 0.0;
                    if (heightPercent >= 0.01 && heightPercent <= 50.0) {
                      setState(() {
                        widget.config.size = RelativeSize(
                          width: widget.config.size.width,
                          height: heightPercent / 100,
                        );
                      });
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Feedback config fields
        Row(
          children: [
            const Text('Feedback Key'),
            const SizedBox(width: 8),
            Expanded(
              child: KeyField(
                initialValue: widget.config.feedback?.key ?? '',
                onChanged: (value) {
                  setState(() {
                    widget.config.feedback ??= FeedbackConfig();
                    widget.config.feedback!.key = value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ColorPickerRow(
          label: 'Feedback Color',
          color: widget.config.feedback?.color ?? Colors.green,
          onChanged: (value) {
            setState(() {
              widget.config.feedback ??= FeedbackConfig();
              widget.config.feedback!.color = value;
            });
          },
        ),
        const SizedBox(height: 24),

        // ----- Icon (optional) -----
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show Icon'),
          value: hasIcon,
          onChanged: (v) {
            setState(() {
              widget.config.icon = v ? IconConfig.preview() : null;
            });
          },
        ),
        if (hasIcon) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Icon'),
                  onPressed: _openIconEditor,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('Remove'),
                onPressed: () => setState(() => widget.config.icon = null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Small inline preview
          SizedBox(
            width: 64,
            height: 64,
            child: IgnorePointer(
              child: IconAsset(widget.config.icon!),
            ),
          ),
        ],

        // Toggle behavior switch
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Toggle Button'),
          subtitle: const Text('Button stays pressed until tapped again'),
          value: widget.config.isToggle,
          onChanged: (value) {
            setState(() {
              widget.config.isToggle = value;
              // Reset toggle state when switching modes
              if (!value) {
                // Reset to untoggled state when switching from toggle to normal
                final buttonState =
                    context.findAncestorStateOfType<_ButtonState>();
                if (buttonState != null) {
                  buttonState.setState(() {
                    buttonState._isToggled = false;
                  });
                }
              }
            });
          },
        ),
        const SizedBox(height: 16),

        // Toggle behavior switch
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Server Writes Low'),
          subtitle: const Text('Server writes low when button is released'),
          value: widget.config.serverWritesLow,
          onChanged: (value) {
            setState(() {
              widget.config.serverWritesLow = value;
            });
          },
        ),
        const SizedBox(height: 16),

        // ----- Disabled gate (optional) -----
        const Text(
          'Disabled Gate',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bind a BOOL key whose live value makes the button '
          'non-interactive. Leave empty to keep the button always enabled.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Disabled Key'),
            const SizedBox(width: 8),
            Expanded(
              child: KeyField(
                initialValue: widget.config.disabledKey ?? '',
                onChanged: (value) {
                  setState(() {
                    widget.config.disabledKey = value.isEmpty ? null : value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Polarity — only meaningful when a key is bound, but always shown
        // so users can pre-set the intended polarity before they pick the
        // key (mirrors the SegmentedButton pattern used by Sensor).
        const Text('Disabled Polarity'),
        const SizedBox(height: 4),
        SegmentedButton<DisabledPolarity>(
          segments: const [
            ButtonSegment(
              value: DisabledPolarity.disableWhenTrue,
              label: Text('Disable when TRUE'),
            ),
            ButtonSegment(
              value: DisabledPolarity.disableWhenFalse,
              label: Text('Disable when FALSE'),
            ),
          ],
          selected: {widget.config.disabledPolarity},
          onSelectionChanged: (newSelection) {
            setState(() {
              widget.config.disabledPolarity = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 8),

        // Color swatch — only useful when a disabled key is bound (the
        // color is never rendered otherwise), so hide it in that case to
        // reduce visual noise.
        if (widget.config.disabledKey != null &&
            widget.config.disabledKey!.isNotEmpty) ...[
          ColorPickerRow(
            label: 'Disabled Color',
            color: widget.config.disabledColor,
            onChanged: (value) {
              setState(() {
                widget.config.disabledColor = value;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
