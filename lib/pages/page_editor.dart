import 'dart:async';
import 'dart:convert';
import 'package:tfc/widgets/panes/standard_dialog.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/providers/page_manager.dart';
import '../page_creator/asset_update.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/editor_clipboard.dart';
import '../page_creator/assets/image.dart';
import '../page_creator/assets/image_store.dart';
import '../page_creator/assets/registry.dart';
import '../providers/page_images.dart';
import '../widgets/base_scaffold.dart';
import 'page_view.dart';
import '../widgets/zoomable_canvas.dart';
import '../widgets/panes/pane_chrome.dart' show PaneAction;
import '../widgets/panes/side_pane.dart';
import '../page_creator/page.dart';
import '../models/menu_item.dart';
import '../route_registry.dart';
import '../routes.dart';
import '../providers/current_page_assets.dart';
import '../tech_docs/tech_doc_picker.dart';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import '../chat/ai_context_action.dart';
import '../chat/asset_context_menu.dart' show buildEditorAssetMenuItems;
import '../core/feature_flags.dart';
import '../providers/mcp_bridge.dart' show isMcpChatAvailable;
import '../chat/chat_overlay.dart' show ChatContext;
import '../chat/hamburger_context_menu.dart';
import '../chat/page_context_menu.dart';
import '../chat/palette_context_menu.dart';
import '../widgets/proposal_visual.dart';
import '../providers/proposal_state.dart';
import 'package:flutter/services.dart';

/// Hit-tests whether a pointer position falls inside an asset's rotated
/// visual rect. The marquee gate uses this to decide between starting a
/// drag-selection rubber band (pointer down on empty canvas) and dragging
/// an asset (pointer down on an asset). An unrotated AABB test would fail
/// in both directions for any asset with a non-zero `angle`.
///
/// `pointer` is in the editor canvas's local coordinate system.
/// `cx`, `cy` are the asset centre in the same system.
/// `halfW`, `halfH` are the asset's unrotated half-extents.
/// `angleDegrees` is the asset's rotation in degrees (matches
/// `Coordinates.angle`).
@visibleForTesting
bool marqueeHitTestRotatedAsset({
  required Offset pointer,
  required double cx,
  required double cy,
  required double halfW,
  required double halfH,
  required double angleDegrees,
}) {
  final dx = pointer.dx - cx;
  final dy = pointer.dy - cy;
  final angleRad = angleDegrees * math.pi / 180;
  // Apply the inverse rotation (-angle) to project the pointer into the
  // asset's unrotated local frame, then test the half-extents.
  final cosA = math.cos(-angleRad);
  final sinA = math.sin(-angleRad);
  final localDx = dx * cosA - dy * sinA;
  final localDy = dx * sinA + dy * cosA;
  return localDx.abs() <= halfW && localDy.abs() <= halfH;
}

/// Reorders [assets] so that [targets] sit beneath everything else.
///
/// Paint order is list order — `AssetStack` renders assets in sequence, so the
/// head of the list is the back of the stack. Members of [targets] keep their
/// own relative stacking; only their position relative to the rest changes.
///
/// Returns a new list; [assets] is not modified. Generic so the ordering can
/// be tested without building real assets.
@visibleForTesting
List<T> sendToBackOrder<T>(List<T> assets, Set<T> targets) {
  final moving = <T>[];
  final rest = <T>[];
  for (final asset in assets) {
    (targets.contains(asset) ? moving : rest).add(asset);
  }
  return [...moving, ...rest];
}

/// Reorders [assets] so that [targets] sit on top of everything else — the
/// mirror image of [sendToBackOrder]. Members of [targets] keep their own
/// relative stacking; only their position relative to the rest changes.
///
/// Returns a new list; [assets] is not modified.
@visibleForTesting
List<T> bringToFrontOrder<T>(List<T> assets, Set<T> targets) {
  final moving = <T>[];
  final rest = <T>[];
  for (final asset in assets) {
    (targets.contains(asset) ? moving : rest).add(asset);
  }
  return [...rest, ...moving];
}

/// Whether [targets] already occupy the back of the stack, i.e. the leading
/// run of [assets]. Empty or absent targets count as already-at-back, since
/// there is nothing to move.
@visibleForTesting
bool isAlreadyAtBack<T>(List<T> assets, Set<T> targets) {
  var seen = 0;
  for (var i = 0; i < assets.length; i++) {
    if (targets.contains(assets[i])) {
      // Out of the leading run: something else is already below it.
      if (i != seen) return false;
      seen++;
    }
  }
  return true;
}

/// Whether [targets] already occupy the front of the stack, i.e. the trailing
/// run of [assets]. Empty or absent targets count as already-at-front, since
/// there is nothing to move. Mirrors [isAlreadyAtBack].
@visibleForTesting
bool isAlreadyAtFront<T>(List<T> assets, Set<T> targets) {
  var seen = 0;
  for (var i = assets.length - 1; i >= 0; i--) {
    if (targets.contains(assets[i])) {
      // Out of the trailing run: something else is already above it.
      if (i != assets.length - 1 - seen) return false;
      seen++;
    }
  }
  return true;
}

/// One asset's placement on the canvas, in the normalized 0..1 units the
/// editor stores. Exists so [rotateGroup] can be exercised — and reasoned
/// about — without building real assets.
@visibleForTesting
@immutable
class AssetPlacement {
  const AssetPlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.angle,
  });

  /// Centre point, as a fraction of the canvas (matches `Coordinates`).
  final double x;
  final double y;

  /// Extents, as a fraction of the canvas (matches `RelativeSize`).
  final double width;
  final double height;

  /// Rotation in degrees, clockwise on screen. Null means "never rotated";
  /// [rotateGroup] preserves that distinction because `AssetStack` only
  /// applies the page's mirror transform to assets with a non-null angle.
  final double? angle;

  @override
  String toString() =>
      'AssetPlacement(x: $x, y: $y, width: $width, height: $height, '
      'angle: $angle)';
}

/// Normalizes an angle in degrees to [0, 360).
double _normalizeAngle(double degrees) {
  final wrapped = degrees % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

/// cos/sin packed as (dx, dy), exact for quarter turns.
///
/// `math.cos(pi / 2)` is 6.1e-17, not 0, so a nominally rigid 90° turn would
/// leak a little of each axis into the other — a systematic error that repeats
/// in the same direction every rotation. The quarter turns are the only
/// rotations the editor's menu offers, so they are table lookups rather than
/// trig. Rounding in the surrounding arithmetic still costs an ulp or so per
/// turn; this only removes the part that would accumulate.
Offset _rotationFactors(double degrees) {
  final normalized = _normalizeAngle(degrees);
  if (normalized == 0) return const Offset(1, 0);
  if (normalized == 90) return const Offset(0, 1);
  if (normalized == 180) return const Offset(-1, 0);
  if (normalized == 270) return const Offset(0, -1);
  final radians = normalized * math.pi / 180;
  return Offset(math.cos(radians), math.sin(radians));
}

/// Rotates [placements] as one rigid group about the centre of their combined
/// bounding box: every asset both spins on its own centre and orbits the
/// group's, the way a selection rotates in a drawing tool.
///
/// [degrees] is clockwise on screen, matching `Coordinates.angle` and
/// `Transform.rotate`.
///
/// [aspectRatio] is the canvas's width / height. It is required because x and
/// y are normalized independently against a canvas that is not square — a
/// rotation applied directly to normalized coordinates would shear the group.
/// The maths therefore runs in units of canvas height (x scaled by
/// [aspectRatio]) and converts back at the end.
///
/// The bounding box is built from each asset's *rotated* extents, so a quarter
/// turn maps the box onto itself and the group's centre stays put. Combined
/// with the exact quarter-turn factors above, that makes CW-then-CCW a round
/// trip to within a rounding ulp, with no direction the error can accumulate
/// in.
///
/// A group that would leave the canvas is translated back in as a unit rather
/// than clamped per asset, which would collapse the layout. A group too large
/// to fit is aligned to the top/left edge and may overhang; as a last resort
/// centres are clamped into 0..1 so no asset ends up unreachable off-canvas.
///
/// Half-extents of an asset's axis-aligned bounding box once its own rotation
/// is applied — the same formula `AssetStack` uses to size the Positioned that
/// holds a rotated visual. In units of canvas height, so [aspect] scales the
/// width in and the caller divides x back out.
///
/// Uses the exact quarter-turn factors rather than raw trig for the same
/// reason the orbit in [rotateGroup] does: the box decides where the group
/// centre sits, so noise here would drift the whole selection.
Offset _halfExtents(double width, double height, double? angle, double aspect) {
  final factors = _rotationFactors(angle ?? 0.0);
  final cosA = factors.dx.abs();
  final sinA = factors.dy.abs();
  final halfW = width * aspect / 2;
  final halfH = height / 2;
  return Offset(halfW * cosA + halfH * sinA, halfW * sinA + halfH * cosA);
}

/// Returns a new list positionally matching [placements]; nothing is mutated.
@visibleForTesting
List<AssetPlacement> rotateGroup({
  required List<AssetPlacement> placements,
  required double degrees,
  required double aspectRatio,
}) {
  if (placements.isEmpty) return const [];
  // A degenerate canvas has no meaningful aspect; fall back to square rather
  // than producing NaN coordinates.
  final aspect = (aspectRatio.isFinite && aspectRatio > 0) ? aspectRatio : 1.0;

  Offset halfExtents(double width, double height, double? angle) =>
      _halfExtents(width, height, angle, aspect);

  // 1) Bounding box of the selection, in canvas-height units.
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final p in placements) {
    final half = halfExtents(p.width, p.height, p.angle);
    minX = math.min(minX, p.x * aspect - half.dx);
    maxX = math.max(maxX, p.x * aspect + half.dx);
    minY = math.min(minY, p.y - half.dy);
    maxY = math.max(maxY, p.y + half.dy);
  }
  final centreX = (minX + maxX) / 2;
  final centreY = (minY + maxY) / 2;

  // 2) Orbit each centre about the group centre and spin the asset itself.
  final factors = _rotationFactors(degrees);
  final rotated = <AssetPlacement>[];
  for (final p in placements) {
    final dx = p.x * aspect - centreX;
    final dy = p.y - centreY;
    final newAngle = _normalizeAngle((p.angle ?? 0.0) + degrees);
    rotated.add(AssetPlacement(
      x: (centreX + dx * factors.dx - dy * factors.dy) / aspect,
      y: centreY + dx * factors.dy + dy * factors.dx,
      width: p.width,
      height: p.height,
      // Back at zero means back to null. AssetStack skips the page's mirror
      // transform for a null angle, so rotating a selection and rotating it
      // back has to restore the null or the visual would start flipping on
      // mirrored pages — a no-op round trip must really be a no-op. The cost
      // is that an angle stored explicitly as 0 collapses to null.
      angle: newAngle == 0 ? null : newAngle,
    ));
  }

  // 3) Translate the group back onto the canvas if the rotation pushed it off.
  var shiftX = 0.0;
  var shiftY = 0.0;
  var rMinX = double.infinity;
  var rMinY = double.infinity;
  var rMaxX = double.negativeInfinity;
  var rMaxY = double.negativeInfinity;
  for (final p in rotated) {
    final half = halfExtents(p.width, p.height, p.angle);
    rMinX = math.min(rMinX, p.x * aspect - half.dx);
    rMaxX = math.max(rMaxX, p.x * aspect + half.dx);
    rMinY = math.min(rMinY, p.y - half.dy);
    rMaxY = math.max(rMaxY, p.y + half.dy);
  }
  // Pull the leading edge in first, so an oversized group overhangs the
  // bottom/right rather than the top/left where it is harder to grab.
  if (rMaxX > aspect) shiftX = aspect - rMaxX;
  if (rMinX + shiftX < 0) shiftX = -rMinX;
  if (rMaxY > 1) shiftY = 1 - rMaxY;
  if (rMinY + shiftY < 0) shiftY = -rMinY;

  if (shiftX == 0 && shiftY == 0) return rotated;
  return [
    for (final p in rotated)
      AssetPlacement(
        x: (p.x + shiftX / aspect).clamp(0.0, 1.0),
        y: (p.y + shiftY).clamp(0.0, 1.0),
        width: p.width,
        height: p.height,
        angle: p.angle,
      ),
  ];
}

/// Translates [placements] as a rigid group so the centre of their combined
/// bounding box lands on ([targetX], [targetY]), both in 0..1 canvas
/// fractions. Backs the context menu's "Paste here".
///
/// Same conventions as [rotateGroup]: extents are measured with each asset's
/// own rotation applied, the maths runs in canvas-height units so a wide
/// canvas does not skew the drop, and a group that would overhang the canvas
/// is pulled back on as a unit — leading edge first, so one too large to fit
/// overhangs the bottom/right — with a final per-centre clamp so no asset
/// ends up unreachable off-canvas.
@visibleForTesting
List<AssetPlacement> placeGroupAt({
  required List<AssetPlacement> placements,
  required double targetX,
  required double targetY,
  required double aspectRatio,
}) {
  if (placements.isEmpty) return const [];
  // A degenerate canvas has no meaningful aspect; fall back to square rather
  // than producing NaN coordinates.
  final aspect = (aspectRatio.isFinite && aspectRatio > 0) ? aspectRatio : 1.0;

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final p in placements) {
    final half = _halfExtents(p.width, p.height, p.angle, aspect);
    minX = math.min(minX, p.x * aspect - half.dx);
    maxX = math.max(maxX, p.x * aspect + half.dx);
    minY = math.min(minY, p.y - half.dy);
    maxY = math.max(maxY, p.y + half.dy);
  }

  var shiftX = targetX.clamp(0.0, 1.0) * aspect - (minX + maxX) / 2;
  var shiftY = targetY.clamp(0.0, 1.0) - (minY + maxY) / 2;

  if (maxX + shiftX > aspect) shiftX = aspect - maxX;
  if (minX + shiftX < 0) shiftX = -minX;
  if (maxY + shiftY > 1) shiftY = 1 - maxY;
  if (minY + shiftY < 0) shiftY = -minY;

  return [
    for (final p in placements)
      AssetPlacement(
        x: (p.x + shiftX / aspect).clamp(0.0, 1.0),
        y: (p.y + shiftY).clamp(0.0, 1.0),
        width: p.width,
        height: p.height,
        angle: p.angle,
      ),
  ];
}

/// Which way a selection is flipped.
enum MirrorAxis {
  /// Left becomes right: assets swap sides across a vertical line through the
  /// selection's centre.
  horizontal,

  /// Top becomes bottom: assets swap across a horizontal line through it.
  vertical,
}

