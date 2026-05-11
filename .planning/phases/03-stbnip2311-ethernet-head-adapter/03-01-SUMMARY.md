---
phase: 03
plan: 03-01
subsystem: page-creator-assets
tags: [advantys-stb, decorative, head-adapter, ethernet, goldens, tdd]
requires:
  - lib/painter/beckhoff/ek1100.dart (EthernetPortPainter)
  - lib/painter/advantys_stb/io16.dart (bodyColor)
  - lib/painter/advantys_stb/ddi3725.dart (stbAccentBlue)
  - lib/page_creator/assets/common.dart (BaseAsset, SizeField, CoordinatesField)
provides:
  - STBNIP2311Config (HMI asset config)
  - STBNIP2311Widget (decorative head adapter widget)
  - STBNIP2311BodyPainter (body painter)
affects:
  - lib/page_creator/assets/advantys_stb.dart (APPENDED)
  - lib/page_creator/assets/advantys_stb.g.dart (REGENERATED)
  - lib/page_creator/assets/registry.dart (BOTH MAPS)
tech-stack:
  added: []
  patterns:
    - Cross-vendor painter reuse (EthernetPortPainter from beckhoff/ek1100.dart)
    - Decorative-only asset (no StateMan subscriptions, no PLC keys)
    - Shared visual identity constant (`stbAccentBlue` imported from ddi3725.dart)
key-files:
  created:
    - lib/painter/advantys_stb/nip2311.dart
    - test/page_creator/assets/goldens/advantys_stb/nip2311_normal_light.png
    - test/page_creator/assets/goldens/advantys_stb/nip2311_normal_dark.png
  modified:
    - lib/page_creator/assets/advantys_stb.dart
    - lib/page_creator/assets/advantys_stb.g.dart
    - lib/page_creator/assets/registry.dart
    - test/page_creator/assets/advantys_stb_test.dart
decisions:
  - NIP2311 has NO PLC keys — firmware-driven on real hardware (LOCKED in 03-CONTEXT.md)
  - Status LEDs rendered in fixed normal state: RUN/PWR green, ERR/ST/TEST dim grey
  - EthernetPortPainter reused verbatim from beckhoff/ek1100.dart — cross-vendor visual is intentional
  - Body aspect ratio = 58/82 ≈ 0.71 (NIP2311 DXF bounding box, smaller than I/O modules)
  - configure() dialog exposes only `nameOrId` + `Coordinates` + `Size` (NO KeyField widgets)
  - Single render state (no stale/disconnected variant since no live keys)
  - _STBNIP2311 is a StatelessWidget (no stream, no tap handler) — simpler than DDI/DDO which use ConsumerStatefulWidget
metrics:
  duration: "~14 minutes"
  completed: 2026-05-11
  tasks: 3
  files-touched: 7
  tests-added: 17 (NIP2311 groups: data shape, painter, configure surface, widget mount, registry, JSON round-trip)
  goldens-added: 2
  total-tests-in-file: 108 (all passing)
---

# Phase 3 Plan 01: STBNIP2311 Decorative Ethernet Head Adapter Summary

**One-liner:** Decorative-only Schneider Advantys STB NIP2311 Ethernet head adapter asset — fixed-state status LEDs + cross-vendor `EthernetPortPainter` reuse, no PLC keys.

## What Shipped

A new `STBNIP2311Config` HMI asset that renders the Schneider Advantys STB NIP2311 Ethernet Modbus/TCP communications head module on a page-creator canvas. The asset is purely decorative — there are NO PLC state keys, no StateMan subscriptions, and no tap-to-detail behavior. The configure dialog exposes only `nameOrId` + `Coordinates` + `Size`.

The body painter renders, top-to-bottom:
1. Top Schneider-blue label strip with "NIP2311" text.
2. Five status LEDs (RUN / PWR / ERR / ST / TEST) in a fixed "normal" state — RUN+PWR green (`Color(0xFF6CA545)`), ERR/ST/TEST dim grey (`Colors.grey.shade400`).
3. Schneider-blue subtitle band with "Ethernet Modbus/TCP 10/100T".
4. Dual RJ45 ports stacked vertically, painted via `EthernetPortPainter` reused verbatim from `lib/painter/beckhoff/ek1100.dart` (cross-vendor reuse is intentional per 03-CONTEXT.md).
5. Decorative bottom footer with "24 VDC 0.55A" and "Schneider Electric" branding.

Aspect ratio is locked at width/height ≈ 0.71 per the NIP2311 DXF bounding box (58×82 mm) — visually narrower than the 107×152 mm I/O modules so head adapters read distinctly in a stacked rail layout.

## Requirements Satisfied

- **NIP-01** — Decorative-only NIP2311 head asset with the fixed five status LEDs and dual RJ45 ports.
- **NIP-02** — Cross-vendor `EthernetPortPainter` reuse verified via direct import from `lib/painter/beckhoff/ek1100.dart`.
- **NIP-03** — configure() exposes only Size / Coordinates / Name or ID; no `KeyField` widgets (compile-time-guarded by the `editor surface` test).
- **NIP-04** — `STBNIP2311Config` registered in both `_fromJsonFactories` and `defaultFactories` of `AssetRegistry`; JSON round-trip + legacy back-compat tests pass.

