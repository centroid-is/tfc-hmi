---
phase: 05
phase_dir: 05-advantysstbstack-composite-parent
verified: 2026-05-12T00:00:00Z
status: passed
score: 7/7 must_haves verified — all CONTEXT deviations signed off
date: 2026-05-12
user_sign_offs:
  - decision: "Delete IconButton has NO confirmation dialog (CX5010 parity overriding CONTEXT line-38 'with confirmation' phrasing)"
    signed_off: 2026-05-12
    signer: jon@centroid.is
    verbatim_response: "dont need confirmation"
    locked_by_test: "advantys_stb_test.dart:3001-3024 (Test 4: find.byType(AlertDialog), findsNothing after tap)"
re_verification:
  previous_status: human_needed
  previous_score: 7/7
  gaps_closed: []
  gaps_remaining: []
  regressions: []
  note: "Previous VERIFICATION.md (2026-05-12 earlier in day) also concluded 7/7 technical PASS with the same single human-decision item. This is an independent goal-backward re-verification against the current shipped code; result is unchanged. Frontmatter `gaps:` was empty in the prior run, so this is technically a fresh verification rather than a gap-closure pass."
human_verification:
  - test: "Confirm CONTEXT Decision 1 — Delete IconButton on the NIP head's configure dialog has NO confirmation step (CX5010 parity, retrofitted onto STBNIP2311)"
    expected: "User explicitly accepts that tapping the trailing Icons.delete on a subdevice ListTile immediately removes the subdevice — no AlertDialog confirmation. CONTEXT §Configure Dialog line 38 originally said delete 'with confirmation'; CONTEXT §Compose Pattern's verbatim-mirror commitment was treated as the stronger commitment and overrode the line-38 phrasing. Test 4 at advantys_stb_test.dart:3001-3024 LOCKS this deviation into a regression assertion (find.byType(AlertDialog), findsNothing after tapping delete)."
    why_human: "Documented as 'user must confirm post-execution' in 05-02-SUMMARY.md §Decision 1 and 05-02-PLAN.md. No commit, code comment, planning artifact, or feedback_*.md memory entry records explicit acceptance. The agent applied the verbatim-mirror commitment under its own authority but the user has not signed off in writing. Reverting later would require code AND test changes — the user should sign off now."
gaps: []
deferred: []
---

# Phase 5: AdvantysSTBStack (Composite Parent) — Verification Report

**Phase Goal:** Operators can place the Advantys STB composite head onto a page, open its configure dialog, add subdevices from a filtered "Add" dropdown limited to the STB I/O module types, reorder them in a `ReorderableListView`, watch all children render in a horizontal `Row` height-normalized via `_STBSubdeviceNormalized` — with `allKeys` flat-mapping every child's keys, a post-`fromJson` sanitiser dropping non-STB types, and a full integration test confirming a NIP head + PDT + DDI + DDO loads cleanly, all child keys are discoverable, every painter renders, and taps register on each interactive module's body.

**Architectural revision:** The standalone `AdvantysSTBStackConfig` was deleted mid-phase; composite behavior moved onto `STBNIP2311Config` to mirror the CX5010/EK1100 precedent. Verified against the retrofit shape per the user-approved redirect in `05-RETROFIT.md`.

**Verified:** 2026-05-12 (re-run by independent verifier; goal-backward).
**Status:** `passed` — 7/7 truths verified; CX5010-parity delete-confirmation deviation signed off by jon@centroid.is on 2026-05-12 ("dont need confirmation"). Decision is now intentional, locked by Test 4, and no follow-up plan is required.
**Re-verification:** Yes — independent re-run of an earlier `human_needed` verification. No regressions; no new gaps; outstanding human item is unchanged.

## Goal Achievement — Requirement-Driven Truths

