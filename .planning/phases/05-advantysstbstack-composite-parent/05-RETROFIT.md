---
phase: 05-advantysstbstack-composite-parent
retrofit: true
completed: 2026-05-12
supersedes: [05-01-SUMMARY.md, 05-02-SUMMARY.md]
---

# Phase 5 Retrofit — `AdvantysSTBStack` → `STBNIP2311` Composite Head

**TL;DR:** The standalone `AdvantysSTBStackConfig` was deleted. Its
composite-parent behavior (subdevices list, sanitiser, `allKeys` flat-map,
Add/Reorder/Delete dialog) moved verbatim onto `STBNIP2311Config`. The NIP
Ethernet head IS the composite — mirrors `BeckhoffCX5010Config` /
`BeckhoffEK1100Config` precedent in `lib/page_creator/assets/beckhoff.dart`.

## Why

In the real Advantys STB rack, the NIP2311 Ethernet head IS the physical
parent of the slotted I/O modules. Phase 5 originally shipped an
`AdvantysSTBStackConfig` that wrapped the NIP inside a frame — an extra
abstraction the precedent rejects:

- `BeckhoffCX5010Config` (`beckhoff.dart` ≈ line 30): `List<Asset> subdevices`
  directly on the head class.
- `BeckhoffEK1100Config` (`beckhoff.dart` ≈ line 288): same shape, no
  separate "stack frame" asset.

The user noticed and requested the retrofit. The new shape is symmetric with
the Beckhoff family: head device = composite.

## What moved

| Concern | Before (Stack) | After (NIP head) |
|---|---|---|
| `List<Asset> subdevices` field | `AdvantysSTBStackConfig` | `STBNIP2311Config` |
| Whitelist constant | `_kAllowedSTBChildTypeNames` (4 types incl. NIP) | `_kAllowedSTBSubdeviceTypeNames` (3 types — NIP **excluded**) |
| Available subdevices map | `_availableSTBSubdevices` (4 entries) | `_availableSTBSubdevices` (3 entries — NIP entry removed) |
| Post-`fromJson` sanitiser | On Stack | On NIP |
| `allKeys` override | On Stack | On NIP |
| Configure dialog widget | `_AdvantysSTBStackConfigContent` | `_STBNIP2311ConfigContent` |
| Subdevice height-normalizer | `_STBSubdeviceNormalized` | `_STBSubdeviceNormalized` (unchanged — same widget) |
| Goldens | `stack_full_{light,dark}.png` | `nip_with_modules_{light,dark}.png` |
| Registry registration | `AdvantysSTBStackConfig` + `STBNIP2311Config` | `STBNIP2311Config` only |

## What was preserved

Every Phase 5 success criterion 3–5 (sanitiser, dialog, integration test)
holds verbatim. Success criterion 1 (palette placement) is satisfied by the
existing NIP registration — the NIP was already in the palette via Phase 3.

## Visual contract changes

- **Standalone NIP** (empty `subdevices`): same Phase-3 decorative head
  visual; no `Row` wrapper. Back-compat for pages that placed a bare NIP.
- **Composite NIP** (non-empty `subdevices`): NIP head on the left, then
  subdevices in slot order, all height-normalized via `_STBSubdeviceNormalized`
  inside a `FittedBox(fit: BoxFit.contain, child: Row(...))`. The NIP head
  itself is the first child of the Row (visually anchors the rack).

## Whitelist deviation from precedent

The Beckhoff `_availableSubdevices` map allows EL-series I/O modules only —
the CX5010 head is NOT in its own whitelist. The retrofitted NIP whitelist
similarly excludes the NIP itself: a NIP head cannot nest another NIP head.
A unit test (`'NIP whitelist correctly excludes NIP itself'`) locks this.

## Test surface delta

- `test/page_creator/assets/advantys_stb_test.dart`: every group named
  `'AdvantysSTBStack…'` was retargeted to `'STBNIP2311 head with subdevices…'`.
  159 tests pass against the retrofit.
- `test/page_creator/all_keys_test.dart`: the
  `AdvantysSTBStackConfig.allKeys` group was retargeted to `STBNIP2311Config`.

## Lesson

Codified in `feedback_composite_head_pattern.md`: head devices ARE their own
composites in this codebase. Do not add standalone "stack" wrapper assets for
future device families — put the subdevices list directly on the head class.
