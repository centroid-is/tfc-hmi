# Phase 5: AdvantysSTBStack (Composite Parent) - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning
**Mode:** Autonomous smart-discuss (mechanical compose-work after Phases 1-4 land)

<domain>
## Phase Boundary

Ship a `AdvantysSTBStackConfig` composite parent that holds a polymorphic `List<Asset> subdevices` filtered to the four STB module types (NIP2311 / PDT3100 / DDI3725 / DDO3705). Mirrors `BeckhoffCX5010Config` verbatim with the whitelist filter substituted. Subdevices render in a horizontal `Row` height-normalized via `_SubdeviceNormalized`. The `allKeys` override flat-maps each subdevice's keys (plus recursive nested-subdevice keys) so alarms and collectors discover the full key set without separate registration. The configure dialog supports add (filtered dropdown) + reorder (ReorderableListView) + remove. A post-`fromJson` sanitiser drops any non-STB child types (permissive render, restrictive add).

Phase 5 is mechanical compose-work — Phases 1-4 produced all four leaf module types; this phase wires them into the parent and ships a full-stack integration test.

</domain>

<decisions>
## Implementation Decisions

### Compose Pattern (Mirror CX5010 verbatim)
- `subdevices: List<Asset>` annotated with `@AssetListConverter()`
- `build()`: `FittedBox(fit: BoxFit.contain, child: Row(children: subdevices.map((s) => _SubdeviceNormalized(child: s)).toList()))`
- `_SubdeviceNormalized` widget duplicates the CX5010 height-normalizing Row wrapper (~20 LoC; per the no-cross-cutting-refactor discipline). Drop it as a private widget at the bottom of `advantys_stb.dart`.

### `allKeys` Override
- Flat-map every subdevice's `allKeys` into a de-duplicated `Set<String>`. Recursive: if a subdevice is itself a composite (none today, but future-proof), its `allKeys` recurses naturally.
- Drop empty strings.
- Result: `Set<String>(subdevices.expand((s) => s.allKeys).where((k) => k.isNotEmpty)).toList()`

### Whitelist Filter
- **Allowed child types:** `STBNIP2311Config`, `STBPDT3100Config`, `STBDDI3725Config`, `STBDDO3705Config`. NO other types accepted.
- **Permissive render:** If a non-STB type somehow survives in the subdevices list (e.g., from a hand-edited JSON), it renders as-is (the painter doesn't fail).
- **Restrictive add:** The dropdown in the configure dialog ONLY shows the 4 STB types. No way to add a non-STB type through the UI.
- **Post-`fromJson` sanitiser:** Walks the subdevices list after deserialization and `retainWhere((s) => _isSTBChildType(s.runtimeType.toString()))`. Foreign types silently dropped (with a log line). Mirrors `AssetRegistry.parse`'s existing convention.

### Configure Dialog
- **Add subdevice:** ElevatedButton + filtered SimpleDialog popup with the 4 STB type names (NIP2311 / PDT3100 / DDI3725 / DDO3705). Each option's onTap creates a new `STBXxxxConfig` via its `.preview()` factory and appends to `subdevices`.
- **Reorder:** ReorderableListView with drag-to-reorder.
- **Remove:** Trailing IconButton(Icons.delete) per subdevice with confirmation.
- **No per-subdevice config editing inline** — operator opens the subdevice itself to configure (subdevices remain individually placed assets within the stack).

### Integration Test
- Pump an `AdvantysSTBStack` containing one NIP + one PDT + one DDI + one DDO.
- Assert: page loads cleanly, `stack.allKeys` returns the union of all child keys (de-duplicated), every painter renders without exception, taps register on each subdevice (not falling through to the stack frame — verified by `GestureDetector(HitTestBehavior.opaque)` wrapping).
- Golden: `stack_full_{light,dark}.png` — canonical NIP+PDT+DDI+DDO layout.

### Goldens
- **2 PNGs:** `stack_full_light.png` + `stack_full_dark.png` at `test/page_creator/assets/goldens/advantys_stb/`. One canonical 4-module stack layout per theme.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BeckhoffCX5010Config` and `_SubdeviceNormalized` — `lib/page_creator/assets/beckhoff.dart`. The CX5010 source is the line-by-line pattern.
- `AssetListConverter` — locate via `grep -n "AssetListConverter" lib/page_creator/assets/`.
- All four STB leaf configs and their `.preview()` factories — `lib/page_creator/assets/advantys_stb.dart` (Phases 1-4).
- `STBDDI3725Config.preview` etc. — used by the filtered "Add" dropdown.

### Established Patterns
- Single file `lib/page_creator/assets/advantys_stb.dart` — Phase 5 APPENDS the stack config.
- No painter file needed (stack composes children; no body painter).
- Codegen: `dart run build_runner build` re-runs for the new config.
- Tests: APPEND to `test/page_creator/assets/advantys_stb_test.dart`. Integration test for the full 4-module stack.

### Integration Points
- `lib/page_creator/assets/registry.dart` — add `AdvantysSTBStackConfig` to BOTH maps (palette entry shows the stack as a placeable composite).
- New tests cover: `allKeys` flat-map correctness; add/reorder/remove flows; non-STB child filter (foreign type → dropped via sanitiser); full-stack integration golden.

</code_context>

<specifics>
## Specific Ideas

- The stack itself has no painter body — it's a pure composition wrapper. `build()` returns `FittedBox + Row` only.
- Per-subdevice tap targets must propagate independently: each subdevice's own `GestureDetector(HitTestBehavior.opaque)` (already in place from Phases 1-4) ensures taps land on the subdevice, not the stack frame.
- The stack's own configure dialog manages stack-level metadata (`nameOrId`, `Coordinates`, `Size`) plus the subdevices list management UI.

</specifics>

<deferred>
## Deferred Ideas

- Multi-stack composition (multiple stacks on one page) — STACK-FUT-01.
- Stack-level disconnected rollup state — STACK-FUT-02.
- Canonical-layout enforcement (NIP first, PDT next, I/O modules in any order after) — STACK-FUT-03.

</deferred>

## Architectural Revision (2026-05-12)

The standalone `AdvantysSTBStackConfig` was retrofitted away. The
composite-parent behavior (subdevices list + sanitiser + `allKeys` flat-map +
Add/Reorder/Delete dialog) was moved ONTO `STBNIP2311Config` directly.

**Why:** The Beckhoff precedent in `lib/page_creator/assets/beckhoff.dart`
puts `List<Asset> subdevices` directly on the head device class
(`BeckhoffCX5010Config`, `BeckhoffEK1100Config`). There is NO standalone
"stack frame" asset in the Beckhoff family. Phase 5 originally shipped one
for Advantys (rejecting that precedent), creating an extra wrapper layer the
real Advantys STB rack does not have: in the physical rack, the NIP2311
Ethernet head IS the parent of the slotted I/O modules.

**Whitelist change:** the retrofit removed the NIP entry from
`_kAllowedSTBChildTypeNames` (renamed to `_kAllowedSTBSubdeviceTypeNames`).
A NIP head cannot nest another NIP head — there is one head per rack.
The whitelist now contains only the three I/O modules (PDT/DDI/DDO).

**What was preserved:** every Phase 5 success criterion 3–5 (sanitiser
behavior, dialog UX, integration test) holds verbatim. Goldens were
regenerated: `stack_full_{light,dark}.png` deleted, replaced by
`nip_with_modules_{light,dark}.png`.

The original CONTEXT decisions above remain for historical traceability.
See `05-RETROFIT.md` for the full retrofit redirect.