/// Reflects [placements] about the centre of their combined bounding box.
///
/// Both the layout and each asset's own orientation are reflected, the way a
/// selection flips in a drawing tool: a line of assets comes back in the
/// opposite order, and one that was leaning right leans left.
///
/// The angle is reflected rather than the artwork, because an asset has no
/// per-asset mirror flag to set — only the page-wide one in `AssetStackConfig`.
/// For the equipment these pages are made of, whose glyphs are symmetric about
/// their own long axis, reflecting the angle is the same picture. It is not
/// for a chiral glyph, which comes back rotated rather than mirrored.
///
/// One consequence worth knowing before reaching for this: a horizontal flip
/// maps angle 0 to 180, so assets that were never rotated come back explicitly
/// upside down. A vertical flip maps 0 to 0 and leaves them alone.
///
/// [aspectRatio] is the canvas's width / height, needed for the same reason
/// [rotateGroup] needs it — x and y are normalized against a canvas that is
/// not square, so a rotated asset's bounding box cannot be measured without
/// it. The reflection itself acts on one axis at a time and so cannot shear.
///
/// Nothing can leave the canvas: reflecting an angle leaves |cos| and |sin|
/// unchanged, so every asset's bounding box keeps its size and the group's box
/// maps exactly onto itself.
///
/// Returns a new list positionally matching [placements]; nothing is mutated.
@visibleForTesting
List<AssetPlacement> mirrorGroup({
  required List<AssetPlacement> placements,
  required MirrorAxis axis,
  required double aspectRatio,
}) {
  if (placements.isEmpty) return const [];
  final aspect = (aspectRatio.isFinite && aspectRatio > 0) ? aspectRatio : 1.0;

  // Bounding box of the selection, in canvas-height units — the same box
  // rotateGroup turns about.
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final p in placements) {
    final half = _halfExtents(p.width, p.height, p.angle, aspect);
    minX = math.min(minX, p.x * aspect - half.dx);
    maxX = math.max(maxX, p.x * aspect + half.dx);
    minY = math.min(minY, p.y - half.dy);
    maxY = math.max(maxY, p.y + half.dy);
  }
  final centreX = (minX + maxX) / 2;
  final centreY = (minY + maxY) / 2;

  return [
    for (final p in placements)
      () {
        final angle = p.angle ?? 0.0;
        // Screen axes: x right, y down, angle clockwise, so an asset points
        // along (cos a, sin a). Reflecting x gives (-cos a, sin a), which is
        // the direction at 180 - a; reflecting y gives (cos a, -sin a), which
        // is -a.
        final newAngle = _normalizeAngle(
          axis == MirrorAxis.horizontal ? 180 - angle : -angle,
        );
        return AssetPlacement(
          x: axis == MirrorAxis.horizontal
              ? ((2 * centreX - p.x * aspect) / aspect).clamp(0.0, 1.0)
              : p.x,
          y: axis == MirrorAxis.vertical
              ? (2 * centreY - p.y).clamp(0.0, 1.0)
              : p.y,
          width: p.width,
          height: p.height,
          // Back at zero means back to null, for the reason spelled out in
          // rotateGroup: AssetStack skips the page's mirror transform for a
          // null angle, so a round trip has to restore it.
          angle: newAngle == 0 ? null : newAngle,
        );
      }(),
  ];
}

/// The axis a selection is lined up along.
enum AlignAxis {
  /// Assets end up in a horizontal row: one shared y, x untouched.
  horizontal,

  /// Assets end up in a vertical column: one shared x, y untouched.
  vertical,
}

/// The coordinate [axis] alignment moves, for each of [placements].
Iterable<double> _alignedCoordinates(
        List<AssetPlacement> placements, AlignAxis axis) =>
    placements.map((p) => axis == AlignAxis.horizontal ? p.y : p.x);

/// Lines [placements] up on [axis], moving every asset's centre onto the
/// midpoint between the two outermost centres.
///
/// Centres, not edges: assets of different sizes end up with their middles on
/// one line and their edges ragged. That is what makes this the one selection
/// action that needs no canvas aspect ratio — it writes a constant into a
/// single normalized axis and leaves the other alone, so there is no
/// cross-axis maths to get wrong.
///
/// The line is the midpoint of the extremes rather than the mean, matching
/// what a drawing tool does: the two outermost assets move symmetrically
/// toward each other instead of the line being dragged around by whichever
/// side happens to be crowded.
///
/// Returns a new list positionally matching [placements]; nothing is mutated.
@visibleForTesting
List<AssetPlacement> alignGroup({
  required List<AssetPlacement> placements,
  required AlignAxis axis,
}) {
  if (placements.isEmpty) return const [];

  final coordinates = _alignedCoordinates(placements, axis);
  final line =
      (coordinates.reduce(math.min) + coordinates.reduce(math.max)) / 2;

  return [
    for (final p in placements)
      AssetPlacement(
        x: axis == AlignAxis.vertical ? line : p.x,
        y: axis == AlignAxis.horizontal ? line : p.y,
        width: p.width,
        height: p.height,
        angle: p.angle,
      ),
  ];
}

/// Whether [placements] already sit on one line along [axis], so the menu
/// entry can be disabled rather than pushing a no-op onto the undo history.
///
/// Exact equality is the right test, not a tolerance: [alignGroup] writes the
/// identical value into every asset, so a selection it has just aligned reads
/// back as aligned. Fewer than two assets have nothing to line up.
@visibleForTesting
bool isAlreadyAligned(List<AssetPlacement> placements, AlignAxis axis) {
  if (placements.length < 2) return true;
  final coordinates = _alignedCoordinates(placements, axis);
  return coordinates.every((c) => c == coordinates.first);
}

/// Projects a drag delta from the rotated GestureDetector's local frame
/// back into the canvas (parent) frame. The editor's per-asset
/// GestureDetector lives inside `Transform.rotate(angleRadians)` (so the
/// hit area follows the rotated visual), which means `DragUpdateDetails.delta`
/// is also expressed in that rotated frame — a screen-right drag at angle
/// 90° arrives as local-down. This helper rotates the delta back so the
/// editor can apply it to the asset's canvas-space coordinates directly.
///
/// For `angleDegrees == 0` the rotation is identity and the returned offset
/// equals the input.
@visibleForTesting
Offset projectDragDeltaToCanvas({
  required Offset delta,
  required double angleDegrees,
}) {
  final angleRad = angleDegrees * math.pi / 180;
  final cosA = math.cos(angleRad);
  final sinA = math.sin(angleRad);
  return Offset(
    delta.dx * cosA - delta.dy * sinA,
    delta.dx * sinA + delta.dy * cosA,
  );
}

class PageEditor extends ConsumerStatefulWidget {
  /// Optional proposal JSON passed via Beamer route data.
  /// When non-null, the editor pre-populates from the proposal instead of
  /// loading only from [pageManagerProvider].
  final String? proposalData;

  const PageEditor({super.key, this.proposalData});

  @override
  ConsumerState<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<PageEditor> {
  final List<Map<String, AssetPage>> _undoHistory = [];
  bool _showPalette = false;

  /// True while the pan key is held. The editor has one mode: a drag on empty
  /// canvas rubber-bands a selection, and this is what temporarily turns that
  /// drag back into a canvas pan.
  ///
  /// There is nothing to pan at 1:1 — `ZoomableCanvas` has `minScale: 1.0` and
  /// no boundary margin, so the child exactly fills the viewport — which is
  /// why panning can afford to be the held-key gesture and marquee the plain
  /// one, rather than the other way round.
  bool _isPanKeyHeld = false;

  Offset? _selectionStart;
  Offset? _selectionCurrent;
  Set<Asset> _selectedAssets = {};

  /// True between an asset's pan start and the following pointer up, so a drag
  /// that began on an asset cannot also grow a marquee behind it.
  bool _isDraggingAsset = false;

  /// The canvas's last laid-out constraints. The keyboard handler sits above
  /// the `LayoutBuilder`, and [_rotateAssets] needs the aspect ratio, so the
  /// builder leaves it here on the way past.
  BoxConstraints? _canvasConstraints;

  /// The shortcut handler's own focus. `autofocus` arms it once at mount, but
  /// focus wanders: the config pane docks in the root overlay — outside this
  /// page's Focus subtree — and a text field there keeps keyboard focus until
  /// something takes it back, leaving every canvas shortcut dead. Clicking the
  /// canvas re-arms it (see the Listener around [ZoomableCanvas]).
  final FocusNode _shortcutFocus =
      FocusNode(debugLabel: 'PageEditor shortcuts');
  String? _copiedAssets;
  Map<String, AssetPage> _temporaryPages = {};
  String? _currentPage;

  /// Working copy of [PageManager.topLevelOrder]: the full top level — pages
  /// and app-registered destinations alike — as arranged in the Pages dialog.
  List<String> _topLevelOrder = [];

  /// True when [_topLevelOrder] differs from what was loaded. Tracked apart
  /// from [_hasUnsavedChanges]'s JSON compare because app-registered items are
  /// not part of the pages JSON at all.
  bool _navOrderDirty = false;

  /// Backs the palette's search box. A controller rather than a bare string:
  /// the palette is torn down whenever it is closed, and a controller-less
  /// TextField would come back empty while the remembered query kept
  /// filtering the grid.
  final TextEditingController _paletteSearchController =
      TextEditingController();
  String _savedJson = '';
  String _currentJson = '';

  /// Path of the tree row currently being dragged in the Pages dialog, so the
  /// drop zones can show whether they would take it.
  String? _dragPagePath;

  /// The Pages dialog's scrolling tree, driven directly while a row is dragged
  /// near an edge — Draggable does not scroll its parent list on its own, so
  /// without this a destination off screen could not be reached.
  final ScrollController _treeScrollController = ScrollController();
  final GlobalKey _treeViewportKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollStep = 0;

  /// True when the editor was opened with AI proposal data that has not yet
  /// been saved by the operator.
  bool _isProposal = false;
  String? _proposalTitle;
  int? _proposalId;

  /// Assets that were added by the AI proposal (for visual indicators).
  Set<Asset> _proposedAssets = {};

  /// Snapshot of pages before proposal was applied (for reject/revert).
  Map<String, AssetPage>? _preProposalPages;

  /// The asset whose configuration pane is docked open, if any. The pane is
  /// non-modal, so the canvas keeps taking taps and drags while it is up and
  /// tapping another asset just re-points the pane at it.
  Asset? _configAsset;

  /// Drives [_syncConfigEdits]. Config editors mutate their asset in place and
  /// rebuild only themselves, so this is the editor's only general signal that
  /// something in the pane changed — see [_assetSnapshot].
  Timer? _configWatch;
  String? _configSnapshot;

  /// How often the open pane is compared against the canvas. Short enough that
  /// typing reads as live; pointer events sync straight away regardless.
  static const Duration _configWatchInterval = Duration(milliseconds: 100);

  /// Wider than an equipment pane: asset config editors are dense forms, and
  /// several were written against a full-screen dialog. The pane carries a
  /// resize handle, and this follows it — a composite device (a Beckhoff bus
  /// coupler, an Advantys head) wants a lot more room than an LED, and the
  /// width you drag it to is the one the next asset opens at.
  double _configPaneWidth = 520;

  /// Matches the pane's own slide, so the canvas chrome moves with it rather
  /// than jumping ahead of it.
  static const Duration _configPaneSlide = Duration(milliseconds: 220);

  /// How far the canvas's right-hand chrome — the page selector and the mode
  /// buttons — steps aside so the open pane does not sit on top of it.
  double get _rightChromeInset =>
      _configAsset == null ? 0 : _configPaneWidth + SidePaneDefaults.margin;

  List<Asset> get assets {
    if (_currentPage == null) {
      return [];
    }
    if (_temporaryPages[_currentPage] == null) {
      return [];
    }
    return _temporaryPages[_currentPage]!.assets;
  }

  @override
  void initState() {
    super.initState();
    ref.read(pageManagerProvider.future).then((pageManager) {
      setState(() {
        _temporaryPages = pageManager.copyWith().pages;
        _topLevelOrder = List.of(pageManager.topLevelOrder);
        _currentPage = pageManager.pages.keys.firstOrNull;

        // Apply proposal data if present.
        _applyProposalData(widget.proposalData);

        _updateCurrentJson();
        _savedJson =
            _isProposal ? '' : _currentJson; // Mark unsaved if proposal
      });
    });
  }

  @override
  void dispose() {
    _stopAutoScroll();
    // The pane lives in the root overlay, so nothing else tears it down when
    // the editor goes away (an MCP proposal can navigate out from under it).
    _configWatch?.cancel();
    _configWatch = null;
    final configAsset = _configAsset;
    if (configAsset != null) closeSidePane(id: _configPaneId(configAsset));
    _treeScrollController.dispose();
    _paletteSearchController.dispose();
    _shortcutFocus.dispose();
    super.dispose();
  }

  /// Parses proposal JSON and merges it into [_temporaryPages].
  ///
  /// For `_proposal_type: 'page'`: expects keys like `title`, `key`, `assets`,
  /// `mirroring_disabled`. Creates or replaces a page entry.
  ///
  /// For `_proposal_type: 'asset'`: expects `key`, `title`, `children` (list
  /// of asset JSON). Adds assets to the page identified by `key`, or creates
  /// a new page.
  void _applyProposalData(String? proposalJson) {
    if (proposalJson == null) return;

    // Store pre-proposal snapshot for reject/revert.
    _preProposalPages = PageManager.copyPages(_temporaryPages);

    try {
      final Map<String, dynamic> proposal;
      final decoded = jsonDecode(proposalJson);
      if (decoded is Map<String, dynamic>) {
        proposal = decoded;
      } else {
        return;
      }

      final type = proposal['_proposal_type'] as String?;
      if (type == null) return;

      // Try to match proposal to universal state for ID tracking.
      try {
        final state = ref.read(proposalStateProvider);
        for (final p in state.proposals) {
          if (p.proposalJson == proposalJson) {
            _proposalId = p.id;
            break;
          }
        }
      } catch (_) {}

      if (type == 'page') {
        _applyPageProposal(proposal);
      } else if (type == 'asset') {
        _applyAssetProposal(proposal);
      } else if (type == 'asset_update') {
        _applyUpdateProposal(proposal);
      }
    } catch (_) {
      // Best-effort: if proposal JSON is malformed, ignore it.
    }
  }

  void _applyPageProposal(Map<String, dynamic> proposal) {
    final title = proposal['title'] as String? ?? 'AI Proposal';
    final key = proposal['key'] as String? ?? '/$title';
    final mirroringDisabled = proposal['mirroring_disabled'] as bool? ?? false;

    List<Asset> assets = [];
    if (proposal['assets'] is List) {
      final items = proposal['assets'] as List;
      // Try full parse first (works when JSON has all required fields).
      try {
        final parsed = AssetRegistry.parse({'assets': items});
        if (parsed.isNotEmpty) {
          assets = parsed;
        }
      } catch (_) {}
      // Fallback: create default assets by type name for minimal MCP JSON.
      if (assets.isEmpty) {
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final assetName =
              item['asset_name'] as String? ?? item['asset_type'] as String?;
          if (assetName == null) continue;
          final asset = AssetRegistry.createDefaultAssetByName(assetName);
          if (asset == null) continue;
          if (item['key'] is String) {
            try {
              (asset as dynamic).key = item['key'] as String;
            } catch (_) {}
          }
          final label = item['title'] as String? ??
              item['label'] as String? ??
              item['text'] as String?;
          if (label != null) {
            asset.text = label;
            asset.textPos ??= TextPos.below;
          }
          if (item['coordinates'] is Map<String, dynamic>) {
            final c = item['coordinates'] as Map<String, dynamic>;
            asset.coordinates = Coordinates(
              x: (c['x'] as num?)?.toDouble() ?? 0.0,
              y: (c['y'] as num?)?.toDouble() ?? 0.0,
            );
          } else if (item['x'] is num || item['y'] is num) {
            asset.coordinates = Coordinates(
              x: (item['x'] as num?)?.toDouble() ?? 0.1,
              y: (item['y'] as num?)?.toDouble() ?? 0.1,
            );
          }
          assets.add(asset);
        }
      }
    }

    final page = AssetPage(
      menuItem: MenuItem(label: title, path: key, icon: Icons.auto_awesome),
      assets: assets,
      mirroringDisabled: mirroringDisabled,
    );

    _temporaryPages[key] = page;
    _currentPage = key;
    _isProposal = true;
    _proposalTitle = title;
    _proposedAssets = Set.of(assets);
  }

