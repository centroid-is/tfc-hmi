---
phase: 01-stbddi3725-16-ch-digital-input
plan: 01
subsystem: ui
tags: [flutter, custompainter, bit-mapping, advantys-stb, schneider, painter-base, tdd]

# Dependency graph
requires:
  - phase: v1.0-elevator-sensor
    provides: BaseLedBlockPainter + IOState enum + bodyColor cream constant (lib/painter/beckhoff/io8.dart)
provides:
  - kSTBChannelBitOrder constant (LSB-first locked default)
  - STBBitOrder enum (lsbFirst | msbFirst)
  - bitmaskToLedStates(int raw, {List<int>? forceValues}) pure helper with force-collapse semantics
  - IO16LedBlockPainter (column-major 2×8 LED layout, sibling to IO8/IO6 painters)
  - Re-exported bodyColor cream from lib/painter/advantys_stb/io16.dart so downstream STB body painters import cream from STB, not Beckhoff
  - Library-public LED-drawing primitives on BaseLedBlockPainter (drawLed/drawLeds/drawBackground/drawBorder — enables cross-library subclassing)
affects: [01-02, 01-03, 01-04, 02-stbddo3705, 03-stbnip2311, 04-stbpdt3100, 05-advantys-stb-stack]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sibling painter pattern: per-channel-count painter file in lib/painter/{vendor}/{module}.dart"
    - "Pure helper for bit-math (bitmaskToLedStates) — painter/widget/dialog all consume it, never re-derive bit math"
    - "Module-level locked-convention constant (kSTBChannelBitOrder) imported via `show` across the milestone to prevent drift"
    - "Cream re-export through STB entry point (only one STB file imports Beckhoff internals)"
    - "TDD RED → GREEN gates: failing compile error first, then minimum-surface implementation"

key-files:
  created:
    - lib/painter/advantys_stb/io16.dart
    - test/page_creator/assets/advantys_stb_test.dart
  modified:
    - lib/painter/beckhoff/io8.dart (private LED-drawing methods promoted to library-public — see Deviations)

key-decisions:
  - "kSTBChannelBitOrder = STBBitOrder.lsbFirst (Beckhoff EL1008 parity). Backend confirmation flagged in test TODO before Plan 02 goldens lock."
  - "Force-collapse: forceValues[i] in {1,2} ignores raw bit and renders forcedLow/forcedHigh (matches BeckhoffEL1008._ledStates). No corner pip in v2.0 (DDI-FUT-01)."
  - "Column-major 2×8 layout encoded in painter math, not parameterised. A future row-major variant would land as a sibling painter."
  - "Renamed BaseLedBlockPainter LED-drawing methods from _drawX to drawX (Rule 3 — Dart library-private symbols are unreachable from cross-library subclasses). External callers unaffected; the public paint() entry point is unchanged."

patterns-established:
  - "STB sibling painter convention: extends Beckhoff BaseLedBlockPainter, lives under lib/painter/advantys_stb/, re-exports cream via STB entry point"
  - "Bit-convention lock pattern: const constant at top of painter file + one-line flip + three-assertion test makes the convention reversible"
  - "Force-collapse contract surfaced via pure helper, not embedded in painter or widget — keeps Phase 2 DDO3705 from re-deriving"

requirements-completed: [DDI-03, DDI-04, QUAL-02]

# Metrics
duration: 5min
completed: 2026-05-11
---

# Phase 1 Plan 01: TDD foundation for IO16LedBlockPainter + bit-order constant — Summary

**`IO16LedBlockPainter` (column-major 2×8) + locked LSB-first `kSTBChannelBitOrder` constant + `bitmaskToLedStates` pure helper, all gated by 9 RED→GREEN unit tests covering bit-mapping and force-collapse semantics.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-11T16:18:00Z
- **Completed:** 2026-05-11T16:23:00Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments
- Locked the channel-to-bit mapping convention for the entire Advantys STB milestone via a single module-level constant (`kSTBChannelBitOrder = STBBitOrder.lsbFirst`) + a canary unit test. Backend can flip the constant + three assertion lines if Schneider's convention turns out to be MSB-first; no painter, widget, or dialog code changes.
- Quarantined the force-collapse semantics (forced channels render the forced state only — no corner pip surfacing raw wire bit) into a pure `bitmaskToLedStates(int raw, {List<int>? forceValues})` helper that Phase 2 DDO3705 and the Plan 02 widget will consume directly. Matches `BeckhoffEL1008._ledStates` exactly.
- Shipped `IO16LedBlockPainter` as a sibling to `IO8LedBlockPainter` / `IO6LedBlockPainter`, encoding the column-major 2×8 layout (channels 1–8 LEFT column top→bottom, 9–16 RIGHT column top→bottom) per the DDI3725 photo reference.
- Established the clean STB import boundary: `lib/painter/advantys_stb/io16.dart` is the only STB file that imports Beckhoff internals; it re-exports `bodyColor` so downstream STB body painters import cream from the STB package only.