| # | Requirement / Truth | Status | Evidence |
|---|---------------------|--------|----------|
| 1 | **STACK-01** — Composite head registered in BOTH `_fromJsonFactories` and `defaultFactories` (retrofit: `STBNIP2311Config` IS the composite). `AdvantysSTBStackConfig` removed from production code. | ✓ VERIFIED | `registry.dart:68` (`STBNIP2311Config: STBNIP2311Config.fromJson` in `_fromJsonFactories`); `registry.dart:113` (`STBNIP2311Config: STBNIP2311Config.preview` in `defaultFactories`). `grep -c AdvantysSTBStackConfig lib/page_creator/assets/registry.dart` = 0. Only doc-comment refs remain in `advantys_stb.dart:891,910`, `all_keys_test.dart:244`, `advantys_stb_test.dart:2678` (4 historical references, all in comment context). Three registry-resolution tests at `advantys_stb_test.dart:2154-2189` pass: `createDefaultAssetByName('STBNIP2311Config')` returns a typed instance; `AssetRegistry.parse` round-trips the JSON; `defaultFactories.keys` contains the type. |
| 2 | **STACK-02** — Polymorphic subdevices via `@AssetListConverter() List<Asset> subdevices`. | ✓ VERIFIED | `advantys_stb.dart:965-966`: `@AssetListConverter()\nList<Asset> subdevices = <Asset>[];`. Converter brought into scope at line 42 (`import '../page.dart' show AssetListConverter;`). Codegen at `advantys_stb.g.dart:86-87, 108` uses `AssetListConverter().fromJson` / `.toJson`. Full round-trip test at `advantys_stb_test.dart:2810-2855` encodes a 3-subdevice list (DDI+DDO+PDT), decodes, and asserts type-and-key fidelity per element. |
| 3 | **STACK-03** — `allKeys` flat-map: deduplicated, empty-filtered union of every subdevice's `allKeys`. | ✓ VERIFIED | Implementation at `advantys_stb.dart:1008-1014`: `subdevices.expand((s) => s is BaseAsset ? s.allKeys : <String>[]).where((k) => k.isNotEmpty).toSet().toList()` — the locked CONTEXT-line-27 shape (NOT the CX5010 for-loop form). Four unit tests at `all_keys_test.dart:248-298` cover: union from subdevices (4 keys, hasLength(4)), empty subdevices → empty, dedupes across two PDTs sharing a key, defensive empty-string filter via `_MockEmptyKeyAsset`. Integration Test 2 at `advantys_stb_test.dart:3104-3128` re-asserts the 4-key union (DDI rawStateKey + DDI forceValuesKey + DDO rawStateKey + PDT inputOkKey). |
| 4 | **STACK-04** — Configure dialog: filtered Add dropdown (3 STB I/O types, NIP excluded) + `ReorderableListView` + Delete IconButton. | ✓ VERIFIED | `_STBNIP2311ConfigContent` widget at `advantys_stb.dart:1140-1303`. Dropdown items iterate `_availableSTBSubdevices.keys` at line 1222 (3 entries, line 938-943). `ReorderableListView.builder` at line 1258 with `onReorder` mutating `widget.config.subdevices`. Trailing `IconButton(icon: Icons.delete)` at line 1283-1289. Six dialog widget tests at `advantys_stb_test.dart:2918-3045` all pass: Test 1 adds DDI via dropdown; Test 2 asserts dropdown has exactly 3 items (NIP excluded — head cannot nest head); Test 3 reorders 0↔2 via `widget.onReorder`; Test 4 deletes with NO AlertDialog; Test 5 confirms Name-or-ID field IS present on the head (NIP retains its own nameOrId — see Note on Decision 2 below); Test 6 asserts `enableAngle: true` on the CoordinatesField via the locked `tester.widget<CoordinatesField>(find.byType(...)).enableAngle` mechanic. |
| 5 | **STACK-05** — Post-`fromJson` sanitiser drops foreign types via `retainWhere` over a 3-entry whitelist; `Logger().w` on drops; no `throw`. | ✓ VERIFIED | `STBNIP2311Config.fromJson` at `advantys_stb.dart:984-998` wraps `_$STBNIP2311ConfigFromJson(json)`, then `cfg.subdevices.retainWhere((s) => _kAllowedSTBSubdeviceTypeNames.contains(s.runtimeType.toString()))`, then logs the dropped count via `Logger().w(...)`. Whitelist constant at lines 923-927 contains exactly 3 entries: `STBPDT3100Config`, `STBDDI3725Config`, `STBDDO3705Config` (NIP correctly EXCLUDED per retrofit — a head cannot nest another head). Four sanitiser tests at `advantys_stb_test.dart:2717-2807` pass: drops foreign ButtonConfig (T1), drops a nested NIP (T2), runtimeType-string-vs-class-name typo-guard against whitelist literals (T3), empty subdevices list is a no-op (T4). `grep "throw\|Exception" inside STBNIP2311Config.fromJson` → no matches; sanitiser logs only. |
| 6 | **QUAL-06** — `flutter analyze` clean across the four Phase-5 footprint files. | ✓ VERIFIED | Ran `flutter analyze lib/page_creator/assets/advantys_stb.dart lib/page_creator/assets/registry.dart test/page_creator/assets/advantys_stb_test.dart test/page_creator/all_keys_test.dart` → "No issues found! (ran in 1.1s)" — exit 0. |
| 7 | **QUAL-07** — Full-stack integration test: NIP+PDT+DDI+DDO loads cleanly, `allKeys` complete, all painters render, taps register on each interactive module's body. | ✓ VERIFIED | Six-test group at `advantys_stb_test.dart:3053-3196`: T1 mounts NIP+PDT+DDI+DDO under `ProviderScope + MaterialApp + Scaffold` with `_EmptyStubStateMan`, asserts `tester.takeException() == null` and four `find.byType(...)` widgets each `findsOneWidget`. T2 (unit) confirms `head.allKeys` is the 4-element deduped union. T3/T4 tap DDI/DDO body → `AlertDialog` opens (live interactive leaves). T5/T6 tap NIP/PDT body → no exception, no dialog (decorative leaves per RESEARCH finding 4 — NIP head and PDT have no `GestureDetector`). All six pass per the test run (see Behavioral Spot-Checks below). Two macOS-gated goldens `nip_with_modules_{light,dark}.png` at `test/page_creator/assets/goldens/advantys_stb/` lock the visual contract. |

