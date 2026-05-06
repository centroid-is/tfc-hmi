/// Pure-Dart layout helpers for the Elevator asset.
///
/// Isolates the off-by-one math (Pitfall 8) into a single unit-tested
/// function so the painter and the widget never reimplement the formula.
///
/// Coordinate convention (locked by ELEV-03 + 02-CONTEXT.md):
///   - 0% (progress=0.0) = platform's bottom edge touches bbox's bottom.
///   - 100% (progress=1.0) = platform's top edge touches bbox's top.
///   - Y-axis grows downward (Flutter convention), so the returned value
///     is the platform's `Positioned.top` offset within the bbox.
library;

/// Returns the Y-offset (`Positioned.top`) of the platform's top edge
/// inside the bbox, given a normalised `progress` in [0.0, 1.0].
///
/// Formula (locked, see PITFALLS.md Pitfall 8):
///   `(1 - progress) * (bboxHeight - platformHeight)`
///
/// At `progress=0.0` returns `bboxHeight - platformHeight` (platform
/// sits at the bottom). At `progress=1.0` returns `0.0` (platform sits
/// at the top). The platform-thickness subtraction guarantees the
/// platform never overhangs the bbox at progress=1.0.
///
/// The caller is responsible for clamping `progress` to [0.0, 1.0]; use
/// [platformProgress] to derive a clamped progress from a raw 0..100 PLC
/// value.
double platformOffsetTop(
  double progress,
  double bboxHeight,
  double platformHeight,
) {
  return (1.0 - progress) * (bboxHeight - platformHeight);
}