## Task Commits

Each task was committed atomically:

1. **Task 1 — RED: failing bit-mapping unit test** — `71010e8` (`test`)
2. **Task 2 — GREEN: io16.dart implementation + Beckhoff method rename** — `1d788f0` (`feat`)

TDD gate sequence confirmed in git log: `test(01-01)` → `feat(01-01)`. No refactor commit required (implementation landed directly per minimum-surface rule).

## Files Created/Modified

- **Created** `lib/painter/advantys_stb/io16.dart` (107 lines)
  - `enum STBBitOrder { lsbFirst, msbFirst }`
  - `const STBBitOrder kSTBChannelBitOrder = STBBitOrder.lsbFirst` (the locked default)
  - `List<IOState> bitmaskToLedStates(int raw, {List<int>? forceValues})` — pure helper with force-collapse
  - `class IO16LedBlockPainter extends BaseLedBlockPainter` — column-major 2×8 layout
  - `export ... show bodyColor` re-export for downstream STB body painters
- **Created** `test/page_creator/assets/advantys_stb_test.dart` (88 lines)
  - Group: `kSTBChannelBitOrder + bitmaskToLedStates`
  - 9 tests: constant canary, length contract, 0x0000 / 0x0001 / 0x8000 / 0xAAAA / 0xFFFF bit-mapping, plus two force-collapse cases
  - `TODO(stb-bit-order)` flagging backend confirmation before Plan 02 goldens lock
- **Modified** `lib/painter/beckhoff/io8.dart`
  - Promoted four library-private methods on `BaseLedBlockPainter` (`_drawBackground`, `_drawBorder`, `_drawLed`, `_drawLeds`) to library-public (`drawBackground`, `drawBorder`, `drawLed`, `drawLeds`). Sibling subclasses `IO8LedBlockPainter` and `IO6LedBlockPainter` updated to match. See Deviations.

## Decisions Made

- **LSB-first as default for `kSTBChannelBitOrder`** — matches Beckhoff EL1008 convention; flagged as needing backend confirmation in a `TODO(stb-bit-order)` comment at the top of the test group. If Schneider confirms MSB-first, the cost is one constant flip + three test-line edits.
- **Force-collapse rule via pure helper** — `bitmaskToLedStates` handles force-vs-raw priority once. No painter, widget, or dialog re-implements the bit math. This is the single highest-risk technical decision in the milestone (PITFALL M-02, M-04) and is now quarantined.
- **Column-major 2×8 layout encoded in painter math** — not parameterised. The DDI3725 + momentum-stack photos lock the layout; a future row-major variant would land as a sibling painter, not a constructor parameter.
- **Cream re-exported through STB entry point** — preserves the brownfield import discipline (PITFALL §9.3): only one STB file (`io16.dart`) imports Beckhoff internals; every other STB module file imports cream from `package:tfc/painter/advantys_stb/io16.dart`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Promoted `BaseLedBlockPainter` private LED-drawing methods to library-public**