**Score:** 7/7 truths technically verified. The one outstanding item is a user policy decision (delete-confirmation UX) flagged by the planning artifacts for post-execution sign-off but never confirmed in writing. See Human Verification Required below.

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/page_creator/assets/advantys_stb.dart` | `STBNIP2311Config` composite head + `_kAllowedSTBSubdeviceTypeNames` (3 entries) + `_availableSTBSubdevices` Map (3 entries) + `_STBSubdeviceNormalized` height-normalizer + `_STBNIP2311ConfigContent` dialog | ✓ VERIFIED | All five symbols present at lines 956, 923, 938, 1100, 1140. File total 1524 lines. Logger imported, AssetListConverter imported (line 42). |
| `lib/page_creator/assets/advantys_stb.g.dart` | `_$STBNIP2311ConfigFromJson` + `_$STBNIP2311ConfigToJson`; subdevices round-trip via `AssetListConverter` | ✓ VERIFIED | Generated helpers at lines 83-109; line 87 uses `AssetListConverter().fromJson`; line 108 uses `AssetListConverter().toJson`. |
| `lib/page_creator/assets/registry.dart` | `STBNIP2311Config` registered in BOTH maps; `AdvantysSTBStackConfig` REMOVED | ✓ VERIFIED | Lines 68 + 113. `grep -c AdvantysSTBStackConfig` = 0 across the whole file. |
| `test/page_creator/assets/advantys_stb_test.dart` | NIP-composite groups for data-shape, sanitiser, round-trip, back-compat, configure-dialog, full-stack integration, and goldens | ✓ VERIFIED | Seven NIP-composite groups at lines 2684, 2717, 2810, 2857, 2888, 3053, 3202. File total 3682 lines. |
| `test/page_creator/all_keys_test.dart` | Four tests asserting NIP composite `allKeys` semantics | ✓ VERIFIED | Tests at lines 248, 267, 271, 284 cover returns-from-subdevices, empty, dedupe, and defensive empty-string filter (via `_MockEmptyKeyAsset` at line 342). |
| `test/page_creator/assets/goldens/advantys_stb/nip_with_modules_light.png` | Canonical NIP + PDT + DDI + DDO golden (light theme) | ✓ VERIFIED | Present, 22883 bytes. Inline visual review confirms the six-item visual-quality checklist (see Visual Quality below). |
| `test/page_creator/assets/goldens/advantys_stb/nip_with_modules_dark.png` | Canonical golden (dark theme) | ✓ VERIFIED | Present, 22883 bytes — pixel-identical to light per QUAL-02 (cream bodies are theme-invariant). |
| `.planning/phases/05-advantysstbstack-composite-parent/05-VISUAL-QUALITY-CHECKLIST.md` | Process gate documenting the six-item visual checklist | ✓ VERIFIED | Present (3390 bytes). Codifies the post-defect-fix discipline so future agents reading regenerated PNGs apply the checklist before committing. |

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `STBNIP2311Config.fromJson` | `_$STBNIP2311ConfigFromJson` + sanitiser whitelist | wraps codegen + `retainWhere` + `Logger().w` | ✓ WIRED | `advantys_stb.dart:984-998`. Four sanitiser tests pass. |
| `STBNIP2311Config.allKeys` | each `subdevice.allKeys` | `expand(...).where(isNotEmpty).toSet().toList()` | ✓ WIRED | `advantys_stb.dart:1008-1014`. Four unit tests in `all_keys_test.dart` + integration Test 2. |
| `STBNIP2311Config.build` (composite mode) | `_STBNIP2311` head + `_STBSubdeviceNormalized` wrappers per child | `SizedBox.fromSize → FittedBox(contain) → Row(MainAxisSize.min)` (lines 1034-1055) | ✓ WIRED | Integration Test 1 asserts all four widget types mount. |
| `STBNIP2311Config.configure` | `_STBNIP2311ConfigContent(config: this)` | `SizedBox(800x500, _STBNIP2311ConfigContent(config: this))` | ✓ WIRED | Lines 1062-1068. Six dialog tests exercise the full Add/Reorder/Delete surface. |
| Dialog Add dropdown | `widget.config.subdevices.add(...)` | `_availableSTBSubdevices[v]!()` factory call | ✓ WIRED | Lines 1225-1230; Test 1 confirms add picks STBDDI3725Config and length goes to 1. |
| Dialog Reorder | `widget.config.subdevices` list mutation | `ReorderableListView.builder.onReorder` (lines 1262-1268) | ✓ WIRED | Test 3 confirms invoking `onReorder(0, 2)` permutes the list as expected. |
| Dialog Delete | `widget.config.subdevices.removeAt(index)` | `IconButton(Icons.delete).onPressed` (lines 1283-1289) | ✓ WIRED | Test 4 confirms tap removes one entry; `find.byType(AlertDialog)` finds nothing (CX5010 parity — Decision 1). |
| Registry → `STBNIP2311Config` | palette load + JSON load | `_fromJsonFactories` + `defaultFactories` entries | ✓ WIRED | Three registry-resolution tests pass. |

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `STBNIP2311Config.build` composite branch | `subdevices` (`List<Asset>`) | `STBNIP2311Config.fromJson` (sanitised) or direct constructor | Yes | ✓ FLOWING |
| `STBNIP2311Config.allKeys` | `subdevices[*].allKeys` | Recursive `expand` across each subdevice's own `allKeys` | Yes | ✓ FLOWING |
| Dialog list view | `widget.config.subdevices` | Mutated by Add dropdown / Reorder / Delete user actions via `setState` | Yes | ✓ FLOWING |
| DDI/DDO leaf widgets (under integration test) | `rawStateKey` stream value | `stateManProvider` override = `_EmptyStubStateMan` returns `Stream<DynamicValue>.empty()` | Stale shell only (test fixture by design) | ⚠ STATIC (acceptable — QUAL-07 verifies tap routing, not real PLC data; production data flow is verified by the Phase-1/2 leaf-level tests) |
| NIP head / PDT decorative bodies | (no live state — decorative) | n/a — `_STBNIP2311` / `_STBPDT3100` are pure painters | n/a | n/a |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `flutter analyze` clean on the four Phase-5 footprint files | `flutter analyze lib/page_creator/assets/advantys_stb.dart lib/page_creator/assets/registry.dart test/page_creator/assets/advantys_stb_test.dart test/page_creator/all_keys_test.dart` | `No issues found! (ran in 1.1s)` | ✓ PASS |
| Full `test/page_creator/` suite green | `flutter test test/page_creator/` | `+543: All tests passed!` | ✓ PASS |
| No `AdvantysSTBStackConfig` remains in production code | `grep -c AdvantysSTBStackConfig lib/page_creator/assets/registry.dart` | `0` | ✓ PASS |
| `AdvantysSTBStackConfig` references that remain are doc-comment only | `grep -rn AdvantysSTBStackConfig lib/ test/` | 4 hits, all in `//`-comment context (`advantys_stb.dart:891,910`, `all_keys_test.dart:244`, `advantys_stb_test.dart:2678`) | ✓ PASS |
| Sanitiser logs and does NOT throw | Inspect `STBNIP2311Config.fromJson` body at `advantys_stb.dart:984-998` | `Logger().w(...)` only on drops; no `throw`, no `Exception` | ✓ PASS |
| Whitelist contains exactly 3 entries (NIP excluded) | Read `_kAllowedSTBSubdeviceTypeNames` literal at `advantys_stb.dart:923-927` | `{STBPDT3100Config, STBDDI3725Config, STBDDO3705Config}` | ✓ PASS |
| `_availableSTBSubdevices` Map contains exactly 3 entries (NIP excluded) | Read map literal at `advantys_stb.dart:938-943` | 3 entries keyed by leaf displayName → preview factory | ✓ PASS |
| No stale `stack_full_*.png` references in tests | `grep -n "stack_full\|stb_stack_full_golden" test/page_creator/assets/advantys_stb_test.dart` | (no matches) | ✓ PASS |
| Both `nip_with_modules_*.png` goldens exist | `ls -la test/page_creator/assets/goldens/advantys_stb/nip_with_modules_*.png` | both present, 22883 bytes each (pixel-identical light/dark) | ✓ PASS |

