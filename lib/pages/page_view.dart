import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderConstrainedBox, BoxHitTestResult, BoxHitTestEntry;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/core/preferences.dart';
import 'package:tfc/page_creator/page.dart';

import '../chat/asset_context_menu.dart';
import '../core/feature_flags.dart';
import '../widgets/proposal_visual.dart';
import '../providers/mcp_bridge.dart' show isMcpChatAvailable;
import '../providers/page_manager.dart';
import '../providers/state_man.dart';
import '../page_creator/assets/common.dart'; // your Asset, Coordinates, RelativeSize, TextPos, etc.
import '../widgets/base_scaffold.dart';
import '../widgets/panes/side_pane.dart';
import '../widgets/zoomable_canvas.dart';

part 'page_view.g.dart';

final _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

@JsonSerializable()
class AssetStackConfig {
  bool xMirror;
  bool yMirror;
  AssetStackConfig({this.xMirror = false, this.yMirror = false});
  factory AssetStackConfig.fromJson(Map<String, dynamic> json) =>
      _$AssetStackConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AssetStackConfigToJson(this);
}

Matrix4 _buildTransform(bool xMirror, bool yMirror) {
  return Matrix4.identity()..scale(xMirror ? -1.0 : 1.0, yMirror ? -1.0 : 1.0);
}

// Conditionally wraps the editor's selection chrome in a bordered Container.
// A Container with a BoxDecoration hit-tests opaque for its full rect (even
// when only a border is set) because BoxDecoration.hitTest returns true
// inside any rectangular shape regardless of fillColor — that would swallow
// runtime-mode primary taps before they reach the asset's own
// GestureDetectors. Only paint the border when actually selected.
/// Places chrome over an asset in that asset's own rotated frame.
///
/// The asset visual rotates internally (each asset reads `coordinates.angle`),
/// so anything drawn over it -- the selection border, the AI-proposal outline
/// -- must be rotated separately or it sits askew across a turned asset. The
/// `OverflowBox` lets the unrotated size escape the parent's tight AABB
/// constraints; `Transform.rotate` also transforms hit-tests, so a
/// `GestureDetector` inside follows the rotated visual.
///
/// Shared by the selection and proposal overlays so the two cannot drift.
Widget _rotatedAssetFrame({
  required double angle,
  required double width,
  required double height,
  required Widget child,
}) {
  return OverflowBox(
    minWidth: 0,
    minHeight: 0,
    maxWidth: double.infinity,
    maxHeight: double.infinity,
    child: Transform.rotate(
      angle: angle,
      alignment: Alignment.center,
      child: SizedBox(width: width, height: height, child: child),
    ),
  );
}

Widget _wrapWithSelectionBorder({
  required bool isSelected,
  required Widget child,
}) {
  if (!isSelected) return child;
  return Container(
    // Keyed so tests can count the selection off what is actually painted
    // rather than reaching into editor state.
    key: selectionBorderKey,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.blue, width: 2),
    ),
    child: child,
  );
}

/// Marks the border drawn around a selected asset. One per selected asset.
const Key selectionBorderKey = ValueKey('asset-selection-border');

/// Computes the top-left offset for the label given the asset center, its size,
/// the label size, and the desired position.
///
/// Exposed for unit testing (regression for the inside-label bug where
/// `TextPos.inside` fell through to the right-side default).
@visibleForTesting
Offset labelOffset(
  Offset center,
  Size assetSize,
  Size textSize,
  TextPos pos, [
  double spacing = 8,
]) {
  final halfW = assetSize.width / 2;
  final halfH = assetSize.height / 2;
  switch (pos) {
    case TextPos.above:
      return Offset(
        center.dx - textSize.width / 2,
        center.dy - halfH - spacing - textSize.height,
      );
    case TextPos.below:
      return Offset(
        center.dx - textSize.width / 2,
        center.dy + halfH + spacing,
      );
    case TextPos.left:
      return Offset(
        center.dx - halfW - spacing - textSize.width,
        center.dy - textSize.height / 2,
      );
    case TextPos.inside:
      // Centre the label inside the asset's bounding rect. Used by
      // buttons / controls where the label is a face caption rather
      // than an external annotation.
      return Offset(
        center.dx - textSize.width / 2,
        center.dy - textSize.height / 2,
      );
    case TextPos.right:
      return Offset(
        center.dx + halfW + spacing,
        center.dy - textSize.height / 2,
      );
  }
}

