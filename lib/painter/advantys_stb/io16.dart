import 'package:flutter/material.dart';
import 'package:tfc/painter/beckhoff/io8.dart' show BaseLedBlockPainter, IOState;
import 'ddi3725.dart' show stbLedPanelColor;

// Re-export Schneider/Beckhoff cream `bodyColor` from this STB entry point so
// downstream STB module body painters (DDI3725, DDO3705, NIP2311, PDT3100,
// Plan 02+) import cream from `package:tfc/painter/advantys_stb/io16.dart`
// rather than reaching into the Beckhoff package directly. This keeps the
// brownfield import boundary clean: only this file imports Beckhoff internals.
export 'package:tfc/painter/beckhoff/io8.dart' show bodyColor;

/// Channel-to-bit mapping convention for the Advantys STB DI/DO modules.
///
/// `lsbFirst` — bit 0 → channel 1, bit 15 → channel 16. Matches the Beckhoff
/// EL1008 convention. This is the locked default (per
/// `.planning/phases/01-stbddi3725-16-ch-digital-input/01-CONTEXT.md`
/// §Bit-Ordering) and the convention all Phase 1 + Phase 2 modules consume.
///
/// `msbFirst` — bit 15 → channel 1, bit 0 → channel 16. Reserved for the case
/// where Schneider backend confirmation surfaces an MSB-first convention.
/// Flipping the default of `kSTBChannelBitOrder` to this value + updating the
/// three assertion expectations in `test/page_creator/assets/advantys_stb_test.dart`
/// is the only change needed — painter math, widget logic, and dialog wiring
/// are unaffected.
enum STBBitOrder { lsbFirst, msbFirst }

/// Module-wide channel-to-bit mapping for Advantys STB DI/DO modules.
///
/// Single source of truth — DDI3725 (this phase) and DDO3705 (Phase 2) import
/// this constant via `show kSTBChannelBitOrder` so the convention cannot drift
/// between input and output modules.
const STBBitOrder kSTBChannelBitOrder = STBBitOrder.lsbFirst;

/// Converts a 16-bit raw input/output bitmask (and optional per-channel
/// `int8[16]` force-values array) into a 16-element `List<IOState>` suitable
/// for `IO16LedBlockPainter`.
///
/// Bit-to-channel mapping follows [kSTBChannelBitOrder]:
/// - `STBBitOrder.lsbFirst` → channel `i+1` lives at bit `i` (bit 0 = ch1).
/// - `STBBitOrder.msbFirst` → channel `i+1` lives at bit `15 - i` (bit 15 = ch1).
///
/// `forceValues` semantics (matches `BeckhoffEL1008._ledStates` at
/// `lib/page_creator/assets/beckhoff.dart` ~lines 1290-1299):
/// - `forceValues[i] == 0` (or `null` / array shorter than 16) → use raw bit.
/// - `forceValues[i] == 1` → `IOState.forcedLow` (raw bit ignored).
/// - `forceValues[i] == 2` → `IOState.forcedHigh` (raw bit ignored).
///
/// Force-collapse rule: forced channels render their forced state only; the
/// underlying raw wire bit is NOT surfaced. Locked by REQUIREMENTS DDI-05.
/// A corner-pip "raw state under force" variant is deferred (DDI-FUT-01).
List<IOState> bitmaskToLedStates(int raw, {List<int>? forceValues}) {
  return List<IOState>.generate(16, (int i) {
    if (forceValues != null && forceValues.length > i) {
      final int force = forceValues[i];
      if (force == 1) return IOState.forcedLow;
      if (force == 2) return IOState.forcedHigh;
    }
    final int bit =
        kSTBChannelBitOrder == STBBitOrder.lsbFirst ? i : (15 - i);
    return (raw & (1 << bit)) != 0 ? IOState.high : IOState.low;
  });
}

/// 16-LED block painter for Advantys STB 16-channel I/O modules (DDI3725,
/// DDO3705). Sibling to `IO8LedBlockPainter` / `IO6LedBlockPainter` in
/// `package:tfc/painter/beckhoff/io8.dart`.
///
/// Layout: column-major 2 columns × 8 rows.
/// - `ledStates[0..7]` fill the LEFT column top→bottom (channels 1–8).
/// - `ledStates[8..15]` fill the RIGHT column top→bottom (channels 9–16).
///
/// The layout is locked by `.planning/research/photos/DDI3725_front_clean.png`
/// and `.planning/research/photos/momentum_stack_in_panel.png`. It is encoded
/// in the painter math, not parameterised — a future row-major or MSB variant
/// would land as a sibling painter.
class IO16LedBlockPainter extends BaseLedBlockPainter {
  /// `true` when the upstream module is in stale / disconnected state — the
  /// RDY indicator dot on the dark inset panel renders dim grey; `false`
  /// renders bright green. BATCH2 Defect G.
  final bool isStale;

  IO16LedBlockPainter({
    required super.ledStates,
    super.topLabels,
    required super.animation,
    this.isStale = false,
  }) : assert(ledStates.length == 16);

  @override
  void drawLeds(Canvas canvas, Size size) {
    // BATCH2 Defect G: rewrite to match real Schneider DDO3705 / DDI3725
    // hardware (per the user's reference photo). The LED block now renders:
    //
    //   1. A dark inset panel covering the full LED block area
    //      (`stbLedPanelColor`) — was the cream module body bleeding through.
    //   2. A small "RDY" status row at the top with a green-when-alive,
    //      grey-when-stale LED dot + the literal "RDY" caption.
    //   3. Sixteen channel LEDs in a 2-column × 8-row grid below the RDY row.
    //      Each LED is a small squared rounded-rectangle (RRect) — NOT a
    //      circle (the previous round-dot fix overcorrected from the
    //      original "venetian-blind bars"; the real shape sits between).
    //   4. A numeric label "1".."16" to the LEFT of each LED, in light text
    //      on the dark panel.
    //
    // The base-painter's `drawLed` is NOT called — we override the full LED
    // block render. The `animation.value` is still honoured for the forced-
    // state pulsing red border.

    // 1. Dark inset panel background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = stbLedPanelColor,
    );