## Commits

| Hash      | Type    | Description                                                                            |
| --------- | ------- | -------------------------------------------------------------------------------------- |
| `bb81bb2` | test    | RED — STBNIP2311 data shape, painter, widget mount, JSON, registry                     |
| `f4cc2c4` | feat    | STBNIP2311 decorative Ethernet head adapter (NIP-01..04, sans goldens)                 |
| `2d20178` | test    | STBNIP2311 goldens — single normal state, light + dark themes                          |

## TDD Gate Compliance

- **RED gate:** commit `bb81bb2` adds 17 test cases that fail to compile (`STBNIP2311Config` undefined).
- **GREEN gate:** commit `f4cc2c4` adds the painter + config + registry entries. 104 of 106 advantys_stb tests pass; the two failures are the two `matchesGoldenFile` checks which expect goldens that don't exist yet.
- **REFACTOR-equivalent (goldens):** commit `2d20178` adds the 2 PNG goldens. Final state: 108/108 tests pass.

The "PASSED unexpectedly during RED" fail-fast rule was respected — the RED tests failed exclusively on `STBNIP2311Config` being undefined, not on any unexpected pre-existence.

## Deviations from Plan

### Auto-Fixed

**1. [Rule 3 - Blocking] Worktree HEAD predated phase 1/2 prerequisites**

- **Found during:** Initial setup (worktree-branch check).
- **Issue:** The worktree-agent-ab79cf6c branch was forked from `4bbede3` (UMAS hardening) which predates the Phase 1/2 STB work + the Phase 3 CONTEXT.md. The prerequisite files (`advantys_stb.dart`, `ddi3725.dart`, `ddo3705.dart`, `03-CONTEXT.md`, etc.) were not tracked in this worktree's HEAD.
- **Fix:** `git reset --hard 726a2ea2044708d0d5a54e70786d3fbba0f21cb2` — exactly as the orchestrator's `<worktree_branch_check>` block directs ("Reset if needed").
- **Files modified:** none — this brought the worktree's index to match the requested base.
- **Commit:** none — this is a base-setup operation, not a content change.

**2. [Rule 3 - Blocking] Mis-routed edits to the main worktree's test file**

- **Found during:** RED gate, before commit.
- **Issue:** Early edits used the absolute path `/Users/jonb/Projects/tfc-hmi2/test/page_creator/assets/advantys_stb_test.dart` (the **main** worktree path) instead of the worktree path. The edits landed in the wrong tree.
- **Fix:** Reverted the main worktree's file with `git checkout -- test/page_creator/assets/advantys_stb_test.dart` (run from `/Users/jonb/Projects/tfc-hmi2`) before re-applying the edits at the correct worktree-prefixed path. Verified the main worktree's `git status` no longer shows the modification.
- **Files modified:** none in the worktree branch (the temporary stray edits were reverted at the source).
- **Commit:** none — corrected before staging.

### Architectural

None. The plan executed exactly as written: TDD discipline preserved (RED → GREEN → goldens), no new dependencies, no schema changes outside the documented `STBNIP2311Config` config class.

## Authentication Gates

None.

## Known Stubs

None. The asset is decorative by design — there is no data path to wire. Future stub elimination would be NIP-FUT-01 (synthetic comm-OK key) and NIP-FUT-02 (per-port link/activity), both explicitly deferred to v2.1 in 03-CONTEXT.md.

## Threat Flags

None. The painter is read-only paint output. No new network endpoints, auth paths, file access, or schema changes are introduced.

## Self-Check: PASSED

- **Files exist:**
  - `lib/painter/advantys_stb/nip2311.dart` — FOUND.
  - `lib/page_creator/assets/advantys_stb.dart` — FOUND (contains `STBNIP2311Config`).
  - `lib/page_creator/assets/advantys_stb.g.dart` — FOUND (contains `_$STBNIP2311ConfigFromJson` / `_$STBNIP2311ConfigToJson`).
  - `lib/page_creator/assets/registry.dart` — FOUND (registered in both maps).
  - `test/page_creator/assets/advantys_stb_test.dart` — FOUND (108 tests pass).
  - `test/page_creator/assets/goldens/advantys_stb/nip2311_normal_light.png` — FOUND.
  - `test/page_creator/assets/goldens/advantys_stb/nip2311_normal_dark.png` — FOUND.
- **Commits exist:**
  - `bb81bb2` — FOUND (RED).
  - `f4cc2c4` — FOUND (GREEN).
  - `2d20178` — FOUND (goldens).
- **Tests pass:** 108 of 108 in `advantys_stb_test.dart`.
- **Analyzer clean:** `flutter analyze` returns "No issues found!" on touched files.