  void _applyAssetProposal(Map<String, dynamic> proposal) {
    final title = proposal['title'] as String? ?? 'AI Asset Proposal';
    // Use page_key to find the target page; fall back to current page.
    // proposal['key'] is the asset identifier, not a page key.
    final targetPage = proposal['page_key'] as String? ?? _currentPage;

    List<Asset> newAssets = [];
    for (final sourceKey in ['children', 'assets']) {
      if (proposal[sourceKey] is! List) continue;
      final items = proposal[sourceKey] as List;
      // First, try full parse (works when the JSON has all required fields).
      try {
        final parsed = AssetRegistry.parse({'assets': items});
        if (parsed.isNotEmpty) {
          newAssets.addAll(parsed);
          continue;
        }
      } catch (_) {}
      // Fallback: create default assets by type name and apply key/title/
      // coordinates from the proposal. This handles MCP proposals that only
      // provide minimal fields (asset_type, key, title).
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final assetName =
            item['asset_name'] as String? ?? item['asset_type'] as String?;
        if (assetName == null) continue;
        final asset = AssetRegistry.createDefaultAssetByName(assetName);
        if (asset == null) continue;
        // Apply key — most asset types store it as a direct `key` field.
        if (item['key'] is String) {
          try {
            (asset as dynamic).key = item['key'] as String;
          } catch (_) {}
        }
        // Apply display text.
        final label = item['title'] as String? ?? item['text'] as String?;
        if (label != null) {
          asset.text = label;
          asset.textPos ??= TextPos.below;
        }
        // Apply coordinates.
        if (item['coordinates'] is Map<String, dynamic>) {
          final c = item['coordinates'] as Map<String, dynamic>;
          asset.coordinates = Coordinates(
            x: (c['x'] as num?)?.toDouble() ?? 0.0,
            y: (c['y'] as num?)?.toDouble() ?? 0.0,
          );
        } else if (item['x'] is num || item['y'] is num) {
          asset.coordinates = Coordinates(
            x: (item['x'] as num?)?.toDouble() ?? 0.1,
            y: (item['y'] as num?)?.toDouble() ?? 0.1,
          );
        }
        // Apply config overrides: merge LLM-provided config into the
        // default asset's JSON representation, then re-parse to get a
        // fully configured asset with all type-safe fields.
        final config = item['config'];
        if (config is Map<String, dynamic> && config.isNotEmpty) {
          try {
            final baseJson = asset.toJson();
            baseJson.addAll(config);
            // Ensure asset_name survives the merge so parse() finds it.
            baseJson[constAssetName] = assetName;
            final reparsed =
                AssetRegistry.parse({constAssetName: assetName, ...baseJson});
            if (reparsed.isNotEmpty) {
              newAssets.add(reparsed.first);
              continue;
            }
          } catch (_) {
            // If re-parse fails, fall through and use the default asset.
          }
        }
        newAssets.add(asset);
      }
    }

    _proposedAssets = Set.of(newAssets);

    if (targetPage != null && _temporaryPages.containsKey(targetPage)) {
      // Add assets to existing page.
      _temporaryPages[targetPage]!.assets.addAll(newAssets);
      _currentPage = targetPage;
    } else {
      // Create a new page with the proposed assets.
      final pageKey = targetPage ?? '/$title';
      _temporaryPages[pageKey] = AssetPage(
        menuItem:
            MenuItem(label: title, path: pageKey, icon: Icons.auto_awesome),
        assets: newAssets,
        mirroringDisabled: false,
      );
      _currentPage = pageKey;
    }