- **Found during:** Task 2 (GREEN implementation)
- **Issue:** The plan instructs `IO16LedBlockPainter` to extend `BaseLedBlockPainter` (imported from `lib/painter/beckhoff/io8.dart`), override `_drawLeds`, and reuse the inherited `_drawLed`. In Dart, leading-underscore identifiers are **library-private** (scoped to the file's library, not class-private). A subclass declared in a different library (`lib/painter/advantys_stb/io16.dart`) cannot override `_drawLeds` nor call `_drawLed`. Without this rename, `IO16LedBlockPainter` cannot extend `BaseLedBlockPainter` at all — direct compile failure. This blocked the entire Task 2.
- **Fix:** Renamed four methods on `BaseLedBlockPainter` from library-private to library-public:
  - `_drawBackground` → `drawBackground`
  - `_drawBorder` → `drawBorder`
  - `_drawLed` → `drawLed`
  - `_drawLeds` → `drawLeds` (abstract method overridden by all sibling painters)

  Updated all three internal callsites in `BaseLedBlockPainter.paint()`, and updated the two existing sibling painters (`IO8LedBlockPainter._drawLeds` and `IO6LedBlockPainter._drawLeds`) to override the now-public `drawLeds`. Added comments noting these are "protected-by-convention" — external callers should still drive the painter via the public `paint()` entry point.
- **Files modified:** `lib/painter/beckhoff/io8.dart` (4 method renames, 5 callsite updates), `lib/painter/advantys_stb/io16.dart` (override `drawLeds` instead of `_drawLeds`, call `drawLed` instead of `_drawLed`).
- **Verification:**
  - `flutter test test/page_creator/assets/advantys_stb_test.dart` — all 9 tests pass (GREEN).
  - `flutter analyze lib/painter/advantys_stb/io16.dart test/page_creator/assets/advantys_stb_test.dart` — zero issues.
  - `grep -rn "_drawLed\|_drawBackground\|_drawBorder" lib/ test/ packages/` (excluding `.g.dart`) — no stale references anywhere in the project.
  - `flutter analyze lib/ test/` — 397 pre-existing issues, zero new issues introduced by the rename, zero errors (only `info` / `warning` lint diagnostics in unrelated files).
- **Committed in:** `1d788f0` (Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary for the plan's stated extension pattern to compile. Plan intent ("`IO16LedBlockPainter extends BaseLedBlockPainter`") preserved; only the underlying access-modifier shape changed. No external API surface affected — the public `paint()` entry point is unchanged. No scope creep.

## Issues Encountered

None beyond the Dart library-privacy blocker documented above. Tests went RED on first run (compile error: `No such file or directory` for the not-yet-created `io16.dart`) and GREEN on first run after creating `io16.dart` with the rename applied. No iteration required on `bitmaskToLedStates` math.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

**Plan 02 is ready to start.** The conventions Plan 02 (DDI3725 body painter + widget + dialog) consumes are all locked:

- Import `kSTBChannelBitOrder` and `bitmaskToLedStates` from `package:tfc/painter/advantys_stb/io16.dart` — never re-derive bit math.
- Import `bodyColor` (Schneider cream) from the same path — do NOT reach into `package:tfc/painter/beckhoff/io8.dart`.
- Compose `IO16LedBlockPainter` inside the DDI3725 body painter for the LED block — pass it the 16-element `List<IOState>` returned by `bitmaskToLedStates`.
- The Phase 2 DDO3705 module reuses the same three imports verbatim — convention drift between DI and DO is structurally impossible.

**Open carry-forward item:** `TODO(stb-bit-order)` in `test/page_creator/assets/advantys_stb_test.dart` flags the backend confirmation that Schneider Advantys STB really is LSB-first. This must be resolved before Plan 02 locks goldens (since flipping the constant would invalidate every golden PNG). The cost if MSB-first turns out to be correct: one constant flip in `io16.dart` + three test-line edits in `advantys_stb_test.dart`. No painter, widget, dialog, or downstream phase change required.

## Self-Check: PASSED

- File `lib/painter/advantys_stb/io16.dart` — FOUND (created in commit `1d788f0`).
- File `test/page_creator/assets/advantys_stb_test.dart` — FOUND (created in commit `71010e8`).
- File `lib/painter/beckhoff/io8.dart` — FOUND (modified in commit `1d788f0`).
- Commit `71010e8` (Task 1 RED) — FOUND.
- Commit `1d788f0` (Task 2 GREEN) — FOUND.
- TDD gate sequence verified: `test(01-01)` precedes `feat(01-01)` in `git log`.
- All 9 unit tests in the bit-mapping group pass.
- `flutter analyze` reports zero issues on plan-scoped files.

---
*Phase: 01-stbddi3725-16-ch-digital-input*
*Completed: 2026-05-11*
