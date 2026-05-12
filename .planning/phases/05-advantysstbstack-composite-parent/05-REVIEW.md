---
phase: 05-advantysstbstack-composite-parent
reviewed: 2026-05-12T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - lib/page_creator/assets/advantys_stb.dart
  - lib/page_creator/assets/registry.dart
  - test/page_creator/assets/advantys_stb_test.dart
  - test/page_creator/all_keys_test.dart
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-05-12
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

The Phase 5 implementation adds `AdvantysSTBStackConfig` as a composite-parent asset that mirrors `BeckhoffCX5010Config` verbatim with a four-type STB whitelist substituted, plus a NET-NEW post-`fromJson` sanitiser (registered-but-not-whitelisted children are dropped via `runtimeType.toString()`) and an `allKeys` flat-map override (with explicit empty-filter).

**Verdict:** Correctness of the sanitiser, allKeys flat-map, registry dual-map wiring, reorder/delete state mutation, and tap-pass-through assertions all check out. The integration test scope and assertions match the documented design. CLAUDE.md compliance (snake_case files, no `print()`, `Logger().w()` for the dropped-type log, TDD-first ordering) is intact.

The findings below are predominantly **test-contract mismatches** and **inherited pre-existing CX5010 patterns** that are worth surfacing for owner awareness. No defects block shipping Phase 5.

## Warnings

### WR-01: JSON back-compat test does not exercise the case its name claims

**File:** `test/page_creator/assets/advantys_stb_test.dart:2890-2912`
**Issue:** The test is named `'minimal legacy snippet without subdevices field loads with empty list'` and the inline comment asserts `"the codegen must default it to [] rather than throwing"`. However, the JSON literal at line 2903 still contains `'subdevices': <Map<String, dynamic>>[]`. The test therefore validates the empty-list case, not the missing-field case.

The generated factory at `lib/page_creator/assets/advantys_stb.g.dart:146-147` does `json['subdevices'] as List` (no null-aware cast and no default). A genuinely missing `subdevices` field on saved JSON would crash with a `TypeError: type 'Null' is not a subtype of type 'List<dynamic>'`. The test does not catch this. This matches CX5010 parity (no regression), but the contract documented in the test does not match the code's actual behaviour.

**Fix:** Either rename the test + adjust the comment to reflect "empty subdevices list" (matches reality), or add a second test that omits the field and asserts the documented behaviour — likely by tightening `fromJson` to be tolerant:

```dart
// Option A (preferred — preserve the contract the test claims):
factory AdvantysSTBStackConfig.fromJson(Map<String, dynamic> json) {
  final cfg = _$AdvantysSTBStackConfigFromJson({
    ...json,
    if (!json.containsKey('subdevices')) 'subdevices': <dynamic>[],
  });
  // ...existing sanitiser logic...
}

// Option B (cheaper — rename the test):
test('JSON with empty subdevices list survives fromJson unchanged', () { ... });
```

### WR-02: `_combinedStream` subscribes empty-string keys, while `allKeys` filters them

