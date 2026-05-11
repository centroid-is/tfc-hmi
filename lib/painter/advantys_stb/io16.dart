import 'package:flutter/material.dart';
import 'package:tfc/painter/beckhoff/io8.dart' show BaseLedBlockPainter, IOState;

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
  IO16LedBlockPainter({
    required super.ledStates,
    super.topLabels,
    required super.animation,
  }) : assert(ledStates.length == 16);

  @override
  void drawLeds(Canvas canvas, Size size) {
    // Independent x- and y-pads. Plan 02 deviation: the original Plan 01
    // sibling-painter pattern (IO8/IO6) uses `pad = size.width * 0.05` for
    // both axes because those painters render into tall-narrow blocks
    // (height >> width). The DDI3725 body painter feeds this painter a
    // wide-flat region (width >> height — roughly 200×66 px at the standard
    // 300px body height), and a single `width * 0.05` pad blows up cellH
    // negative. Use independent axis pads so the painter is correct for both
    // aspect ratios; the IO8/IO6 callers still get visually-identical output
    // because their pad was already isotropic for square-ish blocks.
    const cols = 2;
    const rows = 8;
    final padX = size.width * 0.05;
    final padY = size.height * 0.05;
    final cellW = (size.width - padX * (cols + 1)) / cols;
    final cellH = (size.height - padY * (rows + 1)) / rows;

    // Clamp the LED-border stroke so it never exceeds ~12% of the smaller
    // cell dimension — for the DDI3725 wide-flat block the row height is
    // ~5 px and a sibling-painter `size.width * 0.03` stroke would entirely
    // overpaint the green/grey fill. The IO8/IO6 callers feed tall-narrow
    // blocks where cellW/cellH are similar, so this clamp is a no-op for them.
    final unclampedStroke = size.width * 0.03;
    final maxStroke = (cellH < cellW ? cellH : cellW) * 0.12;
    final borderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          unclampedStroke < maxStroke ? unclampedStroke : maxStroke;

    // Column-major: i → (col: i ~/ 8, row: i % 8).
    // Channels 1–8 fill left column top→bottom, channels 9–16 right column.
    for (int i = 0; i < 16; i++) {
      final int col = i ~/ 8;
      final int row = i % 8;
      final double cx = padX + col * (cellW + padX);
      final double cy = padY + row * (cellH + padY);
      final cellRect = Rect.fromLTWH(cx, cy, cellW, cellH);
      drawLed(canvas, cellRect, ledStates[i], borderPaint);
    }
  }
}
