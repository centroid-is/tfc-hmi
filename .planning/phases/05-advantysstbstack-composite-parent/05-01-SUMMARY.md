---
phase: 05-advantysstbstack-composite-parent
plan: 01
subsystem: page-creator-assets
tags: [advantys-stb, composite-parent, asset-registry, json-serializable, tdd]

# Dependency graph
requires:
  - phase: 01-stbddi3725-16-ch-digital-input
    provides: STBDDI3725Config leaf module config + .preview() factory
  - phase: 02-stbddo3705-16-ch-digital-output
    provides: STBDDO3705Config leaf module config + .preview() factory
  - phase: 03-stbnip2311-ethernet-head-adapter
    provides: STBNIP2311Config leaf module config + .preview() factory
  - phase: 04-stbpdt3100-power-distribution
    provides: STBPDT3100Config leaf module config + .preview() factory
provides:
  - AdvantysSTBStackConfig composite parent (CX5010 mirror with STB whitelist)
  - _STBSubdeviceNormalized private height-normaliser widget
  - _kAllowedSTBChildTypeNames whitelist (sanitiser typo-guard surface)
  - Post-fromJson sanitiser (NET-NEW; no CX5010 precedent)
  - Composite allKeys flat-map override (dedupe + empty-string filter)
affects: [future-multi-stack-composition, future-disconnected-rollup, plan-05-02-configure-dialog]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Composite parent with @AssetListConverter() polymorphic List<Asset> subdevices"
    - "Post-fromJson runtimeType.toString() whitelist sanitiser (permissive render, restrictive load)"
    - "BaseAsset.allKeys flat-map override with .where(isNotEmpty).toSet().toList() shape"
    - "Logger().w(...) for silent-log-and-skip foreign type drops (mirrors AssetRegistry.parse convention)"
    - "Private height-normaliser widget duplicated rather than extracted (no cross-cutting refactor while shipping additive features)"

key-files:
  created: []
  modified:
    - lib/page_creator/assets/advantys_stb.dart (appended AdvantysSTBStackConfig + _STBSubdeviceNormalized; added page.dart import for AssetListConverter)
    - lib/page_creator/assets/advantys_stb.g.dart (regenerated; added _$AdvantysSTBStackConfigFromJson + _$AdvantysSTBStackConfigToJson)
    - lib/page_creator/assets/registry.dart (registered AdvantysSTBStackConfig in BOTH _fromJsonFactories AND defaultFactories)
    - test/page_creator/assets/advantys_stb_test.dart (Rule 1 test fix — round-trip via jsonEncode/jsonDecode in sanitiser test)

key-decisions:
  - "Mirror BeckhoffCX5010Config verbatim with four-type STB whitelist substituted (RESEARCH.md finding 1)"
  - "Post-fromJson sanitiser is NET-NEW for Phase 5 — no CX5010 precedent (RESEARCH.md finding 2). Sanitiser is the security control (V5 Input Validation per ASVS analysis)."
  - "_STBSubdeviceNormalized duplicated as private widget — no cross-cutting extraction (CONTEXT §Compose Pattern; OOS-07)"
  - "configure() stubbed in this plan; Plan 05-02 ships the Add + Reorder + Delete UI"
  - "displayName = 'Advantys STB Stack', category = 'Advantys STB' (matches locked phase contract; verified to also match BaseAsset._humanize output)"
  - "Use import '../page.dart' show AssetListConverter; — codegen requires the converter in scope (parity with beckhoff.dart:15)"

patterns-established:
  - "Whitelist via const Set<String> _kAllowedXxxChildTypeNames: literal runtimeType.toString() values; guard-rail test asserts each leaf matches a literal (Pitfall 2 — typo guard)"
  - "factory ClassName.fromJson wraps _$ClassNameFromJson(json) + retainWhere over the whitelist + Logger().w on drops"
  - "allKeys composite override shape: subdevices.expand((s) => s is BaseAsset ? s.allKeys : <String>[]).where((k) => k.isNotEmpty).toSet().toList()"

requirements-completed: [STACK-01, STACK-02, STACK-03, STACK-05, QUAL-06]

# Metrics
duration: 8m
completed: 2026-05-12
---

> **Superseded by retrofit (2026-05-12)** — composite behavior moved from
> `AdvantysSTBStackConfig` (deleted) to `STBNIP2311Config`. See `05-RETROFIT.md`
> for the new shape. Whitelist now excludes NIP (head cannot nest a head).

# Phase 5 Plan 01: AdvantysSTBStack Composite Parent Summary