    // 2. "RDY" status row at the top — 18% of the LED block height.
    final rdyH = size.height * 0.18;
    final rdyRect = Rect.fromLTWH(0, 0, size.width, rdyH);
    _drawRdyRow(canvas, rdyRect);

    // 3. + 4. Channel-LED grid + numeric labels.
    final gridTop = rdyH;
    final gridRect =
        Rect.fromLTWH(0, gridTop, size.width, size.height - gridTop);
    _drawChannelGrid(canvas, gridRect);
  }

  /// "RDY" status row — a small green/grey LED dot followed by the literal
  /// "RDY" caption, centred vertically in `rect`. Sits on the dark inset
  /// panel so the caption uses light text.
  void _drawRdyRow(Canvas canvas, Rect rect) {
    const activeColor = Color(0xFF6CA545);
    final dotR = rect.height * 0.30;
    final dotCx = rect.left + rect.width * 0.18;
    final dotCy = rect.center.dy;
    final dotColor = isStale ? Colors.grey.shade500 : activeColor;
    canvas.drawCircle(Offset(dotCx, dotCy), dotR, Paint()..color = dotColor);
    canvas.drawCircle(
      Offset(dotCx, dotCy),
      dotR,
      Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = dotR * 0.18,
    );

    final captionLeft = dotCx + dotR + rect.width * 0.06;
    final captionMaxW = rect.right - captionLeft - rect.width * 0.05;
    final tp = TextPainter(
      text: TextSpan(
        text: 'RDY',
        style: TextStyle(
          color: Colors.grey.shade100,
          fontSize: rect.height * 0.50,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: captionMaxW);
    tp.paint(canvas, Offset(captionLeft, dotCy - tp.height / 2));
  }

  /// 2×8 grid of small squared LEDs with numeric labels. The grid is column-
  /// major: channels 1..8 fill the LEFT column top→bottom, channels 9..16
  /// the RIGHT column. Each cell renders `[number] [LED]` left-to-right.
  void _drawChannelGrid(Canvas canvas, Rect rect) {
    const cols = 2;
    const rows = 8;
    if (rect.width <= 0 || rect.height <= 0) return;

    final padX = rect.width * 0.03;
    final padY = rect.height * 0.03;
    final cellW = (rect.width - padX * (cols + 1)) / cols;
    final cellH = (rect.height - padY * (rows + 1)) / rows;
    if (cellW <= 0 || cellH <= 0) return;

    // LED slot: squared rounded-rect, ~1.5× width vs height with a small
    // corner radius. Sits on the RIGHT half of the cell; the channel
    // number sits on the LEFT half of the cell.
    final ledH = cellH * 0.70;
    final ledW = ledH * 1.50;
    // Clamp so the LED never exceeds half the cell width.
    final clampedLedW = ledW > cellW * 0.55 ? cellW * 0.55 : ledW;
    final labelMaxW = cellW - clampedLedW - padX;

    final borderStrokeW = (cellH * 0.08).clamp(0.5, 1.5);
    final basePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderStrokeW;

    for (int i = 0; i < 16; i++) {
      final int col = i ~/ 8;
      final int row = i % 8;
      final double cellX = rect.left + padX + col * (cellW + padX);
      final double cellY = rect.top + padY + row * (cellH + padY);

      // Numeric channel label (1..16).
      final labelTp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.grey.shade100,
            fontSize: cellH * 0.65,
            fontWeight: FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelMaxW > 0 ? labelMaxW : cellW * 0.40);
      labelTp.paint(
        canvas,
        Offset(
          cellX + (labelMaxW > 0 ? (labelMaxW - labelTp.width) : 0),
          cellY + (cellH - labelTp.height) / 2,
        ),
      );

      // Squared LED slot.
      final ledLeft = cellX + cellW - clampedLedW;
      final ledTop = cellY + (cellH - ledH) / 2;
      final ledRect = Rect.fromLTWH(ledLeft, ledTop, clampedLedW, ledH);
      _drawSquaredLed(canvas, ledRect, ledStates[i], basePaint);
    }
  }

  /// Draws a single squared LED — small rounded rectangle (RRect). Reads as
  /// real DIN-rail LED hardware (per the user's reference photo): white/light
  /// when ON, dark/grey when OFF, with a thin border. Forced states pulse
  /// red on the border (animation.value driven).
  void _drawSquaredLed(Canvas canvas, Rect rect, IOState state, Paint border) {
    const activeColor = Color(0xFF6CA545);
    const inactiveColor = Color(0xFF3A3A3A);
    const errorColor = Colors.red;

    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular((rect.height < rect.width ? rect.height : rect.width) *
          0.25),
    );

    Color fill;
    switch (state) {
      case IOState.error:
        fill = errorColor;
        break;
      case IOState.high:
      case IOState.forcedHigh:
        fill = activeColor;
        break;
      case IOState.low:
      case IOState.forcedLow:
        fill = inactiveColor;
        break;
    }
    canvas.drawRRect(rrect, Paint()..color = fill);

    // Border — pulses red for forced states (matches the Beckhoff convention).
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = border.strokeWidth
      ..color = state == IOState.forcedHigh || state == IOState.forcedLow
          ? Colors.red.withAlpha(animation.value)
          : border.color;
    canvas.drawRRect(rrect, stroke);
  }
}
