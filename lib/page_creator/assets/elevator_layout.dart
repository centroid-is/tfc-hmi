/// Pure-Dart layout helpers for the Elevator asset.
///
/// Isolates the off-by-one math (Pitfall 8) into a single unit-tested
/// function so the painter and the widget never reimplement the formula.
///
/// Coordinate convention (locked by ELEV-03 + 02-CONTEXT.md):
///   - 0% (progress=0.0) = platform's bottom edge touches bbox's bottom.
///   - 100% (progress=1.0) = platform's top edge is offset upward by
///     `clamp(maxChildHeight, 0, bboxHeight - platformHeight)` from the
///     bbox bottom. (Plan 260511-dxa / ELEV-10 — was the full bbox range
///     prior to this plan.)
///   - Y-axis grows downward (Flutter convention), so the returned value
///     is the platform's `Positioned.top` offset within the bbox.
library;

/// Returns the Y-offset (`Positioned.top`) of the platform's top edge
/// inside the bbox, given a normalised `progress` in [0.0, 1.0].
///
/// Formula (locked by Plan 260511-dxa / ELEV-10):
///   headroom        = bboxHeight - platformHeight
///   effectiveTravel = clamp(maxChildHeight, 0, headroom)
///   platformY       = headroom - progress * effectiveTravel
///
/// Travel range now equals the TALLEST attached child's height (clamped
/// to `bboxHeight - platformHeight` so the platform never overhangs the
/// bbox top). This closes the visual "freeze at top" bug from Plan 04-02:
/// children no longer need a defensive `max(0.0, ...)` clamp on their
/// `Positioned.top` because the range is sized to keep them inside the
/// bbox by construction.
///
/// Edge cases (verified by unit tests):
///   - `maxChildHeight=0` (no children): travel=0, platform pinned at the
///     bottom for all progress values. This is the safe default for the
///     painter when constructed without children (e.g., bare goldens).
///   - `maxChildHeight >= headroom`: travel clamps to headroom →
///     reproduces the old full-range behaviour exactly.
///   - `maxChildHeight < 0`: defensively clamped to 0.
///
/// At `progress=0.0` the platform always sits at `headroom` (bottom)
/// regardless of `maxChildHeight`. At `progress=1.0` the platform sits at
/// `headroom - effectiveTravel`.
///
/// The caller is responsible for clamping `progress` to [0.0, 1.0]; use
/// [platformProgress] to derive a clamped progress from a raw 0..100 PLC
/// value.
///
/// See `.planning/quick/260511-dxa-elevator-travel-range-equals-tallest-chi/`
/// for the derivation and rationale.
double platformOffsetTop(
  double progress,
  double bboxHeight,
  double platformHeight,
  double maxChildHeight,
) {
  final headroom = bboxHeight - platformHeight;
  final effectiveTravel = maxChildHeight.clamp(0.0, headroom);
  return headroom - progress * effectiveTravel;
}

/// Maps a raw 0..100 PLC value to a clamped 0..1 progress.
///
/// Locked semantics (CONTEXT §Position interpretation):
///   - Clamp to [0, 100] before dividing — out-of-range values silently
///     pin to the legal range. (ELEV-15 amber-outline fault rendering is
///     a Phase 4 concern and is intentionally NOT triggered here.)
///   - NaN is treated as 0.0 (defensive — caller should already guard,
///     but Dart's `clamp` returns NaN for NaN inputs which would break
///     downstream tween math).
double platformProgress(double rawValue) {
  if (rawValue.isNaN) return 0.0;
  final clamped = rawValue.clamp(0.0, 100.0);
  return clamped / 100.0;
}