**Composite STB stack parent that mirrors `BeckhoffCX5010Config` verbatim with a four-type whitelist (NIP2311 / PDT3100 / DDI3725 / DDO3705) and a NET-NEW post-`fromJson` sanitiser that drops foreign child types — flat-maps every subdevice's `allKeys` so alarms and collectors discover the full key set without separate registration.**

## Performance

- **Duration:** 8 min (RED commit `435eb2b` 09:24Z → GREEN commit `a064fc2` 09:32Z)
- **Started:** 2026-05-12T09:24:28Z
- **Completed:** 2026-05-12T09:32:24Z
- **Tasks:** 2 (RED gate via prior commit; GREEN gate this session)
- **Files modified:** 4 (1 lib source, 1 generated, 1 registry, 1 test)

## Accomplishments

- `AdvantysSTBStackConfig` ships as the fifth and final Phase-5 asset, completing the Advantys STB family alongside the four leaf modules from Phases 1–4.
- Sanitiser layer (NET-NEW) silently drops any non-STB child type on load via `retainWhere` against `_kAllowedSTBChildTypeNames`; permissive `build()` still renders any survivor without crashing.
- `allKeys` flat-map override exposes the union of every subdevice's keys (deduplicated, empty-filtered) so the existing alarm and collector pipelines work on a stack with no changes downstream.
- Plan registers the new config in BOTH `_fromJsonFactories` AND `defaultFactories` of `AssetRegistry` (Pitfall 3 lock) — the palette lists the stack as a placeable asset and saved pages round-trip cleanly.
- Full test suite of 504/504 passes across `test/page_creator/` after the change; no regressions.

## Task Commits

Each task was committed atomically following the TDD gate sequence:

1. **Task 1 (RED): Failing tests for sanitiser + allKeys + JSON round-trip + back-compat + registry resolution** — `435eb2b` (test)
   - Pre-existing commit from the prior planning step; 8 new groups in `test/page_creator/assets/advantys_stb_test.dart` and 4 new tests in `test/page_creator/all_keys_test.dart`. RED verified by `flutter analyze` reporting 19 `undefined_function` / `undefined_identifier` errors for `AdvantysSTBStackConfig` before this plan's GREEN landed.

2. **Task 2 (GREEN): AdvantysSTBStackConfig composite parent (STACK-01..05)** — `a064fc2` (feat)
   - Appended `AdvantysSTBStackConfig` to `lib/page_creator/assets/advantys_stb.dart` mirroring CX5010 verbatim with the locked `allKeys` shape and the NET-NEW sanitiser. Added `import '../page.dart' show AssetListConverter;` to bring the converter into scope for codegen. Registered the config in both registry maps. Regenerated `advantys_stb.g.dart`. Applied a Rule 1 test fix to round-trip the sanitiser test through `jsonEncode`/`jsonDecode` (raw `.toJson()` left nested `Coordinates` objects that tripped leaf cast guards).

## TDD Gate Compliance

- ✅ **RED gate:** `435eb2b` (test commit, prior-session) — confirmed failing via `flutter analyze` showing 19 undefined-symbol errors.
- ✅ **GREEN gate:** `a064fc2` (feat commit, this session) — 147/147 in `advantys_stb_test.dart`, 28/28 in `all_keys_test.dart`, 504/504 across full `test/page_creator/`.
- **REFACTOR gate:** none needed — the implementation is the locked CX5010 mirror plus the documented sanitiser; no cleanup pass required.

## Files Created/Modified

- `lib/page_creator/assets/advantys_stb.dart` — Appended `AdvantysSTBStackConfig` (composite parent class), `_STBSubdeviceNormalized` (private height-normaliser widget), `_kAllowedSTBChildTypeNames` (sanitiser whitelist). Added `import '../page.dart' show AssetListConverter;` for codegen scope.
- `lib/page_creator/assets/advantys_stb.g.dart` — Regenerated by `dart run build_runner build --delete-conflicting-outputs`; added `_$AdvantysSTBStackConfigFromJson` + `_$AdvantysSTBStackConfigToJson` (shape identical to `_$BeckhoffCX5010Config*`).
- `lib/page_creator/assets/registry.dart` — Two single-line additions: `AdvantysSTBStackConfig: AdvantysSTBStackConfig.fromJson` in `_fromJsonFactories`, `AdvantysSTBStackConfig: AdvantysSTBStackConfig.preview` in `defaultFactories`.
- `test/page_creator/assets/advantys_stb_test.dart` — Single Rule 1 test fix: the sanitiser-drops-foreign-types test now round-trips its synthetic JSON through `jsonEncode`/`jsonDecode` before passing to `fromJson`, matching the real production load path. Without the round-trip, nested `Coordinates`/`RelativeSize` objects inside `.toJson()` output trip the leaf `_$XxxFromJson` cast guards.