    _isProposal = true;
    _proposalTitle = title;
  }

  void _applyUpdateProposal(Map<String, dynamic> proposal) {
    final targetPage = proposal['page_key'] as String? ?? _currentPage;
    final page = targetPage == null ? null : _temporaryPages[targetPage];
    final result = page == null
        ? const AssetUpdateResult.failure('page not found')
        : applyAssetUpdate(page.assets, proposal);

    final updated = result.updated;
    if (page == null || updated == null) {
      // The page is left untouched -- tell the operator why instead of
      // silently showing an editor with no diff.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('AI update proposal not applied: '
                  '${result.error}')),
        );
      });
      return;
    }

    page.assets[result.index] = updated;
    _currentPage = targetPage;
    _isProposal = true;
    _proposalTitle = updated.text ?? updated.runtimeType.toString();
    _proposedAssets = {updated};
  }

  void _updateCurrentJson() {
    _currentJson = jsonEncode(
        _temporaryPages.map((name, page) => MapEntry(name, page.toJson())));
  }

  bool get _hasUnsavedChanges => _currentJson != _savedJson || _navOrderDirty;

  String _assetsToJson(List<Asset> theAssets) {
    return jsonEncode({
      'assets': theAssets.map((a) => a.toJson()).toList(),
    });
  }

  Future<void> _saveToPrefs() async {
    final pageManager = await ref.read(pageManagerProvider.future);
    pageManager.pages = PageManager.copyPages(_temporaryPages);
    pageManager.topLevelOrder = List.of(_topLevelOrder);
    await pageManager.save();
    await _garbageCollectImages();
    ref.invalidate(pageManagerProvider);
    if (!mounted) return;

    // Update universal proposal state if this was a proposal accept.
    if (_isProposal && _proposalId != null) {
      try {
        ref.read(proposalStateProvider.notifier).acceptProposal(_proposalId!);
      } catch (_) {}
    }

    setState(() {
      _updateCurrentJson();
      _savedJson = _currentJson;
      _navOrderDirty = false;
      _isProposal = false; // Proposal accepted and saved.
      _proposedAssets = {};
      _preProposalPages = null;
    });
  }

  /// Deletes stored image blobs nothing points at any more. Runs on save —
  /// the only moment deletions become permanent — and keeps anything the undo
  /// history or the copy buffer could still bring back.
  Future<void> _garbageCollectImages() async {
    try {
      final store = await ref.read(pageImageStoreProvider.future);
      final referenced = <String>{
        ...PageImageStore.referencedImageIds(
            _temporaryPages.map((name, page) => MapEntry(name, page.toJson()))),
        for (final snapshot in _undoHistory)
          ...PageImageStore.referencedImageIds(
              snapshot.map((name, page) => MapEntry(name, page.toJson()))),
        if (_copiedAssets != null)
          ...PageImageStore.referencedImageIds(jsonDecode(_copiedAssets!)),
      };
      await store.removeUnreferenced(referenced);
    } catch (_) {
      // A failed cleanup must never break saving; orphans get another chance
      // on the next save.
    }
  }

  void _updateState(VoidCallback fn) {
    setState(() {
      fn();
      _updateCurrentJson();
    });
  }

  void _saveToHistory() {
    _undoHistory.add(PageManager.copyPages(_temporaryPages));
    if (_undoHistory.length > 50) {
      _undoHistory.removeAt(0);
    }
  }

  void _handleUndo() {
    if (_undoHistory.isNotEmpty) {
      setState(() {
        _temporaryPages = _undoHistory.removeLast();
        _updateCurrentJson();
      });
    }
  }

  bool _isModifierPressed(Set<LogicalKeyboardKey> keysPressed) {
    if (kIsWeb || Platform.isWindows || Platform.isLinux) {
      return keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
          keysPressed.contains(LogicalKeyboardKey.controlRight);
    } else if (Platform.isMacOS) {
      return keysPressed.contains(LogicalKeyboardKey.metaLeft) ||
          keysPressed.contains(LogicalKeyboardKey.metaRight);
    }
    return false;
  }

  void _handleAssetSelection(Asset asset, Set<LogicalKeyboardKey> keysPressed) {
    setState(() {
      if (_isModifierPressed(keysPressed)) {
        if (_selectedAssets.contains(asset)) {
          _selectedAssets.remove(asset);
        } else {
          _selectedAssets.add(asset);
        }
      } else {
        _selectedAssets = {asset};
      }
    });
  }

  void _handleCopy() {
    if (_selectedAssets.isEmpty) return;
    _copyAssets(_selectedAssets.toList());
  }

  /// Backs both Ctrl/Cmd+C (the whole selection) and the context menu's Copy
  /// entry (the asset under the cursor, or the selection when it is in it).
  void _copyAssets(List<Asset> targets) {
    if (targets.isEmpty) return;
    _copiedAssets = _assetsToJson(targets);
    // Mirror onto the system clipboard, so paste can tell whether the user's
    // most recent copy was assets here or an image somewhere else.
    unawaited(EditorClipboard.instance.writeText(_copiedAssets!));
  }

  /// True when [text] is the asset JSON that [_handleCopy] puts on the system
  /// clipboard (from this or another editor window).
  bool _looksLikeAssetJson(String? text) {
    if (text == null || !text.contains(constAssetName)) return false;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return false;
      return AssetRegistry.parse(decoded).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// [at], in 0..1 canvas fractions, is where the context menu's "Paste here"
  /// drops the group — centred on the click. Ctrl/Cmd+V passes null and gets
  /// the classic slight offset from the source instead, so repeated pastes
  /// remain visibly distinct from what they copy.
  Future<void> _handlePaste({Offset? at}) async {
    final clipboard = EditorClipboard.instance;

    // The system clipboard reflects the user's latest copy: asset JSON when
    // they last copied in an editor, an image when they last copied one in a
    // browser or screenshot tool. Prefer whichever it holds; the in-memory
    // buffer is only a fallback for platforms with no clipboard access.
    String? assetJson;
    final text = await clipboard.readText();
    if (_looksLikeAssetJson(text)) {
      assetJson = text;
    } else {
      final imageBytes = await clipboard.readImage();
      if (imageBytes != null) {
        await _pasteImage(imageBytes, at: at);
        return;
      }
    }
    assetJson ??= _copiedAssets;
    if (assetJson == null || !mounted) return;
    final pasted = assetJson;

    _saveToHistory();
    setState(() {
      _selectedAssets.clear();

      final copiedAssets = AssetRegistry.parse(jsonDecode(pasted));

      if (at != null) {
        final placed = placeGroupAt(
          placements: _placements(copiedAssets),
          targetX: at.dx,
          targetY: at.dy,
          aspectRatio: _canvasAspectRatio(),
        );
        for (var i = 0; i < copiedAssets.length; i++) {
          copiedAssets[i].coordinates = Coordinates(
            x: placed[i].x,
            y: placed[i].y,
            angle: copiedAssets[i].coordinates.angle,
          );
        }
      } else {
        for (final asset in copiedAssets) {
          asset.coordinates = Coordinates(
            x: (asset.coordinates.x + 0.02).clamp(0.0, 1.0),
            y: (asset.coordinates.y + 0.02).clamp(0.0, 1.0),
            angle: asset.coordinates.angle,
          );
        }
      }
      for (final asset in copiedAssets) {
        assets.add(asset);
        _selectedAssets.add(asset);
      }
      _updateCurrentJson();
    });
  }

  /// The live canvas's width / height, or 16:9 before the first layout.
  double _canvasAspectRatio() {
    final constraints = _canvasConstraints;
    return constraints == null || constraints.maxHeight <= 0
        ? 16 / 9
        : constraints.maxWidth / constraints.maxHeight;
  }

  /// Drops a pasted clipboard image onto the canvas as a new [ImageConfig],
  /// sized so the image keeps its shape at a quarter of the canvas width —
  /// centred on [at] when the paste came from the context menu, on the canvas
  /// itself when it came from Ctrl/Cmd+V.
  Future<void> _pasteImage(Uint8List bytes, {Offset? at}) async {
    try {
      final store = await ref.read(pageImageStoreProvider.future);
      final ingest = await ingestPageImage(store, bytes);
      // The id is content-derived: a re-pasted image may reuse an id whose
      // provider cached "gone" after garbage collection.
      ref.invalidate(pageImageBytesProvider(ingest.id));
      if (!mounted) return;

      final canvasAspect = _canvasAspectRatio();
      const widthFrac = 0.25;
      final heightFrac =
          (widthFrac * canvasAspect / ingest.aspectRatio).clamp(0.02, 0.9);

      var coordinates = Coordinates(x: 0.5, y: 0.5);
      if (at != null) {
        // The same pull-back-on-canvas rule as pasting assets, so a paste
        // near an edge lands flush against it instead of half off-screen.
        final placed = placeGroupAt(
          placements: [
            AssetPlacement(
                x: at.dx, y: at.dy, width: widthFrac, height: heightFrac),
          ],
          targetX: at.dx,
          targetY: at.dy,
          aspectRatio: canvasAspect,
        ).single;
        coordinates = Coordinates(x: placed.x, y: placed.y);
      }

      final asset = ImageConfig()
        ..applyIngest(ingest)
        ..size = RelativeSize(width: widthFrac, height: heightFrac)
        ..coordinates = coordinates;

      _saveToHistory();
      setState(() {
        assets.add(asset);
        _selectedAssets
          ..clear()
          ..add(asset);
        _updateCurrentJson();
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _handleDelete() => _deleteAssets(_selectedAssets.toList());

  /// Removes [targets] from the page. Backs both the Delete/Backspace keys
  /// (whole selection) and the context menu's Delete entry (the asset under
  /// the cursor, or the selection when it is part of one).
  void _deleteAssets(List<Asset> targets) {
    if (targets.isEmpty) return;

    // The pane would otherwise stay up over an asset that no longer exists
    // until the next `_syncConfigEdits` tick noticed and shut it.
    final configAsset = _configAsset;
    if (configAsset != null && targets.contains(configAsset)) {
      closeSidePane(id: _configPaneId(configAsset));
    }

    _saveToHistory();
    setState(() {
      assets.removeWhere(targets.contains);
      _selectedAssets.removeAll(targets);
      _updateCurrentJson();
    });
  }

  /// Rotates the current selection a quarter turn from the keyboard.
  ///
  /// The same group rotation the context menu offers — a single selected asset
  /// spins in place, several turn as one rigid group. Silently does nothing
  /// with an empty selection, so the key is harmless when nothing is picked.
  void _handleRotateShortcut(double degrees) {
    final constraints = _canvasConstraints;
    if (constraints == null || _selectedAssets.isEmpty) return;
    _rotateAssets(_selectedAssets.toList(), degrees, constraints);
  }

  /// Menu values for the editing actions; AI entries use their own list index,
  /// so these sit outside that range.
  static const int _sendToBackAction = -1;
  static const int _rotateClockwiseAction = -2;
  static const int _rotateCounterClockwiseAction = -3;
  static const int _alignHorizontalAction = -4;
  static const int _alignVerticalAction = -5;
  static const int _editAction = -6;
  static const int _mirrorHorizontalAction = -7;
  static const int _mirrorVerticalAction = -8;
  static const int _bringToFrontAction = -9;
  static const int _deleteAction = -9;
  static const int _copyAction = -10;
  static const int _pasteAction = -11;

  /// Assets a canvas action applies to: the whole selection when the asset
  /// acted on is part of it, otherwise just that asset. Mirrors [_moveAsset].
  List<Asset> _actionTargets(Asset asset) =>
      _selectedAssets.contains(asset) ? _selectedAssets.toList() : [asset];

  /// False when [targets] already sit at the bottom, so the menu entry can be
  /// disabled rather than pushing a no-op onto the undo history.
  bool _canSendToBack(List<Asset> targets) =>
      !isAlreadyAtBack(assets, targets.toSet());

  /// False when [targets] already sit on top, so the menu entry can be
  /// disabled rather than pushing a no-op onto the undo history.
  bool _canBringToFront(List<Asset> targets) =>
      !isAlreadyAtFront(assets, targets.toSet());

  /// Moves [targets] beneath every other asset on the page.
  void _sendToBack(List<Asset> targets) {
    final moving = targets.toSet();
    if (isAlreadyAtBack(assets, moving)) return;
    _applyOrder(sendToBackOrder(assets, moving));
  }

  /// Moves [targets] on top of every other asset on the page.
  void _bringToFront(List<Asset> targets) {
    final moving = targets.toSet();
    if (isAlreadyAtFront(assets, moving)) return;
    _applyOrder(bringToFrontOrder(assets, moving));
  }

  void _applyOrder(List<Asset> reordered) {
    _saveToHistory();
    setState(() {
      // Mutate in place: AssetPage holds a reference to this same list.
      assets
        ..clear()
        ..addAll(reordered);
      _updateCurrentJson();
    });
  }

  /// [targets] as placements, for the geometry helpers.
  List<AssetPlacement> _placements(List<Asset> targets) => [
        for (final asset in targets)
          AssetPlacement(
            x: asset.coordinates.x,
            y: asset.coordinates.y,
            width: asset.size.width,
            height: asset.size.height,
            angle: asset.coordinates.angle,
          ),
      ];

  /// Writes [placements] back onto [targets], which must line up positionally.
  void _applyPlacements(List<Asset> targets, List<AssetPlacement> placements) {
    _saveToHistory();
    _updateState(() {
      for (var i = 0; i < targets.length; i++) {
        targets[i].coordinates = Coordinates(
          x: placements[i].x,
          y: placements[i].y,
          angle: placements[i].angle,
        );
      }
    });
  }

  /// False when [targets] already sit on one line along [axis], so the menu
  /// entry can be disabled. Mirrors [_canSendToBack].
  bool _canAlign(List<Asset> targets, AlignAxis axis) =>
      !isAlreadyAligned(_placements(targets), axis);

  /// Lines [targets] up on [axis], centre points onto the selection's middle.
  void _alignAssets(List<Asset> targets, AlignAxis axis) {
    final placements = _placements(targets);
    if (isAlreadyAligned(placements, axis)) return;

    _applyPlacements(targets, alignGroup(placements: placements, axis: axis));
  }

  /// Rotates [targets] a quarter turn as one rigid group about the centre of
  /// their combined bounding box. A single asset is just the degenerate case:
  /// its own centre is the group centre, so it spins in place.
  ///
  /// [constraints] supplies the canvas aspect ratio, without which a rotation
  /// of the normalized coordinates would shear the group. See [rotateGroup].
  void _rotateAssets(
    List<Asset> targets,
    double degrees,
    BoxConstraints constraints,
  ) {
    if (targets.isEmpty) return;

    _applyPlacements(
      targets,
      rotateGroup(
        placements: _placements(targets),
        degrees: degrees,
        aspectRatio: constraints.maxWidth / constraints.maxHeight,
      ),
    );
  }

  /// Flips [targets] about the centre of their combined bounding box.
  ///
  /// [constraints] supplies the canvas aspect ratio, for the same reason
  /// [_rotateAssets] needs it. See [mirrorGroup].
  void _mirrorAssets(
    List<Asset> targets,
    MirrorAxis axis,
    BoxConstraints constraints,
  ) {
    if (targets.isEmpty) return;

    _applyPlacements(
      targets,
      mirrorGroup(
        placements: _placements(targets),
        axis: axis,
        aspectRatio: constraints.maxWidth / constraints.maxHeight,
      ),
    );
  }

  /// Right-click menu for an asset on the canvas.
  ///
  /// Editing actions are always available; the AI entries are appended only
  /// when MCP chat is up, preserving what the AI-only menu used to offer.
  ///
  /// [constraints] are the canvas's, needed by the rotate entries.
  /// [pasteTarget] is the click point in 0..1 canvas fractions, where the
  /// Paste entry drops its group.
  Future<void> _showAssetContextMenu(
    Asset asset,
    Offset globalPosition,
    BoxConstraints constraints,
    Offset pasteTarget,
  ) async {
    final aiItems = kChatEnabled && isMcpChatAvailable()
        ? buildEditorAssetMenuItems(asset)
        : const <AiMenuItem>[];

    final targets = _actionTargets(asset);
    final canSendToBack = _canSendToBack(targets);
    final canBringToFront = _canBringToFront(targets);
    final canAlignHorizontal = _canAlign(targets, AlignAxis.horizontal);
    final canAlignVertical = _canAlign(targets, AlignAxis.vertical);

    final choice = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        // First, and on its own: this is how the configuration editor is
        // reached now that a tap selects instead of opening it. Unlike the
        // entries below it acts on the asset under the cursor rather than on
        // the whole selection — the pane configures one asset.
        PopupMenuItem<int>(
          value: _editAction,
          child: const ListTile(
            leading: Icon(Icons.tune),
            title: Text('Edit'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: _copyAction,
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: Text(
                targets.length > 1 ? 'Copy ${targets.length} assets' : 'Copy'),
            dense: true,
          ),
        ),
        // Always enabled: whether there is anything to paste can live on the
        // system clipboard (asset JSON or an image from another window), which
        // cannot be inspected synchronously. An empty paste is a no-op.
        PopupMenuItem<int>(
          value: _pasteAction,
          child: const ListTile(
            leading: Icon(Icons.content_paste),
            title: Text('Paste here'),
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: _rotateClockwiseAction,
          child: ListTile(
            leading: const Icon(Icons.rotate_right),
            title: Text(targets.length > 1
                ? 'Rotate ${targets.length} assets 90° clockwise'
                : 'Rotate 90° clockwise'),
            dense: true,
          ),
        ),
        PopupMenuItem<int>(
          value: _rotateCounterClockwiseAction,
          child: ListTile(
            leading: const Icon(Icons.rotate_left),
            title: Text(targets.length > 1
                ? 'Rotate ${targets.length} assets 90° counter-clockwise'
                : 'Rotate 90° counter-clockwise'),
            dense: true,
          ),
        ),
        // Named for the direction things move, not the line they reflect
        // about: "horizontally" swaps left for right. Matches how a drawing
        // tool's Flip Horizontal reads, and how the rotate pair above it does.
        PopupMenuItem<int>(
          value: _mirrorHorizontalAction,
          child: ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(targets.length > 1
                ? 'Mirror ${targets.length} assets horizontally'
                : 'Mirror horizontally'),
            dense: true,
          ),
        ),
        PopupMenuItem<int>(
          value: _mirrorVerticalAction,
          child: ListTile(
            leading: const Icon(Icons.swap_vert),
            title: Text(targets.length > 1
                ? 'Mirror ${targets.length} assets vertically'
                : 'Mirror vertically'),
            dense: true,
          ),
        ),
        // The icon names read backwards: `align_vertical_center` draws a
        // horizontal reference line, which is what lining assets up into a
        // row looks like. Pair each entry with the line it produces, not with
        // the word in the icon name.
        PopupMenuItem<int>(
          value: _alignHorizontalAction,
          enabled: canAlignHorizontal,
          child: ListTile(
            leading: const Icon(Icons.align_vertical_center),
            title: Text(targets.length > 1
                ? 'Align ${targets.length} assets horizontally'
                : 'Align horizontally'),
            dense: true,
            enabled: canAlignHorizontal,
          ),
        ),
        PopupMenuItem<int>(
          value: _alignVerticalAction,
          enabled: canAlignVertical,
          child: ListTile(
            leading: const Icon(Icons.align_horizontal_center),
            title: Text(targets.length > 1
                ? 'Align ${targets.length} assets vertically'
                : 'Align vertically'),
            dense: true,
            enabled: canAlignVertical,
          ),
        ),
        PopupMenuItem<int>(
          value: _bringToFrontAction,
          enabled: canBringToFront,
          child: ListTile(
            leading: const Icon(Icons.flip_to_front),
            title: Text(targets.length > 1
                ? 'Bring ${targets.length} assets to front'
                : 'Bring to front'),
            dense: true,
            enabled: canBringToFront,
          ),
        ),
        PopupMenuItem<int>(
          value: _sendToBackAction,
          enabled: canSendToBack,
          child: ListTile(
            leading: const Icon(Icons.flip_to_back),
            title: Text(targets.length > 1
                ? 'Send ${targets.length} assets to back'
                : 'Send to back'),
            dense: true,
            enabled: canSendToBack,
          ),
        ),
        // Set off from the layout actions above: everything else rearranges,
        // this one destroys. Same targets rule though — the selection when
        // the clicked asset is in it, otherwise just that asset.
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: _deleteAction,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(targets.length > 1
                ? 'Delete ${targets.length} assets'
                : 'Delete'),
            dense: true,
          ),
        ),
        if (aiItems.isNotEmpty) const PopupMenuDivider(),
        for (var i = 0; i < aiItems.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: ListTile(
              leading: Icon(aiItems[i].icon),
              title: Text(aiItems[i].label),
              dense: true,
            ),
          ),
      ],
    );

    if (choice == null) return;
    // The editor can be torn down while the menu is open — proposal events
    // arriving over MCP navigate on their own — and both branches below touch
    // State (setState / ref) that is invalid after dispose.
    if (!mounted) return;

    if (choice == _editAction) {
      // `_openConfigPane` toggles, which from a menu entry reading "Edit"
      // would read as the pane refusing to open. Already showing this asset
      // is already the wanted end state.
      if (!identical(_configAsset, asset)) _openConfigPane(asset);
    } else if (choice == _sendToBackAction) {
      _sendToBack(targets);
    } else if (choice == _bringToFrontAction) {
      _bringToFront(targets);
    } else if (choice == _rotateClockwiseAction) {
      _rotateAssets(targets, 90, constraints);
    } else if (choice == _rotateCounterClockwiseAction) {
      _rotateAssets(targets, -90, constraints);
    } else if (choice == _mirrorHorizontalAction) {
      _mirrorAssets(targets, MirrorAxis.horizontal, constraints);
    } else if (choice == _mirrorVerticalAction) {
      _mirrorAssets(targets, MirrorAxis.vertical, constraints);
    } else if (choice == _alignHorizontalAction) {
      _alignAssets(targets, AlignAxis.horizontal);
    } else if (choice == _alignVerticalAction) {
      _alignAssets(targets, AlignAxis.vertical);
    } else if (choice == _deleteAction) {
      _deleteAssets(targets);
    } else if (choice == _copyAction) {
      _copyAssets(targets);
    } else if (choice == _pasteAction) {
      await _handlePaste(at: pasteTarget);
    } else if (kChatEnabled) {
      await AiContextAction.runMenuItem(ref: ref, item: aiItems[choice]);
    }
  }

  /// Right-click menu for empty canvas. One entry so far: paste, centred on
  /// the click — the natural counterpart of Copy on the asset menu.
  Future<void> _showCanvasContextMenu(
    Offset globalPosition,
    Offset pasteTarget,
  ) async {
    final choice = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        // Enabled unconditionally, same reasoning as the asset menu's entry.
        const PopupMenuItem<int>(
          value: _pasteAction,
          child: ListTile(
            leading: Icon(Icons.content_paste),
            title: Text('Paste here'),
            dense: true,
          ),
        ),
      ],
    );
    if (choice != _pasteAction || !mounted) return;
    await _handlePaste(at: pasteTarget);
  }

  @override
  Widget build(BuildContext context) {
    // Reactively watch for new page/asset proposals arriving via MCP.
    ref.listen<ProposalState>(proposalStateProvider, (prev, next) {
      if (_isProposal) return; // Already showing a proposal.
      final pageProposals = next.proposals
          .where((p) => p.proposalType == 'page' || p.proposalType == 'asset');
      if (pageProposals.isEmpty) return;
      final proposal = pageProposals.first;
      _applyProposalData(proposal.proposalJson);
      if (_isProposal) {
        _updateCurrentJson();
        _savedJson = ''; // Mark unsaved for proposal.
        setState(() {});
      }
    });

    return Focus(
      focusNode: _shortcutFocus,
      autofocus: true,
      // A window switch or a click into the palette can swallow the key up,
      // which would otherwise leave the canvas stuck in pan.
      onFocusChange: (hasFocus) {
        if (!hasFocus && _isPanKeyHeld) {
          setState(() => _isPanKeyHeld = false);
        }
      },
      onKeyEvent: (node, event) {
        // Don't intercept keys when a text field has focus — otherwise
        // backspace/delete edit the canvas selection, R rotates it and space
        // pans, all mid-keystroke. A focused text field's FocusNode attaches
        // to a Focus widget *inside* EditableText's build, so the focused
        // context's own widget is never EditableText — the EditableText is
        // found among its ancestors.
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext != null &&
            (focusContext.widget is EditableText ||
                focusContext.findAncestorStateOfType<EditableTextState>() !=
                    null)) {
          return KeyEventResult.ignored;
        }
        // Space is held, not pressed: it is the only thing that turns a drag
        // on empty canvas from a marquee back into a canvas pan, so both
        // edges matter. KeyRepeatEvent arrives while it is down and must not
        // be read as a release.
        if (event.logicalKey == LogicalKeyboardKey.space) {
          final held = event is! KeyUpEvent;
          if (held != _isPanKeyHeld) {
            setState(() => _isPanKeyHeld = held);
          }
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent) {
          if (_isModifierPressed(
              HardwareKeyboard.instance.logicalKeysPressed)) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              _handleUndo();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
              _handleCopy();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
              _handlePaste();
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _handleDelete();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
            // Shift reverses it, the way the two menu entries pair up.
            _handleRotateShortcut(
              HardwareKeyboard.instance.isShiftPressed ? -90 : 90,
            );
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: BaseScaffold(
        title: _isProposal ? 'Page Editor — AI Proposal' : 'Page Editor',
        body: Column(
          children: [
            if (_isProposal)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.amber.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI Proposal: ${_proposalTitle ?? "Untitled"}. '
                        'Review the proposed layout.',
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saveToPrefs,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Accept'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        if (_proposalId != null) {
                          try {
                            ref
                                .read(proposalStateProvider.notifier)
                                .rejectProposal(_proposalId!);
                          } catch (_) {}
                        }
                        setState(() {
                          if (_preProposalPages != null) {
                            _temporaryPages = _preProposalPages!;
                            _currentPage = _temporaryPages.keys.firstOrNull;
                          }
                          _isProposal = false;
                          _proposedAssets = {};
                          _preProposalPages = null;
                          _updateCurrentJson();
                          _savedJson = _currentJson;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ),
            Expanded(
                child: Listener(
                    // Any click on the canvas re-arms the shortcuts. Selecting an
                    // asset and pressing Ctrl/Cmd+C must work no matter what held
                    // keyboard focus before — the config pane's fields being the
                    // case that never heals on its own: the pane lives in the root
                    // overlay, so as long as it keeps focus, key events never even
                    // reach this page's Focus subtree. Raw pointer-down, not a tap:
                    // it precedes the gesture arena, so a text field clicked inside
                    // the palette still wins focus back on the tap itself.
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (!_shortcutFocus.hasPrimaryFocus) {
                        _shortcutFocus.requestFocus();
                      }
                    },
                    child: ZoomableCanvas(
                      scaleEnabled: !_showPalette,
                      panEnabled: _isPanKeyHeld,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Stashed for the keyboard handler, which is above this
                          // builder and cannot see the canvas box. Plain assignment:
                          // calling setState during build is not allowed, and nothing
                          // here needs a repaint — the next rotate simply reads it.
                          _canvasConstraints = constraints;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                color: Theme.of(context).colorScheme.surface,
                              ),
                              // The only feedback that the held pan key has
                              // changed what a drag will do. A MouseRegion
                              // only tracks hover — it joins no gesture arena
                              // — so it can sit in the stack rather than
                              // wrapping the canvas and re-indenting it.
                              if (_isPanKeyHeld)
                                const Positioned.fill(
                                  child: MouseRegion(
                                      cursor: SystemMouseCursors.grab),
                                ),
                              DragTarget<Type>(
                                onAcceptWithDetails: (details) {
                                  final RenderBox box =
                                      context.findRenderObject() as RenderBox;
                                  final localPosition =
                                      box.globalToLocal(details.offset);

                                  final relativeX =
                                      (localPosition.dx / box.size.width)
                                          .clamp(0.0, 1.0);
                                  final relativeY =
                                      (localPosition.dy / box.size.height)
                                          .clamp(0.0, 1.0);

                                  final newAsset =
                                      AssetRegistry.createDefaultAsset(
                                          details.data);
                                  _saveToHistory();
                                  setState(() {
                                    newAsset.coordinates =
                                        Coordinates(x: relativeX, y: relativeY);
                                    assets.add(newAsset);
                                    _updateCurrentJson();
                                  });
                                },
                                builder:
                                    (context, candidateData, rejectedData) {
                                  return AssetStack(
                                    assets: assets,
                                    constraints: constraints,
                                    // A tap selects, always. Configuring used to be
                                    // what a tap did, in the mode where selecting was
                                    // not; with one mode there is room for only one
                                    // meaning, and the config pane is reachable from
                                    // the right-click menu instead. The pane is not
                                    // modal, so it can follow the selection: with one
                                    // already open, selecting another asset re-points
                                    // it rather than leaving stale config on screen.
                                    onTap: (asset) {
                                      final keys = HardwareKeyboard
                                          .instance.logicalKeysPressed;
                                      _handleAssetSelection(asset, keys);
                                      if (_configAsset != null &&
                                          !identical(_configAsset, asset) &&
                                          !_isModifierPressed(keys)) {
                                        _openConfigPane(asset);
                                      }
                                    },
                                    // The pointer-first route to the config pane; the
                                    // right-click menu's "Edit" stays as the
                                    // discoverable one. A double tap swallows both of
                                    // its single taps, so selection has to happen
                                    // here too — plainly, since reaching for a double
                                    // click says "just this one".
                                    onDoubleTap: (asset) {
                                      setState(() => _selectedAssets = {asset});
                                      if (!identical(_configAsset, asset)) {
                                        _openConfigPane(asset);
                                      }
                                    },
                                    onPanUpdate: (asset, details) {
                                      _moveAsset(asset, details, constraints);
                                    },
                                    onPanStart: (asset, details) {
                                      // Claims the drag for the asset so the marquee
                                      // listener below stands down for its duration.
                                      _isDraggingAsset = true;
                                      _saveToHistory();
                                    },
                                    onSecondaryTap: (asset, globalPosition) {
                                      final box = context.findRenderObject()
                                          as RenderBox;
                                      final local =
                                          box.globalToLocal(globalPosition);
                                      _showAssetContextMenu(
                                        asset,
                                        globalPosition,
                                        constraints,
                                        Offset(
                                          (local.dx / constraints.maxWidth)
                                              .clamp(0.0, 1.0),
                                          (local.dy / constraints.maxHeight)
                                              .clamp(0.0, 1.0),
                                        ),
                                      );
                                    },
                                    absorb: true,
                                    selectedAssets: _selectedAssets,
                                    proposedAssets: _proposedAssets,
                                    mirroringDisabled:
                                        _temporaryPages[_currentPage]
                                                ?.mirroringDisabled ??
                                            false,
                                  );
                                },
                              ),
                              // Always live now, rather than only in a select mode.
                              // It stands down while the pan key is held, which is the
                              // one gesture it would otherwise take over.
                              if (!_isPanKeyHeld)
                                Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: (pointerEvent) {
                                    // Check if we're clicking on an asset first.
                                    // The hit-test respects the asset's rotation
                                    // via marqueeHitTestRotatedAsset — without it
                                    // the marquee gate would (a) start a marquee
                                    // when the operator clicks inside the rotated
                                    // visual but outside its pre-rotation AABB,
                                    // and (b) refuse to start a marquee when the
                                    // operator clicks empty visual space inside
                                    // the pre-rotation rect.
                                    bool hitAsset = assets.any((asset) {
                                      return marqueeHitTestRotatedAsset(
                                        pointer: pointerEvent.localPosition,
                                        cx: asset.coordinates.x *
                                            constraints.maxWidth,
                                        cy: asset.coordinates.y *
                                            constraints.maxHeight,
                                        halfW: (asset.size.width *
                                                constraints.maxWidth) /
                                            2,
                                        halfH: (asset.size.height *
                                                constraints.maxHeight) /
                                            2,
                                        angleDegrees:
                                            asset.coordinates.angle ?? 0.0,
                                      );
                                    });

                                    // A right-click is a menu, never a marquee: on
                                    // empty canvas it offers paste-at-cursor; on an
                                    // asset, AssetStack shows its own menu, so only
                                    // the marquee below has to stand down.
                                    if (pointerEvent.buttons ==
                                        kSecondaryMouseButton) {
                                      if (!hitAsset) {
                                        _showCanvasContextMenu(
                                          pointerEvent.position,
                                          Offset(
                                            (pointerEvent.localPosition.dx /
                                                    constraints.maxWidth)
                                                .clamp(0.0, 1.0),
                                            (pointerEvent.localPosition.dy /
                                                    constraints.maxHeight)
                                                .clamp(0.0, 1.0),
                                          ),
                                        );
                                      }
                                      return;
                                    }

                                    // Only start selection box if we didn't hit an asset
                                    if (!hitAsset) {
                                      // If no Ctrl/Cmd, clear any existing selection
                                      if (!_isModifierPressed(HardwareKeyboard
                                          .instance.logicalKeysPressed)) {
                                        setState(() {
                                          _selectedAssets.clear();
                                        });
                                      }
                                      // Record the start of the drag‐selection
                                      final box = context.findRenderObject()
                                          as RenderBox;
                                      final local = box
                                          .globalToLocal(pointerEvent.position);
                                      setState(() {
                                        _selectionStart = local;
                                        _selectionCurrent = local;
                                      });
                                    }
                                  },
                                  onPointerMove: (pointerEvent) {
                                    // Only update selection if we have a valid selection start AND we're not dragging an asset
                                    if (_selectionStart != null &&
                                        !_isDraggingAsset) {
                                      final box = context.findRenderObject()
                                          as RenderBox;
                                      final local = box
                                          .globalToLocal(pointerEvent.position);
                                      setState(() {
                                        _selectionCurrent = local;

                                        final bounds = Rect.fromPoints(
                                            _selectionStart!,
                                            _selectionCurrent!);
                                        _selectedAssets = assets.where((asset) {
                                          final cx = asset.coordinates.x *
                                              constraints.maxWidth;
                                          final cy = asset.coordinates.y *
                                              constraints.maxHeight;
                                          final halfW = (asset.size.width *
                                                  constraints.maxWidth) /
                                              2;
                                          final halfH = (asset.size.height *
                                                  constraints.maxHeight) /
                                              2;

                                          final assetRect = Rect.fromLTWH(
                                            cx -
                                                halfW, // Offset by half width to match Positioned widget
                                            cy -
                                                halfH, // Offset by half height to match Positioned widget
                                            asset.size.width *
                                                constraints.maxWidth,
                                            asset.size.height *
                                                constraints.maxHeight,
                                          );
                                          return bounds.overlaps(assetRect);
                                        }).toSet();
                                      });
                                    }
                                  },
                                  onPointerUp: (pointerEvent) {
                                    setState(() {
                                      _isDraggingAsset = false;
                                      _selectionStart = null;
                                      _selectionCurrent = null;
                                    });
                                  },
                                ),
                              if (_selectionStart != null &&
                                  _selectionCurrent != null)
                                CustomPaint(
                                  painter: SelectionBoxPainter(
                                    start: _selectionStart!,
                                    current: _selectionCurrent!,
                                  ),
                                ),
                              AnimatedPositioned(
                                duration: _configPaneSlide,
                                curve: Curves.easeOutCubic,
                                top: 16,
                                right: 16 + _rightChromeInset,
                                child: _buildPageSelector(),
                              ),
                              Positioned(
                                left: 16,
                                bottom: 16,
                                child: Row(
                                  children: [
                                    _buildHamburgerFab(assets),
                                    const SizedBox(width: 8),
                                    FloatingActionButton(
                                      mini: true,
                                      heroTag: 'save',
                                      backgroundColor: _hasUnsavedChanges
                                          ? Colors.orange
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary,
                                      onPressed: _saveToPrefs,
                                      child: const Icon(Icons.save,
                                          color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                              if (_showPalette)
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _showPalette = false),
                                    behavior: HitTestBehavior.translucent,
                                    child: Container(),
                                  ),
                                ),
                              if (_showPalette)
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: 0,
                                  child: SizedBox(
                                    width: 320,
                                    child: Material(
                                      elevation: 8,
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.only(
                                        topRight: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                      child: Stack(
                                        children: [
                                          _buildPalette(),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: IconButton(
                                              icon: Icon(Icons.close),
                                              onPressed: () => setState(
                                                  () => _showPalette = false),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              AnimatedPositioned(
                                duration: _configPaneSlide,
                                curve: Curves.easeOutCubic,
                                right: 16 + _rightChromeInset,
                                bottom: 16,
                                // The mode toggle used to live at the bottom of this
                                // column. There is only one mode now, so what is left
                                // is the size pair, and it appears only when there is
                                // a selection to resize.
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_selectedAssets.isNotEmpty) ...[
                                      FloatingActionButton(
                                        mini: true,
                                        heroTag: 'increase',
                                        tooltip: 'Grow selection',
                                        onPressed: () =>
                                            _adjustSelectedAssetsSize(1.1),
                                        child: const Icon(Icons.add,
                                            color: Colors.white),
                                      ),
                                      const SizedBox(height: 8),
                                      FloatingActionButton(
                                        mini: true,
                                        heroTag: 'decrease',
                                        tooltip: 'Shrink selection',
                                        onPressed: () =>
                                            _adjustSelectedAssetsSize(0.9),
                                        child: const Icon(Icons.remove,
                                            color: Colors.white),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ))),
          ],
        ),
      ),
    );
  }

  Widget _buildPalette() {
    final query = _paletteSearchController.text.trim().toLowerCase();
    final entries = AssetRegistry.defaultFactories.entries.where((entry) {
      if (query.isEmpty) return true;
      final asset = entry.value();
      // Keywords let an umbrella asset be found by what it contains — the
      // 3rd-party tile answers to "multivac".
      return asset.displayName.toLowerCase().contains(query) ||
          asset.searchKeywords.any((k) => k.toLowerCase().contains(query));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 48, 8),
          child: TextField(
            controller: _paletteSearchController,
            decoration: const InputDecoration(
              hintText: 'Search assets...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final previewAsset = entry.value();
              Widget item = _PaletteItem(
                assetType: entry.key,
                asset: previewAsset,
              );
              if (kChatEnabled) {
                item = AiContextMenuWrapper(
                  menuItems: buildPaletteItemMenuItems(
                    asset: previewAsset,
                    pageName: _currentPage,
                    existingAssetSummary: summarizeExistingAssets(assets),
                  ),
                  child: item,
                );
              }
              return item;
            },
          ),
        ),
      ],
    );
  }

  /// The palette hamburger FAB, wrapped in the AI context menu only when the
  /// chat feature is compiled in ([kChatEnabled] is const, so the flag-off
  /// build tree-shakes the wrapper and its chat dependencies).
  Widget _buildHamburgerFab(List<Asset> assets) {
    Widget fab = FloatingActionButton(
      mini: true,
      heroTag: 'hamburger',
      backgroundColor: Theme.of(context).colorScheme.primary,
      onPressed: () => setState(() => _showPalette = true),
      child: const Icon(Icons.menu, color: Colors.white),
    );
    if (kChatEnabled) {
      fab = AiContextMenuWrapper(
        menuItems: buildHamburgerMenuItems(
          pageName: _currentPage ?? 'Untitled',
          assets: assets,
        ),
        child: fab,
      );
    }
    return fab;
  }

  /// Identifies one asset's pane. Assets have no stable id of their own, and
  /// two of the same type are equal only by identity, so that is what the id
  /// is built from — enough for `showSidePane` to tell "same asset, toggle
  /// shut" from "different asset, swap the contents".
  String _configPaneId(Asset asset) =>
      'page-editor-config:${identityHashCode(asset)}';

  /// Docks [asset]'s configuration editor to the right of the canvas.
  ///
  /// This used to be a `showDialog`, which put a barrier over the canvas: the
  /// operator had to close it to see what a change did, and again to move the
  /// asset. The pane is non-modal, so the canvas underneath keeps taking
  /// drags, marquee selection and taps on other assets while it is open, and
  /// [_syncConfigEdits] mirrors edits onto the canvas as they are made.
  void _openConfigPane(Asset asset) {
    ref.read(currentPageAssetsProvider.notifier).state = assets;

    // Tapping the asset whose pane is already open closes it; `showSidePane`
    // has already run `_onConfigPaneClosed` for us by then.
    final opened = showSidePane(
      context: context,
      id: _configPaneId(asset),
      width: _configPaneWidth,
      resizable: true,
      onWidthChanged: (width) => setState(() => _configPaneWidth = width),
      builder: (paneContext) => _buildConfigPane(paneContext, asset),
      onClosed: _onConfigPaneClosed,
    );
    if (!opened) return;

    setState(() {
      _configAsset = asset;
      _configSnapshot = _assetSnapshot(asset);
    });
    _configWatch?.cancel();
    _configWatch =
        Timer.periodic(_configWatchInterval, (_) => _syncConfigEdits());
  }

  /// Runs when the pane goes away for any reason — its Close button, Escape,
  /// a swap to another asset, or the editor being torn down.
  void _onConfigPaneClosed() {
    _configWatch?.cancel();
    _configWatch = null;
    _configSnapshot = null;
    if (!mounted) {
      _configAsset = null;
      return;
    }
    setState(() {
      _configAsset = null;
      // A last pass, in case the closing interaction itself was the edit.
      _updateCurrentJson();
    });
    // The pane may have held keyboard focus (its text fields live in the root
    // overlay); with it gone, the shortcuts take over again without the
    // operator having to click the canvas first.
    _shortcutFocus.requestFocus();
  }

  Widget _buildConfigPane(BuildContext paneContext, Asset asset) {
    final label = asset.text;
    return Listener(
      // Sync on the pointer event itself so slider drags and colour taps reach
      // the canvas in the same frame; the timer only has to cover edits that
      // arrive without one (typing, nested pickers, async key lookups).
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _syncConfigEdits(),
      onPointerMove: (_) => _syncConfigEdits(),
      onPointerUp: (_) => _syncConfigEdits(),
      child: SidePane(
        title: asset.displayName,
        subtitle: label != null && label.isNotEmpty ? label : null,
        icon: Icons.tune,
        // Every config editor brings its own scrolling and sizing; wrapping
        // them in another scroll view would leave the ones that use `Expanded`
        // with an unbounded height.
        scrollable: false,
        actions: [
          PaneAction.destructive(
            label: 'Delete',
            icon: Icons.delete,
            onPressed: () => _deleteConfiguredAsset(asset),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              Expanded(child: asset.configure(paneContext)),
              if (kKnowledgeEnabled && asset is BaseAsset)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TechDocPicker(
                    selectedDocId: asset.techDocId,
                    onChanged: (id) {
                      asset.techDocId = id;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Repaints the canvas when the open pane has changed its asset.
  ///
  /// Config editors write straight into the asset they were handed and call
  /// `setState` on themselves, so there is no callback to hook. Comparing the
  /// asset's own serialization catches every one of them without touching the
  /// ~45 editors, and costs one small `jsonEncode` per check.
  void _syncConfigEdits() {
    final asset = _configAsset;
    if (asset == null) return;

    // The asset can leave the canvas while its pane is up: deleted with the
    // keyboard, undone, or left behind by a page change.
    if (!assets.contains(asset)) {
      closeSidePane(id: _configPaneId(asset));
      return;
    }

    final snapshot = _assetSnapshot(asset);
    if (snapshot == null || snapshot == _configSnapshot) return;
    setState(() {
      _configSnapshot = snapshot;
      _updateCurrentJson();
    });
  }

  /// [asset] as JSON, or null if it will not serialize — in which case the
  /// pane simply falls back to updating the canvas when it closes.
  String? _assetSnapshot(Asset asset) {
    try {
      return jsonEncode(asset.toJson());
    } catch (_) {
      return null;
    }
  }

  void _deleteConfiguredAsset(Asset asset) {
    closeSidePane(id: _configPaneId(asset));
    _saveToHistory();
    _updateState(() {
      assets.remove(asset);
      _selectedAssets.remove(asset);
    });
  }

  void _moveAsset(
      Asset asset, DragUpdateDetails details, BoxConstraints constraints) {
    // If the dragged asset is selected, move all selected assets
    final assetsToMove =
        _selectedAssets.contains(asset) ? _selectedAssets.toList() : [asset];

    // `details.delta` arrives in the local coord space of the GestureDetector
    // that received the event. The selection-rotation fix wrapped that
    // GestureDetector inside `Transform.rotate(angle)`, so for a rotated
    // asset the local frame is rotated and a screen-right drag arrives as
    // local-down (and vice versa). projectDragDeltaToCanvas projects the
    // delta back into the canvas (parent) frame. For angle == 0 it's an
    // identity transform — behaviour matches the pre-rotation editor exactly.
    final canvasDelta = projectDragDeltaToCanvas(
      delta: details.delta,
      angleDegrees: asset.coordinates.angle ?? 0.0,
    );

    _updateState(() {
      for (final assetToMove in assetsToMove) {
        final newX =
            (assetToMove.coordinates.x + canvasDelta.dx / constraints.maxWidth)
                .clamp(0.0, 1.0);
        final newY =
            (assetToMove.coordinates.y + canvasDelta.dy / constraints.maxHeight)
                .clamp(0.0, 1.0);

        assetToMove.coordinates =
            Coordinates(x: newX, y: newY, angle: assetToMove.coordinates.angle);
      }
    });
  }

  void _adjustSelectedAssetsSize(double factor) {
    _saveToHistory();
    setState(() {
      for (final asset in _selectedAssets) {
        asset.size = RelativeSize(
          width: (asset.size.width * factor).clamp(0.01, 1.0),
          height: (asset.size.height * factor).clamp(0.01, 1.0),
        );
      }
      _updateCurrentJson();
    });
  }

  Widget _buildPageSelector() {
    final currentPagePath = _currentPage ?? _temporaryPages.keys.firstOrNull;
    final displayName = currentPagePath != null
        ? (_temporaryPages[currentPagePath]?.menuItem.label ?? 'Empty')
        : 'Empty';
    final currentPage =
        currentPagePath != null ? _temporaryPages[currentPagePath] : null;

    final selector = GestureDetector(
      onTap: _showPageManagerDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(displayName),
            // Which page you are on is obvious; that operators cannot see it
            // is not, and it is the kind of thing that gets left switched off
            // once the page is finished.
            if (currentPage != null && !currentPage.published) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Draft — not published to the navigation menu',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off,
                        size: 16, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 4),
                    Text(
                      'Draft',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );

    // Wrap with right-click context menu that includes both direct actions
    // (Create New Page) and AI chat actions when page data is available.
    if (currentPagePath != null && currentPage != null) {
      return GestureDetector(
        onSecondaryTapUp: (details) {
          if (kChatEnabled) {
            _showPageSelectorContextMenu(
              details.globalPosition,
              currentPagePath,
              currentPage,
            );
          } else {
            // Without chat the only page-selector action is Create New Page.
            _showCreateNewPageContextMenu(details.globalPosition);
          }
        },
        child: selector,
      );
    }

    // No page selected -- still allow right-click to create a new page.
    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showCreateNewPageContextMenu(details.globalPosition);
      },
      child: selector,
    );
  }

  /// Shows a context menu for the page selector with "Create New Page" and
  /// AI actions. Intercepts the [kCreateNewPageAction] sentinel to open the
  /// page manager dialog instead of chat.
  Future<void> _showPageSelectorContextMenu(
    Offset position,
    String pagePath,
    AssetPage page,
  ) async {
    final menuItems = buildPageSelectorMenuItems(pagePath, page);

    final result = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        for (var i = 0; i < menuItems.length; i++) ...[
          // Add a divider after "Create New Page" to separate direct actions
          // from AI actions.
          if (i == 1) const PopupMenuDivider(),
          PopupMenuItem<int>(
            value: i,
            child: ListTile(
              leading: Icon(menuItems[i].icon),
              title: Text(menuItems[i].label),
              dense: true,
            ),
          ),
        ],
      ],
    );

    if (result == null || !mounted) return;

    final item = menuItems[result];

    // Intercept "Create New Page" -- open the page manager dialog directly.
    if (item.prefillText == kCreateNewPageAction) {
      _showPageManagerDialog();
      return;
    }

    // Otherwise delegate to AI chat action.
    if (item.sendImmediately) {
      AiContextAction.openChatAndSend(ref: ref, message: item.prefillText);
    } else {
      ChatContext? chatContext;
      if (item.contextBlock != null) {
        chatContext = ChatContext(
          label: item.contextLabel ?? item.label,
          type: item.contextType,
          contextBlock: item.contextBlock!,
        );
      }
      AiContextAction.openChat(
        ref: ref,
        prefillText: item.prefillText,
        context: chatContext,
      );
    }
  }

  /// Shows a minimal context menu with just "Create New Page" when no page
  /// is currently selected.
  Future<void> _showCreateNewPageContextMenu(Offset position) async {
    final result = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'create',
          child: ListTile(
            leading: Icon(Icons.add_circle_outline),
            title: Text('Create New Page'),
            dense: true,
          ),
        ),
      ],
    );

    if (result == 'create' && mounted) {
      _showPageManagerDialog();
    }
  }

  /// Returns page paths that are not referenced as children of any OTHER page.
  List<String> _getRootPageNames() {
    final childPaths = <String>{};
    for (final entry in _temporaryPages.entries) {
      PageManager.collectChildPaths(
          entry.value.menuItem.children, childPaths, entry.key);
    }
    final roots = _temporaryPages.keys
        .where((path) => !childPaths.contains(path))
        .toList();
    roots.sort((a, b) {
      final pa = _temporaryPages[a]?.navigationPriority ?? 999;
      final pb = _temporaryPages[b]?.navigationPriority ?? 999;
      return pa.compareTo(pb);
    });
    return roots;
  }

  /// Top-level items the app registered itself (Alarm View, Advanced, ...),
  /// keyed by path. They are not pages, so the dialog can only reorder them.
  /// Built-in destinations whose menu placement the operator may change
  /// between the top level and the Advanced section. Placement is recorded
  /// as membership in the shared top-level order — no second key to drift.
  static const Set<String> movableBuiltinPaths = {AppRoutes.historyView};

  /// Whether the operator's (unsaved) arrangement has [path] at the top
  /// level rather than under Advanced.
  bool _isBuiltinPromoted(String path) => _topLevelOrder.contains(path);

  /// Finds [path]'s menu item anywhere in the registry tree — movable
  /// built-ins live under Advanced by default, so a top-level scan misses
  /// them.
  MenuItem? _findRegistryItem(String path, [List<MenuItem>? items]) {
    for (final item in items ?? RouteRegistry().menuItems) {
      if (item.path == path) return item;
      final nested = _findRegistryItem(path, item.children);
      if (nested != null) return nested;
    }
    return null;
  }

  Map<String, MenuItem> _appRegisteredTopLevel() {
    final map = {
      for (final item in RouteRegistry().menuItems)
        if (item.path != null && !_temporaryPages.containsKey(item.path))
          item.path!: item,
    };
    // Movable built-ins follow the editor's (possibly unsaved) placement,
    // not the registry's — the registry only changes on restart.
    for (final path in movableBuiltinPaths) {
      final item = _findRegistryItem(path);
      if (item == null) continue; // app without this destination
      if (_isBuiltinPromoted(path)) {
        map.putIfAbsent(path, () => item);
      } else {
        map.remove(path);
      }
    }
    return map;
  }

  /// Movable built-ins currently placed under Advanced — offered a
  /// "move to top level" affordance below the list.
  List<MenuItem> _demotedMovableBuiltins() => [
        for (final path in movableBuiltinPaths)
          if (!_isBuiltinPromoted(path))
            if (_findRegistryItem(path) case final MenuItem item) item,
      ];

  /// Moves [path] to the top level: freezes the currently displayed
  /// arrangement into the order list and appends [path], so the promotion
  /// survives restarts (placement IS membership in the stored order).
  void _promoteBuiltin(String path, StateSetter dialogSetState) {
    setState(() {
      _topLevelOrder = [
        ..._getTopLevelPaths().where((p) => p != path),
        path,
      ];
      _navOrderDirty = true;
    });
    dialogSetState(() {});
  }

  /// Moves [path] back under Advanced by dropping it from the stored order.
  void _demoteBuiltin(String path, StateSetter dialogSetState) {
    setState(() {
      _topLevelOrder = [..._topLevelOrder.where((p) => p != path)];
      _navOrderDirty = true;
    });
    dialogSetState(() {});
  }

  /// Every top-level row of the Pages dialog — root pages and the app's own
  /// destinations — in navigation order.
  ///
  /// Rows the stored order does not know yet rank by the live registry order
  /// (what the running app currently shows); pages absent from both — drafts
  /// and pages created this session, which enter the registry only on restart
  /// — go last, in priority order.
  List<String> _getTopLevelPaths() {
    final pageRoots = _getRootPageNames();
    final externals = _appRegisteredTopLevel().keys.toList();

    final registryPaths = [
      for (final item in RouteRegistry().menuItems)
        if (item.path != null) item.path!,
    ];
    final rank = <String, int>{};
    for (final path in _topLevelOrder) {
      rank.putIfAbsent(path, () => rank.length);
    }
    var next = rank.length;
    for (final path in registryPaths) {
      rank.putIfAbsent(path, () => next++);
    }
    for (final path in pageRoots) {
      rank.putIfAbsent(path, () => next++);
    }

    final combined = [...pageRoots, ...externals];
    combined.sort((a, b) => rank[a]!.compareTo(rank[b]!));
    return combined;
  }

  void _showPageManagerDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final roots = _getTopLevelPaths();
          final appItems = _appRegisteredTopLevel();
          return StandardDialogFrame(
            title: 'Pages',
            // The restart caveat belongs with the change, not buried in the
            // button row it used to share with Close.
            subtitle: 'Navigation changes require an app restart',
            icon: Icons.menu_book,
            width: 590,
            child: SizedBox(
              width: 550,
              // StandardDialogFrame caps itself at 80% of the screen, so a
              // taller fixed box pushes the drop zone and the add buttons off
              // a short panel where they cannot be reached at all. Shrink to
              // whatever the frame can actually give, minus its own header.
              height:
                  math.min(550, MediaQuery.sizeOf(context).height * 0.8 - 120),
              child: Column(
                children: [
                  Text(
                    'Tap to select. Sections are navigation groups. Drag the '
                    'handle to reorder within a level; hold and drag a row '
                    'onto a section — or onto "Top level" — to move it there.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView(
                      key: _treeViewportKey,
                      scrollController: _treeScrollController,
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) {
                        _onReorderRoots(
                            roots, oldIndex, newIndex, dialogSetState);
                      },
                      children: [
                        for (int i = 0; i < roots.length; i++)
                          if (appItems.containsKey(roots[i]))
                            _buildAppItemNode(
                              appItems[roots[i]]!,
                              reorderIndex: i,
                              dialogSetState: dialogSetState,
                            )
                          else
                            _buildTreeNode(
                              roots[i],
                              dialogSetState,
                              dialogContext,
                              depth: 0,
                              reorderIndex: i,
                            ),
                      ],
                    ),
                  ),
                  _buildTopLevelDropZone(dialogSetState),
                  for (final item in _demotedMovableBuiltins())
                    ListTile(
                      key: ValueKey('advanced-builtin-${item.path}'),
                      dense: true,
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      subtitle: const Text('Built-in — in Advanced'),
                      trailing: TextButton.icon(
                        key: ValueKey('promote-builtin-${item.path}'),
                        icon: const Icon(Icons.vertical_align_top, size: 18),
                        label: const Text('Move to top level'),
                        onPressed: () =>
                            _promoteBuiltin(item.path!, dialogSetState),
                      ),
                    ),
                  const Divider(),
                  _buildAddButtons(null, dialogSetState, dialogContext),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The row's second line: what the entry is, and whether operators can see
  /// it. Null when there is nothing to say (a plain, published page).
  Widget? _treeNodeSubtitle({required bool isSection, required bool isDraft}) {
    final parts = [
      if (isSection) 'Section',
      if (isDraft) 'Draft — not published',
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' · '));
  }

  /// Publishes or unpublishes [pagePath].
  ///
  /// Nothing about the page itself changes — it keeps its path, its assets and
  /// its place in the tree, and stays editable here. Only whether
  /// `getRootMenuItems` hands it to the app's menu and router does, which the
  /// running app picks up on its next start (as the dialog's subtitle warns).
  void _setPagePublished(
    String pagePath,
    bool published,
    StateSetter dialogSetState,
  ) {
    final page = _temporaryPages[pagePath];
    if (page == null || page.published == published) return;
    _saveToHistory();
    setState(() {
      _temporaryPages[pagePath] = page.copyWith(published: published);
      _updateCurrentJson();
    });
    dialogSetState(() {});
  }

  Widget _buildTreeNode(
    String pageName,
    StateSetter dialogSetState,
    BuildContext dialogContext, {
    required int depth,
    required int reorderIndex,
  }) {
    final page = _temporaryPages[pageName];
    if (page == null) return SizedBox(key: ValueKey(pageName));

    final isSelected = _currentPage == pageName;
    final displayName = page.menuItem.label;
    final hasChildren = page.menuItem.children.isNotEmpty;
    // An empty section is still a section — otherwise a freshly created one
    // would render as a page and could never receive children.
    final isSection = page.menuItem.isNavigationSection;
    final isDraft = !page.published;

    Widget row = ListTile(
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: reorderIndex,
            child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
          ),
          const SizedBox(width: 4),
          Icon(
            page.menuItem.icon,
            color: isSelected && !isSection
                ? Theme.of(dialogContext).colorScheme.primary
                : null,
          ),
        ],
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight:
              isSelected && !isSection ? FontWeight.bold : FontWeight.normal,
          color: isSelected && !isSection
              ? Theme.of(dialogContext).colorScheme.primary
              : null,
        ),
      ),
      subtitle: _treeNodeSubtitle(isSection: isSection, isDraft: isDraft),
      selected: isSelected && !isSection,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSection && depth < 3)
            PopupMenuButton<String>(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Add child',
              onSelected: (value) {
                _addItem(
                  parentName: pageName,
                  isSection: value == 'section',
                  dialogSetState: dialogSetState,
                  dialogContext: dialogContext,
                );
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'page',
                  child: Text('Add Page'),
                ),
                const PopupMenuItem(
                  value: 'section',
                  child: Text('Add Section'),
                ),
              ],
            )
          else if (isSection)
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Add page',
              onPressed: () => _addItem(
                parentName: pageName,
                isSection: false,
                dialogSetState: dialogSetState,
                dialogContext: dialogContext,
              ),
            ),
          IconButton(
            icon: Icon(
              isDraft ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: isDraft ? Theme.of(dialogContext).colorScheme.error : null,
            ),
            onPressed: () =>
                _setPagePublished(pageName, isDraft, dialogSetState),
            tooltip: isDraft
                ? (isSection
                    ? 'Publish section'
                    : 'Publish — operators can reach it')
                : (isSection
                    ? 'Unpublish section and everything in it'
                    : 'Unpublish — keep editing, hide from operators'),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            onPressed: () =>
                _showMoveDialog(pageName, dialogSetState, dialogContext),
            tooltip: isSection ? 'Move section' : 'Move to section',
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () =>
                _editPage(pageName, page, dialogSetState, dialogContext),
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18),
            onPressed: () =>
                _deletePage(pageName, dialogSetState, dialogContext),
            tooltip: 'Delete',
          ),
        ],
      ),
      onTap: isSection
          ? null
          : () {
              setState(() => _currentPage = pageName);
              Navigator.pop(dialogContext);
            },
    );

    if (kChatEnabled) {
      row = AiContextMenuWrapper(
        menuItems: [
          AiMenuItem(
            label: 'Describe this page',
            prefillText:
                'Describe page "$displayName" (key: $pageName) — what assets does it contain and what is it monitoring?',
          ),
          AiMenuItem(
            label: 'Improve layout',
            prefillText:
                'Review page "$displayName" (key: $pageName) and suggest layout improvements or missing assets.',
          ),
          AiMenuItem(
            label: 'Duplicate with AI',
            prefillText:
                'Create a new page similar to "$displayName" (key: $pageName) but for [describe the target system].',
          ),
        ],
        child: row,
      );
    }

    return Padding(
      key: ValueKey(pageName),
      padding: EdgeInsets.only(left: depth > 0 ? 20.0 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _draggableRow(
            pageName: pageName,
            page: page,
            depth: depth,
            isSection: isSection,
            row: row,
            dialogSetState: dialogSetState,
          ),
          // Render children recursively with reordering
          if (hasChildren)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                _onReorderChildren(
                    pageName, oldIndex, newIndex, dialogSetState);
              },
              children: [
                for (int i = 0; i < page.menuItem.children.length; i++)
                  if (page.menuItem.children[i].path == pageName)
                    _buildSelfRefChild(
                      page.menuItem.children[i],
                      pageName,
                      dialogSetState,
                      dialogContext,
                      depth: depth + 1,
                      reorderIndex: i,
                    )
                  else
                    _buildTreeNode(
                      page.menuItem.children[i].path ?? '',
                      dialogSetState,
                      dialogContext,
                      depth: depth + 1,
                      reorderIndex: i,
                    ),
              ],
            ),
        ],
      ),
    );
  }

  /// Renders a self-referencing child as a leaf page.
  /// E.g. the "IOs" entry has label "Diagnostics" with child {label: "IOs"}.
  /// The child is the actual clickable page that selects this entry for editing.
  Widget _buildSelfRefChild(
    MenuItem childItem,
    String mapKey,
    StateSetter dialogSetState,
    BuildContext dialogContext, {
    required int depth,
    required int reorderIndex,
  }) {
    final isSelected = _currentPage == mapKey;
    final page = _temporaryPages[mapKey];

    return Padding(
      key: ValueKey('selfref-$mapKey'),
      padding: const EdgeInsets.only(left: 20.0),
      child: ListTile(
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: reorderIndex,
              child:
                  const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            Icon(
              childItem.icon,
              color: isSelected
                  ? Theme.of(dialogContext).colorScheme.primary
                  : null,
            ),
          ],
        ),
        title: Text(
          childItem.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color:
                isSelected ? Theme.of(dialogContext).colorScheme.primary : null,
          ),
        ),
        selected: isSelected,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (page != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _editSelfRefChild(
                    mapKey, childItem, dialogSetState, dialogContext),
                tooltip: 'Edit',
              ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18),
              onPressed: () =>
                  _deletePage(mapKey, dialogSetState, dialogContext),
              tooltip: 'Delete',
            ),
          ],
        ),
        onTap: () {
          setState(() => _currentPage = mapKey);
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  /// A top-level destination the app registered itself. It has no page to
  /// select, edit or publish here — the row exists to be dragged into order.
  Widget _buildAppItemNode(MenuItem item,
      {required int reorderIndex, StateSetter? dialogSetState}) {
    final movable =
        item.path != null && movableBuiltinPaths.contains(item.path);
    return ListTile(
      key: ValueKey('app-item-${item.path}'),
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: reorderIndex,
            child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
          ),
          const SizedBox(width: 4),
          Icon(item.icon),
        ],
      ),
      title: Text(item.label),
      subtitle: const Text('Built-in — drag to reorder'),
      trailing: movable && dialogSetState != null
          ? IconButton(
              key: ValueKey('demote-builtin-${item.path}'),
              icon: const Icon(Icons.subdirectory_arrow_right, size: 18),
              tooltip: 'Move into Advanced',
              onPressed: () => _demoteBuiltin(item.path!, dialogSetState),
            )
          : null,
    );
  }

  void _onReorderRoots(
    List<String> roots,
    int oldIndex,
    int newIndex,
    StateSetter dialogSetState,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;
    setState(() {
      final movedName = roots[oldIndex];
      roots.removeAt(oldIndex);
      roots.insert(newIndex, movedName);
      // The full mixed order is what gets persisted; the per-page priorities
      // are kept in step so page-only consumers (getRootMenuItems) agree.
      _topLevelOrder = List.of(roots);
      _navOrderDirty = true;
      var pageIndex = 0;
      for (final path in roots) {
        final page = _temporaryPages[path];
        if (page == null) continue;
        _temporaryPages[path] = page.copyWith(navigationPriority: pageIndex++);
      }
      _updateCurrentJson();
    });
    dialogSetState(() {});
  }

  void _onReorderChildren(
    String parentName,
    int oldIndex,
    int newIndex,
    StateSetter dialogSetState,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;
    setState(() {
      final parent = _temporaryPages[parentName]!;
      final children = List<MenuItem>.from(parent.menuItem.children);
      final moved = children.removeAt(oldIndex);
      children.insert(newIndex, moved);
      _temporaryPages[parentName] = parent.copyWith(
          menuItem: parent.menuItem.copyWith(children: children));
      // Update navigationPriority on each child page
      for (int i = 0; i < children.length; i++) {
        final childPath = children[i].path ?? '';
        final childPage = _temporaryPages[childPath];
        if (childPage != null) {
          _temporaryPages[childPath] =
              childPage.copyWith(navigationPriority: i);
        }
      }
      _updateCurrentJson();
    });
    dialogSetState(() {});
  }

  /// Edit a self-referencing child's properties (label, path, icon).
  /// Updates both the child MenuItem in the parent and the map entry.
  void _editSelfRefChild(
    String mapKey,
    MenuItem childItem,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final page = _temporaryPages[mapKey]!;
    // Create a temporary AssetPage with the child's MenuItem for editing
    final childPage = page.copyWith(menuItem: childItem);

    showDialog(
      context: dialogContext,
      builder: (ctx) => StandardDialogFrame(
        title: 'Edit page',
        icon: Icons.edit,
        width: 440,
        child: SizedBox(
          width: 400,
          child: CreatePageWidget(
            initialPage: childPage,
            basePath: _buildBasePath(mapKey),
            onSave: (updatedPage) {
              setState(() {
                // Update the child MenuItem in the parent's children list
                final parentPage = _temporaryPages[mapKey]!;
                final updatedChildren = parentPage.menuItem.children.map((c) {
                  if (c.path == childItem.path) {
                    return c.copyWith(
                      label: updatedPage.menuItem.label,
                      path: updatedPage.menuItem.path,
                      icon: updatedPage.menuItem.icon,
                    );
                  }
                  return c;
                }).toList();
                _temporaryPages[mapKey] = parentPage.copyWith(
                  menuItem: parentPage.menuItem.copyWith(
                    children: updatedChildren,
                  ),
                  mirroringDisabled: updatedPage.mirroringDisabled,
                  navigationPriority: updatedPage.navigationPriority,
                  published: updatedPage.published,
                );
                _updateCurrentJson();
              });
              dialogSetState(() {});
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAddButtons(
    String? parentName,
    StateSetter dialogSetState,
    BuildContext dialogContext, {
    int depth = 0,
  }) {
    if (depth >= 3) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Page'),
          onPressed: () => _addItem(
            parentName: parentName,
            isSection: false,
            dialogSetState: dialogSetState,
            dialogContext: dialogContext,
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.create_new_folder, size: 16),
          label: const Text('Section'),
          onPressed: () => _addItem(
            parentName: parentName,
            isSection: true,
            dialogSetState: dialogSetState,
            dialogContext: dialogContext,
          ),
        ),
      ],
    );
  }

  String _buildBasePath(String? parentPath) {
    if (parentPath == null) return '';
    final page = _temporaryPages[parentPath];
    if (page == null) return '';
    // Since all pages/sections now have paths, just use the parent's path
    return page.menuItem.path ?? '';
  }

  String? _findParentOf(String childPath) {
    for (final entry in _temporaryPages.entries) {
      if (entry.key != childPath &&
          entry.value.menuItem.children.any((c) => c.path == childPath)) {
        return entry.key;
      }
    }
    return null;
  }

  /// How deep a section may sit and still take children, matching the limit
  /// the "Add Page / Add Section" buttons already enforce.
  static const int _maxSectionDepth = 3;

  /// How close to the tree's edge a dragged row must get before the list
  /// starts scrolling, and the most it scrolls per frame at the very edge.
  static const double _autoScrollBand = 56;
  static const double _autoScrollMaxStep = 12;

  /// Scrolls the tree while a dragged row sits in the top or bottom band, so
  /// a section below the fold can still be reached. Speed ramps with how far
  /// into the band the pointer is.
  void _updateAutoScroll(Offset globalPosition) {
    final box =
        _treeViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_treeScrollController.hasClients) {
      _stopAutoScroll();
      return;
    }

    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final y = globalPosition.dy;

    double ratio = 0;
    if (y < top + _autoScrollBand) {
      ratio = -(top + _autoScrollBand - y) / _autoScrollBand;
    } else if (y > bottom - _autoScrollBand) {
      ratio = (y - (bottom - _autoScrollBand)) / _autoScrollBand;
    }
    _autoScrollStep = ratio.clamp(-1.0, 1.0) * _autoScrollMaxStep;

    if (_autoScrollStep == 0) {
      _stopAutoScroll();
    } else {
      _autoScrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _autoScrollTick(),
      );
    }
  }

  void _autoScrollTick() {
    if (!_treeScrollController.hasClients) {
      _stopAutoScroll();
      return;
    }
    final position = _treeScrollController.position;
    final target = (position.pixels + _autoScrollStep)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return; // Already against the end.
    _treeScrollController.jumpTo(target);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollStep = 0;
  }

  /// Makes a tree row draggable onto another section, and — when the row is a
  /// section — a drop target for other rows.
  ///
  /// The drag starts on a long press rather than immediately: the row sits
  /// inside the dialog's scrollable, and an immediate [Draggable] would eat
  /// the vertical drags that scroll the list. The drag handle keeps its own
  /// gesture, so it still reorders within the level.
  Widget _draggableRow({
    required String pageName,
    required AssetPage page,
    required int depth,
    required bool isSection,
    required Widget row,
    required StateSetter dialogSetState,
  }) {
    void setDragging(String? path) {
      if (path == null) _stopAutoScroll();
      setState(() => _dragPagePath = path);
      dialogSetState(() {});
    }

    final draggable = LongPressDraggable<String>(
      data: pageName,
      onDragStarted: () => setDragging(pageName),
      onDragUpdate: (details) => _updateAutoScroll(details.globalPosition),
      onDragEnd: (_) => setDragging(null),
      onDraggableCanceled: (_, __) => setDragging(null),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(page.menuItem.icon, size: 18),
              const SizedBox(width: 8),
              Text(page.menuItem.label),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: row,
    );

    if (!isSection) return draggable;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _moveBlockedReason(details.data, pageName, depth) == null,
      onAcceptWithDetails: (details) =>
          _movePage(details.data, pageName, dialogSetState),
      builder: (context, candidate, rejected) {
        final scheme = Theme.of(context).colorScheme;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: candidate.isEmpty ? null : scheme.primaryContainer,
            border: candidate.isEmpty
                ? null
                : Border.all(color: scheme.primary, width: 2),
          ),
          child: draggable,
        );
      },
    );
  }

  /// Drop area that un-nests an item.
  ///
  /// Always rendered, not just mid-drag: appearing on drag start would reflow
  /// the tree and slide the row out from under the pointer.
  Widget _buildTopLevelDropZone(StateSetter dialogSetState) {
    final dragging = _dragPagePath;
    final wouldTake = dragging != null && _findParentOf(dragging) != null;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _findParentOf(details.data) != null,
      onAcceptWithDetails: (details) =>
          _movePage(details.data, null, dialogSetState),
      builder: (context, candidate, rejected) {
        final scheme = Theme.of(context).colorScheme;
        final active = candidate.isNotEmpty;
        return Container(
          height: 40,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active ? scheme.primaryContainer : null,
            border: Border.all(
              color:
                  active || wouldTake ? scheme.primary : scheme.outlineVariant,
              width: active ? 2 : 1,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.north, size: 16, color: scheme.outline),
                const SizedBox(width: 8),
                Text(
                  wouldTake || active
                      ? 'Drop here to move to the top level'
                      : 'Top level',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Every section in the tree, in the order the Pages dialog renders them,
  /// with the depth used to indent them in the move picker.
  List<({String path, String label, IconData icon, int depth})>
      _collectSectionTargets() {
    final targets = <({String path, String label, IconData icon, int depth})>[];
    final seen = <String>{};

    void walk(String path, int depth) {
      if (!seen.add(path)) return;
      final page = _temporaryPages[path];
      if (page == null) return;
      if (page.menuItem.isNavigationSection) {
        targets.add((
          path: path,
          label: page.menuItem.label,
          icon: page.menuItem.icon,
          depth: depth,
        ));
      }
      for (final child in page.menuItem.children) {
        final childPath = child.path;
        // Self-references are the section's own landing page, not a child.
        if (childPath == null || childPath.isEmpty || childPath == path) {
          continue;
        }
        walk(childPath, depth + 1);
      }
    }

    for (final root in _getRootPageNames()) {
      walk(root, 0);
    }
    return targets;
  }

  /// Why [targetPath] cannot receive [pagePath], or null when it can.
  String? _moveBlockedReason(String pagePath, String targetPath, int depth) {
    if (targetPath == pagePath) return 'This is the item being moved';
    if (targetPath == _findParentOf(pagePath)) return 'Already here';
    if (PageManager.isDescendantOf(_temporaryPages,
        ancestor: pagePath, candidate: targetPath)) {
      return 'Inside the item being moved';
    }
    if (depth >= _maxSectionDepth) return 'Nesting limit reached';
    return null;
  }

  /// Destination picker for moving a page or section somewhere else.
  ///
  /// A flat, indented list rather than drag-and-drop: the Pages dialog already
  /// uses nested [ReorderableListView]s for ordering within a level, and those
  /// swallow drags, so cross-section moves get their own explicit gesture that
  /// also works on a touch panel.
  void _showMoveDialog(
    String pagePath,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final page = _temporaryPages[pagePath];
    if (page == null) return;
    final isRoot = _findParentOf(pagePath) == null;
    final targets = _collectSectionTargets();

    showDialog(
      context: dialogContext,
      builder: (ctx) => StandardDialogFrame(
        title: 'Move "${page.menuItem.label}"',
        subtitle: 'Pick the section it should live under. The address stays '
            'the same, so links to it keep working.',
        icon: Icons.drive_file_move_outline,
        width: 440,
        height: 460,
        // The list scrolls itself; an outer scroll would unbound its height.
        scrollable: false,
        closeLabel: 'Cancel',
        child: ListView(
          children: [
            _buildMoveTarget(
              ctx: ctx,
              icon: Icons.north,
              label: 'Top level',
              depth: 0,
              blockedReason: isRoot ? 'Already here' : null,
              onMove: () => _movePage(pagePath, null, dialogSetState),
            ),
            if (targets.isNotEmpty) const Divider(height: 1),
            for (final target in targets)
              _buildMoveTarget(
                ctx: ctx,
                icon: target.icon,
                label: target.label,
                depth: target.depth,
                blockedReason:
                    _moveBlockedReason(pagePath, target.path, target.depth),
                onMove: () => _movePage(pagePath, target.path, dialogSetState),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveTarget({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required int depth,
    required String? blockedReason,
    required VoidCallback onMove,
  }) {
    final enabled = blockedReason == null;
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: ListTile(
        dense: true,
        enabled: enabled,
        leading: Icon(icon),
        title: Text(label),
        subtitle: blockedReason == null ? null : Text(blockedReason),
        onTap: enabled
            ? () {
                Navigator.pop(ctx);
                onMove();
              }
            : null,
      ),
    );
  }

  /// Applies a move and reports it, since the tree may scroll the moved item
  /// out of view.
  void _movePage(
    String pagePath,
    String? newParentPath,
    StateSetter dialogSetState,
  ) {
    final label = _temporaryPages[pagePath]?.menuItem.label ?? pagePath;
    final destination = newParentPath == null
        ? 'the top level'
        : '"${_temporaryPages[newParentPath]?.menuItem.label ?? newParentPath}"';

    _saveToHistory();
    setState(() {
      _temporaryPages = PageManager.movePage(
        _temporaryPages,
        pagePath: pagePath,
        newParentPath: newParentPath,
      );
      _updateCurrentJson();
    });
    dialogSetState(() {});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved "$label" to $destination.')),
    );
  }

  void _addItem({
    required String? parentName,
    required bool isSection,
    required StateSetter dialogSetState,
    required BuildContext dialogContext,
  }) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => StandardDialogFrame(
        title: isSection ? 'Add section' : 'Add page',
        icon: isSection ? Icons.create_new_folder : Icons.note_add,
        width: 440,
        child: SizedBox(
          width: 400,
          child: CreatePageWidget(
            isSection: isSection,
            basePath: _buildBasePath(parentName),
            onSave: (page) {
              final newPath = page.menuItem.path ?? '';
              if (_temporaryPages.containsKey(newPath)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                        'A page with path "$newPath" already exists. Please choose a different name.'),
                  ),
                );
                return;
              }
              setState(() {
                // Auto-assign priority: put at end of its level
                final int priority;
                if (parentName != null) {
                  final parent = _temporaryPages[parentName];
                  priority = parent?.menuItem.children.length ?? 0;
                } else {
                  priority = _getRootPageNames().length;
                }
                final pageWithPriority =
                    page.copyWith(navigationPriority: priority);
                _temporaryPages[newPath] = pageWithPriority;
                // Add as child of parent if specified
                if (parentName != null) {
                  final parent = _temporaryPages[parentName];
                  if (parent != null) {
                    final updatedChildren =
                        List<MenuItem>.from(parent.menuItem.children)
                          ..add(pageWithPriority.menuItem);
                    _temporaryPages[parentName] = parent.copyWith(
                      menuItem:
                          parent.menuItem.copyWith(children: updatedChildren),
                    );
                  }
                }
                if (!isSection) {
                  _currentPage = newPath;
                }
                _updateCurrentJson();
              });
              dialogSetState(() {});
            },
          ),
        ),
      ),
    );
  }

  void _editPage(
    String pagePath,
    AssetPage page,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final isSection = page.menuItem.isNavigationSection;
    showDialog(
      context: dialogContext,
      builder: (ctx) => StandardDialogFrame(
        title: 'Edit',
        icon: Icons.edit,
        width: 440,
        child: SizedBox(
          width: 400,
          child: CreatePageWidget(
            initialPage: page,
            isSection: isSection,
            basePath: _buildBasePath(_findParentOf(pagePath)),
            onSave: (updatedPage) {
              final newPath = updatedPage.menuItem.path ?? '';
              if (newPath != pagePath && _temporaryPages.containsKey(newPath)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                        'A page with path "$newPath" already exists. Please choose a different name.'),
                  ),
                );
                return;
              }
              setState(() {
                if (newPath != pagePath) {
                  _temporaryPages.remove(pagePath);
                  // Update parent references
                  _updateChildPathInParents(
                      pagePath, newPath, updatedPage.menuItem);
                  if (_currentPage == pagePath) {
                    _currentPage = newPath;
                  }
                }
                _temporaryPages[newPath] = updatedPage;
                _updateCurrentJson();
              });
              dialogSetState(() {});
            },
          ),
        ),
      ),
    );
  }

  void _updateChildPathInParents(
      String oldPath, String newPath, MenuItem newMenuItem) {
    final updates = <String, AssetPage>{};
    for (final entry in _temporaryPages.entries) {
      final page = entry.value;
      final updated = _updatePathInChildren(
          page.menuItem.children, oldPath, newPath, newMenuItem);
      if (updated != null) {
        updates[entry.key] =
            page.copyWith(menuItem: page.menuItem.copyWith(children: updated));
      }
    }
    _temporaryPages.addAll(updates);
  }

  List<MenuItem>? _updatePathInChildren(List<MenuItem> children, String oldPath,
      String newPath, MenuItem newMenuItem) {
    bool changed = false;
    final result = children.map((child) {
      MenuItem updated = child;
      if (child.path == oldPath) {
        changed = true;
        updated = child.copyWith(
          label: newMenuItem.label,
          path: newPath,
          icon: newMenuItem.icon,
          isSection: newMenuItem.isSection,
        );
      }
      final subUpdated = _updatePathInChildren(
          updated.children, oldPath, newPath, newMenuItem);
      if (subUpdated != null) {
        changed = true;
        updated = updated.copyWith(children: subUpdated);
      }
      return updated;
    }).toList();
    return changed ? result : null;
  }

  void _deletePage(
    String pagePath,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final displayName = _temporaryPages[pagePath]?.menuItem.label ?? pagePath;
    showConfirmDialog(
      context: dialogContext,
      title: 'Delete',
      message: 'Delete "$displayName"?',
      confirmLabel: 'Delete',
      destructive: true,
    ).then((confirmed) {
      if (!confirmed) return;
      setState(() {
        _temporaryPages.remove(pagePath);
        // Remove from parent children lists
        _removeChildFromParents(pagePath);
        if (_currentPage == pagePath) {
          _currentPage = _temporaryPages.keys.firstOrNull;
        }
        _updateCurrentJson();
      });
      dialogSetState(() {});
    });
  }

  void _removeChildFromParents(String path) {
    final updates = <String, AssetPage>{};
    for (final entry in _temporaryPages.entries) {
      final page = entry.value;
      final updated = _removeFromChildren(page.menuItem.children, path);
      if (updated != null) {
        updates[entry.key] =
            page.copyWith(menuItem: page.menuItem.copyWith(children: updated));
      }
    }
    _temporaryPages.addAll(updates);
  }

  List<MenuItem>? _removeFromChildren(List<MenuItem> children, String path) {
    bool changed = false;
    final result = <MenuItem>[];
    for (final child in children) {
      if (child.path == path) {
        changed = true;
        continue;
      }
      final subUpdated = _removeFromChildren(child.children, path);
      if (subUpdated != null) {
        changed = true;
        result.add(child.copyWith(children: subUpdated));
      } else {
        result.add(child);
      }
    }
    return changed ? result : null;
  }
}

class _PaletteItem extends StatelessWidget {
  final Type assetType;
  final Asset asset;

  const _PaletteItem({
    required this.assetType,
    required this.asset,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<Type>(
      data: assetType,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 80,
          height: 80,
          child: Opacity(
            opacity: 0.7,
            child: asset.build(context),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildThumbnail(context),
      ),
      child: _buildThumbnail(context),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 80,
                height: 80,
                child: ClipRect(
                  child: IgnorePointer(
                    child: asset.build(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            asset.displayName,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset current;

  SelectionBoxPainter({required this.start, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromPoints(start, current);
    canvas.drawRect(rect, paint);

    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(SelectionBoxPainter oldDelegate) {
    return start != oldDelegate.start || current != oldDelegate.current;
  }
}