class AssetStack extends ConsumerStatefulWidget {
  final List<Asset> assets;
  final BoxConstraints constraints;
  final void Function(Asset asset)? onTap;

  /// Double tap on an asset in edit mode. Registering it costs single taps
  /// the double-tap disambiguation window before [onTap] fires, so it is only
  /// wired up when a host actually supplies it — the runtime view never pays.
  final void Function(Asset asset)? onDoubleTap;
  final void Function(Asset asset, DragUpdateDetails details)? onPanUpdate;
  final void Function(Asset asset, DragStartDetails details)? onPanStart;

  /// Secondary tap (right-click) on an asset in edit mode. When supplied the
  /// host builds the whole context menu, so it can offer editing actions
  /// alongside the AI ones. Falls back to the AI-only menu when null.
  final void Function(Asset asset, Offset globalPosition)? onSecondaryTap;
  final bool absorb;
  final Set<Asset> selectedAssets;
  final bool mirroringDisabled;

  /// Assets that were proposed by AI. When non-empty, these assets are
  /// rendered with a dashed amber border and AI sparkle badge.
  final Set<Asset> proposedAssets;

  const AssetStack({
    Key? key,
    required this.assets,
    required this.constraints,
    this.onTap,
    this.onDoubleTap,
    this.onPanUpdate,
    this.onPanStart,
    this.onSecondaryTap,
    this.absorb = false,
    required this.selectedAssets,
    required this.mirroringDisabled,
    this.proposedAssets = const {},
  }) : super(key: key);

  @override
  ConsumerState<AssetStack> createState() => _AssetStackState();
}

/// A [SizedBox] whose hit test does not clamp to its own bounds.
///
/// Assets rotate INTERNALLY (`LayoutRotatedBox` reads `coordinates.angle`)
/// and paint out of their unrotated w×h rect into the surrounding AABB. A
/// plain [SizedBox] rejects any hit outside the unrotated rect before the
/// asset's own rotation-aware hit test can consider it, which truncated a
/// rotated asset's tappable area to the overlap sliver between the rotated
/// visual and the unrotated rect. This box lays out exactly like a
/// [SizedBox] but forwards every position to its child — the child still
/// accepts or rejects against its own (rotation-aware) geometry, so the
/// effective hit area is the visible glyph, never more.
class _HitPermissiveSizedBox extends SingleChildRenderObjectWidget {
  final double width;
  final double height;

  const _HitPermissiveSizedBox({
    required this.width,
    required this.height,
    super.child,
  });

  BoxConstraints get _additionalConstraints =>
      BoxConstraints.tightFor(width: width, height: height);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHitPermissiveConstrainedBox(
      additionalConstraints: _additionalConstraints,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHitPermissiveConstrainedBox renderObject,
  ) {
    renderObject.additionalConstraints = _additionalConstraints;
  }
}

class _RenderHitPermissiveConstrainedBox extends RenderConstrainedBox {
  _RenderHitPermissiveConstrainedBox({required super.additionalConstraints});

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Deliberately no `size.contains(position)` gate — see the widget doc.
    // The child decides; we only record ourselves on the path when it hits.
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

class _AssetStackState extends ConsumerState<AssetStack> {
  final prefs = SharedPreferencesWrapper(SharedPreferencesAsync());