## Verification

- `flutter analyze lib/page_creator/assets/advantys_stb.dart lib/page_creator/assets/registry.dart` — **No issues found.**
- `flutter analyze test/page_creator/all_keys_test.dart test/page_creator/assets/advantys_stb_test.dart` — **No issues found.**
- `flutter test test/page_creator/assets/advantys_stb_test.dart` — **147/147 pass** (138 prior + 9 new for AdvantysSTBStackConfig).
- `flutter test test/page_creator/all_keys_test.dart` — **28/28 pass** (24 prior + 4 new for AdvantysSTBStackConfig).
- `flutter test test/page_creator/` (full directory) — **504/504 pass** — no regressions across the page-creator surface.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Sanitiser RED test passed raw `.toJson()` output, tripping leaf cast guards**
- **Found during:** Task 2 (GREEN run after `dart run build_runner build`).
- **Issue:** `STBNIP2311Config.preview().toJson()` returns a `Map<String, dynamic>` where `coordinates` is a raw `Coordinates` *object* (not a Map). When the test passed that map directly to `AdvantysSTBStackConfig.fromJson`, the inner `_$STBNIP2311ConfigFromJson` cast `json['coordinates'] as Map<String, dynamic>` failed with `type 'Coordinates' is not a subtype of type 'Map<String, dynamic>'`. The production load path (`jsonEncode` → `jsonDecode` → `fromJson`) normalises every value to JSON-native types, so this failure does not occur in real saves/loads.
- **Fix:** Wrapped the test's synthetic JSON with `jsonDecode(jsonEncode(rawJson))` before passing to `fromJson`. The intent of the test (verify the sanitiser drops the foreign `ButtonConfig`) is preserved; the fix only normalises the encoding shape to match production.
- **Files modified:** `test/page_creator/assets/advantys_stb_test.dart` (lines 2710–2740).
- **Commit:** `a064fc2` (rolled into the GREEN feat commit per the standard TDD flow).

**2. [Rule 3 - Blocking] `Could not resolve annotation for List<Asset> subdevices` — codegen needs `AssetListConverter` in scope**
- **Found during:** Task 2 (first `dart run build_runner build` attempt after adding the class).
- **Issue:** `json_serializable` analyzer cannot resolve the `@AssetListConverter()` annotation if the converter type is not lexically reachable from the class declaration. The pre-existing `advantys_stb.dart` imports do not bring `AssetListConverter` into scope (it lives in `lib/page_creator/page.dart`, not `common.dart`).
- **Fix:** Added `import '../page.dart' show AssetListConverter;` at line 41 (parity with `beckhoff.dart:15`, which is the established mirror for composite assets).
- **Files modified:** `lib/page_creator/assets/advantys_stb.dart`.
- **Commit:** `a064fc2`.

## Known Stubs

- `AdvantysSTBStackConfig.configure(BuildContext context)` returns a minimal placeholder `Column` with the text "Subdevice management UI ships in Plan 05-02. Edit JSON directly for now." The dropdown / ReorderableListView / delete IconButton surface from CONTEXT.md §Configure Dialog ships in Plan 05-02 as locked by the phase plan. Operators can already place a stack on a page (palette wiring is live via the registry) but must hand-edit JSON to add subdevices until Plan 05-02 lands.

## Deferred Issues

- None — every plan task ran to completion within the same session.

## Self-Check: PASSED

- ✅ `lib/page_creator/assets/advantys_stb.dart` exists, contains `class AdvantysSTBStackConfig`.
- ✅ `lib/page_creator/assets/advantys_stb.g.dart` exists, contains `_$AdvantysSTBStackConfigFromJson` and `_$AdvantysSTBStackConfigToJson`.
- ✅ `lib/page_creator/assets/registry.dart` exists, contains both `AdvantysSTBStackConfig: AdvantysSTBStackConfig.fromJson` and `AdvantysSTBStackConfig: AdvantysSTBStackConfig.preview`.
- ✅ Commit `435eb2b` (RED) reachable in `git log`.
- ✅ Commit `a064fc2` (GREEN) reachable in `git log`.
- ✅ `flutter analyze` clean on all modified files.
- ✅ Full test suites (`advantys_stb_test.dart`, `all_keys_test.dart`, `test/page_creator/`) green.