## Requirements Coverage

| Requirement | Plan | Description | Status | Evidence |
|-------------|------|-------------|--------|---------|
| STACK-01 | 05-01 | Composite extends `BaseAsset`, registered in both registry maps (retrofit: NIP IS the composite) | ✓ SATISFIED | `registry.dart:68,113`; `AdvantysSTBStackConfig` fully removed. Three registry-resolution tests pass. |
| STACK-02 | 05-01 | Polymorphic `List<Asset> subdevices` via `@AssetListConverter()` | ✓ SATISFIED | `advantys_stb.dart:965-966` + codegen at `.g.dart:86-87,108`. Full JSON round-trip test passes. |
| STACK-03 | 05-01 | `allKeys` flat-map with dedupe + empty-filter | ✓ SATISFIED | `advantys_stb.dart:1008-1014` (locked `expand+where+toSet+toList` shape). 4 unit tests + integration Test 2. |
| STACK-04 | 05-02 | Configure dialog with filtered Add + Reorder + Delete | ✓ SATISFIED | `_STBNIP2311ConfigContent` lines 1140-1303; 6 dialog widget tests. |
| STACK-05 | 05-01 | Post-`fromJson` sanitiser, permissive render / restrictive add | ✓ SATISFIED | `advantys_stb.dart:984-998` + 4 sanitiser tests. |
| QUAL-06 | 05-02 | `flutter analyze` clean across new/modified files | ✓ SATISFIED | `flutter analyze` exit 0 on all four Phase-5 files. |
| QUAL-07 | 05-02 | Full-stack integration test: 4-module mount + `allKeys` + tap routing | ✓ SATISFIED | 6-test group at `advantys_stb_test.dart:3053-3196`; all pass. |