**File:** `lib/page_creator/assets/advantys_stb.dart:336-357` (also lines 169-181, 643-655 callers)
**Issue:** The shared `_combinedStream` helper filters subscribed entries with `if (entry.value != null)`. An empty string `''` for a leaf `*Key` field (an operator can clear the `KeyField` in the configure dialog — the TextField's `onChanged` passes `''` back through) is `!= null`, so `stateMan.subscribe('')` is called.

Meanwhile, `BaseAsset.allKeys` (`common.dart:232-243`) and the stack's `allKeys` override (line 1325-1329) both drop empty strings. This means alarms/collectors will see N keys, but the live widget will subscribe to N+1 (one of which is an invalid empty key). The behaviour is pre-existing in the Beckhoff `_combinedStream`, but is observable in the new stack.

Note: PDT3100 (line 1152) does correctly guard with `if (key == null || key.isEmpty) return;` — there is an inconsistency between PDT and DDI/DDO key handling.

**Fix:** Align DDI/DDO with PDT's empty-key guard:

```dart
// In _combinedStream:
[
  for (final entry in keys.entries)
    if (entry.value != null && entry.value!.isNotEmpty)
      stateMan.subscribe(entry.value!).asStream().asyncExpand((s) => s),
],
(values) {
  final map = <String, DynamicValue>{};
  int i = 0;
  for (final entry in keys.entries) {
    if (entry.value != null && entry.value!.isNotEmpty) {
      map[entry.key] = values[i++];
    }
  }
  return map;
},
```

### WR-03: Unawaited `.then()` in initState swallows `stateManProvider` failures

**File:** `lib/page_creator/assets/advantys_stb.dart:169-181, 643-655, 1153-1159`
**Issue:** All three `_STB*State.initState()` implementations call `ref.read(stateManProvider.future).then((sm) { ... });` without a `.catchError` and without `await`. If `stateManProvider` rejects (e.g. preferences init fails, OPC UA bootstrap fails), the rejection lands in Flutter's unhandled async-error zone and the widget renders the stale shell forever with no operator-visible signal. The mounted guard correctly avoids `setState` after dispose, but does not surface errors.

This matches the established Beckhoff `_STB*` and EL* pattern, so it's pre-existing convention, not a Phase 5 regression. It is, however, the kind of silent-failure case that the SUMMARY's "stale shell" treatment masks — worth surfacing for a follow-up.

**Fix:** Add a defensive `.catchError` that logs and keeps the stale shell. Suggest a small follow-up issue rather than fixing in Phase 5 (would need to be applied across DDI/DDO/PDT consistently):

```dart
ref.read(stateManProvider.future).then((sm) {
  if (!mounted) return;
  setState(() { _stateMan = sm; _combinedStreamCache = _combinedStream(...); });
}).catchError((e, st) {
  Logger().w('STB widget init failed: $e\n$st');
});
```

### WR-04: Registry crawl swallows `_log.t/_log.d` comments but rethrows `parse` errors

**File:** `lib/page_creator/assets/registry.dart:144,147,156-162,168,171`
**Issue:** `AssetRegistry.parse` contains commented-out trace/debug log statements at lines 144, 147, 168, 171 — dead artifacts from earlier development. Worse, the `catch (e, stackTrace)` block at lines 156-163 *rethrows* the error after logging. This contradicts the `AdvantysSTBStackConfig.fromJson` sanitiser comment claim (line 1386-1387) that the registry "silent-log-and-skip"s unknown types.

In practice: the registry only silently skips JSON nodes that don't match any known asset (the for-loop falls through). For JSON that DOES claim to be a registered asset but fails to parse, the registry **rethrows** — propagating the error to the page-load top-level. This means a malformed STB-stack subdevice (e.g. invalid coordinate) crashes the whole page, not just its subdevice slot. This is pre-existing CX5010-shared behaviour; documenting it here so future hardening can target it.

**Fix:** Two micro-fixes are independently useful:

```dart
// 1. Delete dead commented-out logs at registry.dart:144, 147, 168, 171.

// 2. (Larger follow-up) Replace `rethrow` with `_log.e + continue` so a single
//    malformed asset does not abort the whole page load:
} catch (e, stackTrace) {
  _log.e('Failed to parse asset of type $assetName', error: e, stackTrace: stackTrace);
  return; // skip this asset, keep crawling the rest of the JSON.
}
```

## Info

### IN-01: `Logger()` instantiated on every `fromJson` call

**File:** `lib/page_creator/assets/advantys_stb.dart:1396`
**Issue:** `Logger().w(...)` constructs a new `Logger` instance every call. `AssetRegistry` uses a static `_log` field (`registry.dart:35`) for the same purpose. Cheap to fix; harmless to leave.
**Fix:** Add `static final Logger _log = Logger();` to `AdvantysSTBStackConfig` and reuse `_log.w(...)`.

### IN-02: `_AdvantysSTBStackConfigContent` ignores screen size

**File:** `lib/page_creator/assets/advantys_stb.dart:1374-1380`
**Issue:** `configure()` returns `SizedBox(width: 800, height: 500, ...)` — fixed dimensions regardless of viewport. On compact windows (≤ 800 px wide or ≤ 500 px tall), the dialog overflows. The configure-dialog widget test (line 2934) bumps the surface to 1400×900 specifically to avoid this. CX5010 has the same shape (line 96-101 of beckhoff.dart), so it's intentional CX5010 parity.
**Fix:** Out of scope for Phase 5 — both CX5010 and STB stack share this fragility. A separate follow-up could wrap in `LayoutBuilder` + `ConstrainedBox` to clamp to viewport.

### IN-03: Sanitiser does not recurse into composite subdevices

**File:** `lib/page_creator/assets/advantys_stb.dart:1388-1402`
**Issue:** The sanitiser only filters direct `subdevices` by `runtimeType.toString()`. If a future STB child were itself a composite (STACK-FUT-01), its own internal subdevices would not be sanitised by the parent. Currently no composite is in `_kAllowedSTBChildTypeNames`, so a composite child is itself dropped at the parent level — the recursion concern is structurally moot today.

Note: the **`allKeys` override** at line 1324-1330 *does* recurse correctly, because each subdevice's own `allKeys` getter is called (which for a future composite would walk its own subdevices).

**Fix:** No fix needed for Phase 5. If STACK-FUT-01 ever adds nested composites to the whitelist, the sanitiser will need to recurse — flag this as a guard rail at that time.

### IN-04: `initState` reads config keys once; live-mutation in config dialog requires page reload

**File:** `lib/page_creator/assets/advantys_stb.dart:151-159, 641-655, 1146-1159`
**Issue:** All three leaf widgets resolve their `*Key` fields once in `initState`. If an operator opens the configure dialog and changes a key, the widget will not re-subscribe to the new key until the page is reloaded / the widget cycles. This is the QUAL-03 / PITFALL M-03 contract (avoid resubscribe storms on parent rebuild). Documented design, not a defect — but a UX subtlety worth surfacing.
**Fix:** None required; design choice. Surface in operator docs if the user-facing edit-then-watch flow becomes a support issue.

### IN-05: `_combinedStream` swallowed by `CombineLatest`-never-emits if any source key is offline

**File:** `lib/page_creator/assets/advantys_stb.dart:336-357` (and consumers at lines 402-515, 796-877)
**Issue:** `CombineLatestStream` requires every source to emit at least one value before producing a combined map. In the detail dialog, all FIVE keys (`raw + force + on_filters + off_filters + descriptions`) must emit before the row tree renders; if any one is silent, the dialog shows `SizedBox.shrink()` (line 426-428, 818-820). Pre-existing Beckhoff convention — not a Phase 5 regression — but worth surfacing because the operator-facing impact ("detail dialog appears blank") is non-obvious.
**Fix:** Optional follow-up: replace `CombineLatestStream` with per-key `StreamBuilder` nesting, or with a `CombineLatestStream` that starts each source with a sentinel `DynamicValue`. Out of scope for Phase 5.

---

_Reviewed: 2026-05-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