  /// Read once per mount, not once per build. The stack rebuilds on every
  /// drag tick while an asset is moved, and handing FutureBuilder a fresh
  /// future each time meant a preferences read — and the extra rebuild its
  /// completion schedules — per pointer event. Nothing writes this key after
  /// startup, so a per-mount read loses nothing.
  late final Future<AssetStackConfig> _configFuture =
      prefs.getString('asset_stack_config').then((value) {
    if (value == null) {
      final cfg = AssetStackConfig();
      prefs.setString('asset_stack_config', jsonEncode(cfg.toJson()));
      return cfg;
    }
    return AssetStackConfig.fromJson(jsonDecode(value));
  });

  /// Label sizes by (text, style). Measuring text is the expensive part of
  /// laying a label out, and during a drag neither the text nor its style
  /// changes — only the position does — so the measure from the first frame
  /// serves every following tick.
  final Map<(String, TextStyle), Size> _labelSizeCache = {};

  Size _measureLabel(String text, TextStyle style) {
    if (_labelSizeCache.length > 512) _labelSizeCache.clear();
    return _labelSizeCache.putIfAbsent((text, style), () {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final size = tp.size;
      tp.dispose();
      return size;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This will trigger a rebuild when the substitutions change
    ref.watch(substitutionsChangedProvider);

    final W = widget.constraints.maxWidth;
    final H = widget.constraints.maxHeight;

    return FutureBuilder<AssetStackConfig>(
      future: _configFuture,
      builder: (context, snap) {
        final cfg = snap.data ?? AssetStackConfig();

        // Effective flags rather than writes back into cfg: the config now
        // lives for the whole mount, so a build must not edit it in place.
        final xMirror = !widget.mirroringDisabled && cfg.xMirror;
        final yMirror = !widget.mirroringDisabled && cfg.yMirror;

        // We'll accumulate all Positioned children here
        final positionedChildren = <Widget>[];

        for (final asset in widget.assets) {
          // 1) normalized coords with optional mirroring
          final fx = xMirror ? 1 - asset.coordinates.x : asset.coordinates.x;
          final fy = yMirror ? 1 - asset.coordinates.y : asset.coordinates.y;

          // 2) canvas-pixel center point
          final cx = fx * W;
          final cy = fy * H;
          final center = Offset(cx, cy);

          final assetW = asset.size.width * W;
          final assetH = asset.size.height * H;
          final assetSize = Size(assetW, assetH);
          final halfW = assetW / 2;
          final halfH = assetH / 2;

          final textScaler = TextScaler.linear(
              math.min(asset.size.width * W, asset.size.height * H) / 25);
          // Build the label style starting from the ambient DefaultTextStyle
          // and overlaying:
          //   - the scaled font size (preserves the pre-existing behaviour
          //     that labels grow with the asset's bounding box), and
          //   - the per-asset `labelColor` override when non-null
          //     (e.g. `ButtonConfig.textColor`). A null override leaves the
          //     ambient color untouched so assets without a configurable
          //     label color render byte-for-byte as before.
          final ambientStyle = DefaultTextStyle.of(context).style;
          var labelStyle = ambientStyle.copyWith(
            fontSize: textScaler.scale(ambientStyle.fontSize ?? 16),
          );
          if (asset.labelColor != null) {
            labelStyle = labelStyle.copyWith(color: asset.labelColor);
          }

          // 4) measure text size if any
          Size textSize = Size.zero;
          if (asset.text != null && asset.text!.isNotEmpty) {
            textSize = _measureLabel(asset.text!, labelStyle);
          }

          final isProposed = widget.proposedAssets.contains(asset);

          // A) add the asset widget itself
          //
          // Layering for rotation correctness:
          //   - The asset visual (asset.build) rotates internally via its
          //     own `LayoutRotatedBox`/`Transform.rotate` (each asset reads
          //     `coordinates.angle`). We do NOT wrap the visual in an outer
          //     Transform.rotate here -- that would double-rotate.
          //   - The selection-border container and the editor's
          //     GestureDetector live in a SIBLING overlay that IS wrapped
          //     in `Transform.rotate(angle, alignment: Alignment.center)`.
          //     This makes the blue selection rectangle rotate with the
          //     visual, and (because Transform.rotate transforms hit-tests
          //     by default) the GestureDetector's hit area follows the
          //     rotated visual instead of the unrotated bounding box.
          //
          // See test/page_creator/selection_rotation_test.dart for the
          // regression contract.
          final angleRadians = (asset.coordinates.angle ?? 0.0) * math.pi / 180;
          final isSelected = widget.selectedAssets.contains(asset);

          // Compute the rotated AABB (axis-aligned bounding box) so the
          // outer Positioned is large enough for taps on the rotated
          // visual to reach our hit-test subtree. Without this, Stack
          // clips hit-tests at each child's layout bounds and operator
          // clicks on the visible glyph miss when the rotation pushes
          // pixels outside the unrotated rect.
          final cosA = math.cos(angleRadians).abs();
          final sinA = math.sin(angleRadians).abs();
          final aabbW = assetW * cosA + assetH * sinA;
          final aabbH = assetW * sinA + assetH * cosA;
          final halfAabbW = aabbW / 2;
          final halfAabbH = aabbH / 2;

          positionedChildren.add(
            Positioned(
              // Keyed by identity so a z-order change (send to back / bring
              // to front) moves the existing element instead of rebuilding
              // every asset at its new index — asset subtrees hold live
              // state (subscriptions, futures) that a rebuild would restart.
              key: ObjectKey(asset),
              left: cx - halfAabbW,
              top: cy - halfAabbH,
              width: aabbW,
              height: aabbH,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // 1) The asset visual. The asset's own `build()` handles
                  //    internal rotation; wrapping it again in
                  //    `Transform.rotate(angle)` would double-rotate, so
                  //    only the mirror transform lives here. The SizedBox
                  //    keeps the unrotated visual constraints stable; the
                  //    asset's internal rotation paints out into the
                  //    surrounding AABB. `OverflowBox` lets the SizedBox
                  //    escape the Stack's tight AABB constraints (Stack
                  //    would otherwise shrink the 40x10 visual to fit the
                  //    10x40 AABB).
                  // The RepaintBoundary sits OUTSIDE the OverflowBox (sized
                  // to the AABB) rather than hugging the asset: hugging it
                  // both let the rotated overflow painting escape the
                  // boundary and clamped hit tests to the unrotated rect
                  // (RenderProxyBox.hitTest rejects positions outside its
                  // own size).
                  RepaintBoundary(
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      // NOT a plain SizedBox: a rotated asset paints out
                      // into the AABB, and a SizedBox rejects hits outside
                      // its unrotated w×h rect before the asset's
                      // rotation-aware hit test
                      // (`_RenderLayoutRotatedBox.hitTest`) gets a say —
                      // truncating a rotated sensor's tappable area to the
                      // sliver where the rotated visual and the unrotated
                      // rect overlap. The permissive box lays out
                      // identically but forwards every position to the
                      // child, which still clamps to its own (rotated)
                      // geometry.
                      child: _HitPermissiveSizedBox(
                        width: assetW,
                        height: assetH,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: asset.coordinates.angle != null
                              ? _buildTransform(xMirror, yMirror)
                              : Matrix4.identity(),
                          child: widget.absorb
                              // In editor mode the asset's own
                              // GestureDetectors must NOT fire -- the
                              // editor's overlay GestureDetector (below) is
                              // the single tap source. We use IgnorePointer
                              // because the overlay sits on top in the
                              // Stack and would otherwise compete with the
                              // asset's internal gestures.
                              // AssetEditModeScope lets assets that render
                              // nothing at runtime (idle alarm beacons) draw
                              // an editor-only placeholder instead of
                              // disappearing from the canvas.
                              ? IgnorePointer(
                                  child: AssetEditModeScope(
                                      child: asset.build(context)))
                              : asset.build(context),
                        ),
                      ),
                    ),
                  ),
                  // 2) Rotated overlay carrying the selection border and
                  //    the editor's GestureDetector. Transform.rotate
                  //    rotates BOTH the painted border AND the hit-test
                  //    region (default `transformHitTests: true`) so the
                  //    GestureDetector hit area tracks the rotated visual
                  //    instead of the unrotated bounding rect.
                  _rotatedAssetFrame(
                    angle: angleRadians,
                    width: assetW,
                    height: assetH,
                    // Container with a BoxDecoration hit-tests opaque for
                    // its full bounds even when only a border is set
                    // (BoxDecoration.hitTest returns true inside any
                    // rectangular shape regardless of fill). In runtime
                    // mode the overlay's inner GestureDetector is
                    // translucent so primary taps fall through to the
                    // asset's own GestureDetectors — but the wrapping
                    // Container would still consume the hit. Only wrap
                    // in a Container when there is an actual border to
                    // paint (i.e. when selected); otherwise the chrome
                    // is just the bare GestureDetector.
                    child: _wrapWithSelectionBorder(
                      isSelected: isSelected,
                      child: widget.absorb
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onTap != null
                                  ? () => widget.onTap!(asset)
                                  : null,
                              onDoubleTap: widget.onDoubleTap != null
                                  ? () => widget.onDoubleTap!(asset)
                                  : null,
                              onPanUpdate: widget.onPanUpdate != null
                                  ? (d) => widget.onPanUpdate!(asset, d)
                                  : null,
                              onPanStart: widget.onPanStart != null
                                  ? (details) =>
                                      widget.onPanStart!(asset, details)
                                  : null,
                              // The host's menu wins when supplied: it
                              // carries editing actions that must be
                              // reachable whether or not MCP chat is
                              // available, and folds the AI entries in
                              // itself.
                              onSecondaryTapUp: widget.onSecondaryTap != null
                                  ? (details) => widget.onSecondaryTap!(
                                        asset,
                                        details.globalPosition,
                                      )
                                  : kChatEnabled && isMcpChatAvailable()
                                      ? (details) {
                                          showEditorAssetContextMenu(
                                            context,
                                            ref,
                                            details.globalPosition,
                                            asset,
                                          );
                                        }
                                      : null,
                            )
                          : GestureDetector(
                              // Runtime view: only secondary tap is
                              // handled here (chat context menu). Primary
                              // taps must pass through to the asset's
                              // own GestureDetectors. translucent keeps
                              // us from swallowing them.
                              behavior: HitTestBehavior.translucent,
                              onSecondaryTapUp:
                                  kChatEnabled && isMcpChatAvailable()
                                      ? (details) {
                                          showAssetContextMenu(
                                            context,
                                            details.globalPosition,
                                            () => debugAsset(ref, asset),
                                          );
                                        }
                                      : null,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );

          // Proposal visual indicators: dashed border + AI badge
          if (isProposed) {
            positionedChildren.add(
              Positioned(
                // Sized to the rotated AABB, like the asset's own Positioned.
                // _rotatedAssetFrame uses an OverflowBox, which needs bounded
                // constraints to size against -- on a left/top-only Positioned
                // it receives unbounded ones and paints nothing.
                left: cx - halfAabbW,
                top: cy - halfAabbH,
                width: aabbW,
                height: aabbH,
                child: IgnorePointer(
                  // Rotate with the asset, exactly as the blue selection
                  // border does (see the layering note above). Drawn
                  // unrotated, the dashed box sat askew across a turned
                  // conveyor and read as marking the wrong thing.
                  child: _rotatedAssetFrame(
                    angle: angleRadians,
                    width: assetW,
                    height: assetH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: Size(assetW, assetH),
                          painter: DashedBorderPainter(color: Colors.amber),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          // The frame turns with the asset; the badge is a
                          // label and stays upright so it is still readable
                          // on a rotated or upside-down asset.
                          child: Transform.rotate(
                            angle: -angleRadians,
                            alignment: Alignment.center,
                            child: const ProposalBadge(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          // B) add the label (if any)
          if (asset.text != null && asset.text!.isNotEmpty) {
            var pos = asset.textPos ?? TextPos.right;
            if (xMirror && (pos == TextPos.left || pos == TextPos.right)) {
              pos = pos == TextPos.left ? TextPos.right : TextPos.left;
            }
            if (yMirror && (pos == TextPos.above || pos == TextPos.below)) {
              pos = pos == TextPos.above ? TextPos.below : TextPos.above;
            }
            final labelOff = labelOffset(center, assetSize, textSize, pos);
            // The label `Positioned` is added AFTER the asset visual in
            // `positionedChildren`, so it paints (and hit-tests) on TOP
            // of the asset. If the label is allowed to consume primary
            // pointer events, it eats taps that should reach the asset's
            // own GestureDetectors / InkWell underneath — most visibly
            // for a Button with `TextPos.inside`.
            //
            // In editor mode (`absorb=true`) we wrap the label in
            // `IgnorePointer` so the editor's overlay GestureDetector
            // sitting beneath gets every event (drag / select / context
            // menu) — otherwise an asset whose label overlaps its body
            // can't be moved.
            //
            // In runtime mode (`absorb=false`) we keep the secondary-tap
            // (right-click → AI context menu) binding so operators can
            // open the AI menu by right-clicking the label, but we wrap
            // the underlying Text in `IgnorePointer` so it does not
            // hit-test for primary taps. Combined with
            // `HitTestBehavior.translucent` on the wrapping
            // GestureDetector, primary taps on the label fall through to
            // the asset body below (Stack hit-testing visits earlier
            // children when a translucent detector reports a hit but has
            // no matching gesture handler).
            final labelWidget = widget.absorb
                ? IgnorePointer(child: Text(asset.text!, style: labelStyle))
                : GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onSecondaryTapUp: kChatEnabled && isMcpChatAvailable()
                        ? (details) {
                            showAssetContextMenu(
                              context,
                              details.globalPosition,
                              () => debugAsset(ref, asset),
                            );
                          }
                        : null,
                    child: IgnorePointer(
                      child: Text(asset.text!, style: labelStyle),
                    ),
                  );
            positionedChildren.add(
              Positioned(
                left: labelOff.dx,
                top: labelOff.dy,
                child: labelWidget,
              ),
            );
          }

          // C) add the red center dot
          // positionedChildren.add(
          //   Positioned(
          //     left: cx - 4,
          //     top: cy - 4,
          //     child: Container(
          //       width: 8,
          //       height: 8,
          //       decoration: BoxDecoration(
          //         color: Colors.red,
          //         shape: BoxShape.circle,
          //       ),
          //     ),
          //   ),
          // );
        }

        return Stack(
          fit: StackFit.expand,
          children: positionedChildren,
        );
      },
    );
  }
}

class AssetView extends ConsumerWidget {
  final String pageName;
  const AssetView({Key? key, required this.pageName}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseScaffold(
      title: 'Asset View',
      // An equipment pane (a tapped conveyor, a sensor) docks over the right
      // edge; the inset re-fits the plant view beside it so the very device
      // the operator tapped is never hidden behind its own pane.
      body: SidePaneInset(
          child: ZoomableCanvas(
        child: LayoutBuilder(
          builder: (context, constraints) => FutureBuilder<PageManager>(
            future: ref.watch(pageManagerProvider.future),
            builder: (context, snap) {
              final pageManager = snap.data;
              if (pageManager == null) {
                return const SizedBox.shrink();
              }
              if (pageManager.pages[pageName] == null) {
                return Center(
                  child: Text('Page: "$pageName" not found'),
                );
              }
              return AssetStack(
                assets: pageManager.pages[pageName]?.assets ?? [],
                constraints: constraints,
                absorb: false,
                selectedAssets: const {},
                mirroringDisabled:
                    pageManager.pages[pageName]?.mirroringDisabled ?? false,
              );
            },
          ),
        ),
      )),
    );
  }
}