No orphaned requirements. Every requirement listed under Phase 5 in `REQUIREMENTS.md:15-19, 66-67` is satisfied.

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/page_creator/assets/advantys_stb.dart` | 891, 910 | Doc-comment references to deleted `AdvantysSTBStackConfig` | ℹ Info | Intentional historical traceability per `05-RETROFIT.md`. No code impact — the references are inside `//` comments documenting the retrofit. Could be cleaned up for hygiene, but explicitly preserved per the retrofit doc. |
| `test/page_creator/all_keys_test.dart` | 244 | Doc-comment reference to deleted `AdvantysSTBStackConfig` | ℹ Info | Same — explains retrofit context for future readers. |
| `test/page_creator/assets/advantys_stb_test.dart` | 2678 | Doc-comment reference to deleted `AdvantysSTBStackConfig` | ℹ Info | Same. |

No Blockers, no Warnings. The sanitiser does not throw (Logger().w only). No empty placeholder `build()`s, no stub `configure()` methods, no hardcoded empty `subdevices` defaults that flow to render-only paths. The visual-defect remediation suite includes 9 DEFECT regression tests (`advantys_stb_test.dart:3281-3490`).

## Visual Quality (Goldens Inline Review)

Read `nip_with_modules_light.png` inline (the Claude `Read` tool renders PNGs visually). Applying the six-item checklist from `05-VISUAL-QUALITY-CHECKLIST.md`:

- [x] **Chamfer / rounded corners visible cleanly on all four corners** — every module body (NIP head + PDT + DDI + DDO) shows clean rounded corners; no Schneider header bar overshoot past the chamfer.
- [x] **No stray pixels below the bottom outline** — the bottom edges of all four modules are clipped at the rounded body outline; no leaked accent band.
- [x] **LEDs round, evenly spaced, active vs inactive distinct** — NIP shows 4 round status LEDs on the upper left; PDT shows a single round INPUT dot; DDI/DDO show their 16-channel circular indicator columns. The four DEFECT-3 regression tests at `advantys_stb_test.dart:3421+` lock the round-LED geometry via direct pixel sampling.
- [x] **All text labels fit inside the module body** — NIP/PDT/DDI/DDO labels and pin numbers are inside their cream bodies. At 800×200 the labels are small but uncropped. DEFECT-4 regression test locks the "INPUT +" / "INPUT −" labels inside the PDT body.
- [x] **No clipping at any edge** — the leftmost NIP and the rightmost DDO are fully visible inside the 800-wide canvas; the outer `FittedBox(contain)` correctly inscribes the Row.
- [x] **Aspect ratio looks correct per module** — NIP first (narrowish head), PDT next (slim PDM), DDI third (wider 16-channel grid), DDO last (wider grid with arrow indicator); all heights normalized via `_STBSubdeviceNormalized`.

Both goldens (light + dark) are pixel-identical (cream module bodies are theme-invariant per QUAL-02). The Scaffold background is excluded from the goldens by the tightly-cropped 800×200 `RepaintBoundary` per the golden harness.

## Human Verification Required

### 1. CONTEXT Decision 1 — Delete IconButton has NO confirmation dialog

**Test:** Confirm that this CX5010-parity deviation matches the operator-facing intent.

**Expected:** User explicitly accepts that tapping the trailing `Icons.delete` on a subdevice ListTile inside the NIP head's configure dialog removes the subdevice immediately — no `AlertDialog` confirmation step.

**Why human:** Documented under "⚠ CONTEXT Deviations Requiring User Confirmation" in `05-02-SUMMARY.md §Decision 1` and `05-02-PLAN.md`. The original CONTEXT phrasing at `05-CONTEXT.md:38` says delete "with confirmation"; the verbatim CX5010 mirror dropped the confirmation. The agent applied the CX5010-mirror commitment in CONTEXT §Compose Pattern as the stronger commitment, but the user has not signed off in writing — no commit, no planning-artifact edit, and no `feedback_*.md` memory entry records acceptance. Test 4 at `advantys_stb_test.dart:3001-3024` LOCKS this deviation into a regression assertion (`find.byType(AlertDialog), findsNothing` after tapping delete), so any future revert would require both code AND test changes — which is precisely why the user should sign off now.

If the user accepts: this becomes an explicit override and the verification flips to `passed`. To accept via an override, add this to the VERIFICATION.md frontmatter:

```yaml
overrides:
  - must_have: "Delete IconButton on the NIP head configure dialog removes subdevice with confirmation"
    reason: "Verbatim CX5010 mirror (no confirmation) accepted as the canonical UX; CONTEXT.md §Compose Pattern's verbatim-mirror commitment supersedes the §Configure Dialog line-38 'with confirmation' phrasing."
    accepted_by: "jon"
    accepted_at: "<ISO timestamp>"
```

If the user rejects: a follow-up plan adds an `AlertDialog` confirmation step + updates Test 4.

### Note on the original Decision 2 (no `nameOrId` on the stack — now moot post-retrofit)

This concern is largely **moot after the retrofit**. The original Decision 2 in `05-02-SUMMARY.md` said "the stack has no `nameOrId`" — but the retrofit deleted the standalone stack, and the NIP head IS the composite. The NIP head has retained its own `nameOrId` field from Phase 3, visible in dialog Test 5 at `advantys_stb_test.dart:3026-3034`: `find.widgetWithText(TextFormField, 'Name or ID'), findsOneWidget`. So the user-visible state is: the composite-parent asset (NIP head) DOES carry a `nameOrId`. The original concern (no top-level identity field on the composite) is no longer applicable. Decision 2 does not require fresh user confirmation.

## Gaps Summary

No gaps. Every requirement (STACK-01..05, QUAL-06, QUAL-07) is technically satisfied with code + tests + goldens. The one outstanding item is the user policy decision (delete-confirmation UX) that the planning artifacts explicitly flagged for post-execution sign-off but never received written acceptance.

---

_Verified: 2026-05-12_
_Verifier: Claude (gsd-verifier) — independent goal-backward re-run_
