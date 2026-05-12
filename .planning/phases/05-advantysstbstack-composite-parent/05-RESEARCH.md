# Phase 5: AdvantysSTBStack (Composite Parent) - Research

**Researched:** 2026-05-12
**Domain:** Flutter / Riverpod / Asset Registry composite-asset wiring (mirror BeckhoffCX5010Config)
**Confidence:** HIGH

## Summary

Phase 5 is **pure mechanical compose-work**. Every implementation choice in CONTEXT.md is locked to "mirror CX5010 verbatim with the whitelist filter substituted." This research validated each CX5010 reference against the actual source. Findings:

1. The CX5010 pattern exists exactly as CONTEXT.md describes — `subdevices: List<Asset>` annotated `@AssetListConverter()`, `FittedBox + Row` build, `_SubdeviceNormalized` height-normaliser, identical configure-dialog with dropdown + `ReorderableListView` + delete-IconButton. All locations confirmed line-by-line at `lib/page_creator/assets/beckhoff.dart:31-285`.
2. **The post-`fromJson` sanitiser is NET-NEW for Phase 5 — CX5010 does NOT have one today.** This is the one piece that does not exist to mirror; the planner must write it. The "convention" the sanitiser mirrors is `AssetRegistry.parse`'s silent-log-and-skip behaviour for unknown `asset_name` values (`registry.dart:138-176`), not an existing CX5010 sanitiser.
3. All four leaf STB module configs (`STBNIP2311Config`, `STBPDT3100Config`, `STBDDI3725Config`, `STBDDO3705Config`) are registered in BOTH `_fromJsonFactories` and `defaultFactories` (Phases 1–4 complete; `registry.dart:66-69` and `111-114`). Their `.preview()` factories all exist and take no arguments.
4. The "GestureDetector(HitTestBehavior.opaque) on every subdevice" claim in CONTEXT.md §Integration Test is **partially incorrect**: only DDI and DDO wrap their inner widget in `GestureDetector(opaque)`. NIP and PDT are decorative-only (no tap handler, no GestureDetector). The integration test's tap-pass-through assertion must be scoped to DDI+DDO only — taps on NIP/PDT areas correctly fall through.
5. Test conventions: `goldens/advantys_stb/` already exists with 14 PNGs from Phases 1–4. Golden tests are double-gated — `dart_test.yaml` has `tags: golden: skip: ...` AND individual groups use `skip: !Platform.isMacOS`. The existing `advantys_stb_test.dart` is 2829 lines, 135 tests; Phase 5 appends to it.
6. Codegen is straightforward: `@JsonSerializable()` + `part 'advantys_stb.g.dart';` is already in place. Adding `AdvantysSTBStackConfig` with `@AssetListConverter() List<Asset> subdevices = []` and running `dart run build_runner build` produces a `_$AdvantysSTBStackConfigFromJson` identical in shape to `_$BeckhoffCX5010ConfigFromJson` (`beckhoff.g.dart:9-21`).
7. `BaseAsset` default `allKeys` walks `toJson()` and matches `key$|key\d+$|Key$|_key$` field names (`common.dart:218-243`). For a composite, this default would return ONLY the `subdevices` JSON list (not a string) → empty result. **The `allKeys` override is mandatory**, and the CX5010 shape (`for (final sub in subdevices) if (sub is BaseAsset) keys.addAll(sub.allKeys)`) is the proven mirror.

**Primary recommendation:** Append `AdvantysSTBStackConfig` to `lib/page_creator/assets/advantys_stb.dart` as a near-clone of `BeckhoffCX5010Config` (lines 31-110 of beckhoff.dart). Add the four-type whitelist Map at the top of the new section. Add a sanitiser inside the `fromJson` factory (the one piece without a CX5010 precedent). Register in both registry maps. Append tests to the existing `advantys_stb_test.dart`. Run `build_runner`. Goldens go in the existing `test/page_creator/assets/goldens/advantys_stb/` directory.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Stack composite render (build) | UI / Flutter widget tree | — | Pure widget composition; no state-key reads in stack itself |
| Subdevice list management (add/reorder/delete) | UI / configure dialog State | Asset config (in-memory `List<Asset>`) | Same pattern as CX5010 — config holds the list, dialog mutates via setState |
| `allKeys` flat-map for alarms/collectors | Asset config (`BaseAsset` API) | StateMan (consumes the resulting keys via the existing collector) | StateMan/AlarmMan already iterate `BaseAsset.allKeys` for any asset on the page; the stack just contributes the union |
| Subdevice JSON polymorphism | Codegen + `AssetListConverter` | `AssetRegistry.parse` (the actual factory dispatch) | Existing converter delegates to registry — no new converter needed |
| Whitelist enforcement | Asset config (post-`fromJson` sanitiser) + configure dialog (filtered dropdown) | — | Permissive render fallback lives in the build path (renders whatever survives); restrictive add lives in the configure dialog |
| Live state subscription per subdevice | Each leaf module's own `ConsumerStatefulWidget` | StateMan via `stateManProvider` | Stack owns nothing live — each subdevice manages its own subscription per Phases 1-4 |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter SDK | stable (^3.5/^3.6) | Widget framework | [VERIFIED: pubspec.yaml] Project mandates Flutter stable channel |
| `json_annotation` | ^4.9.0 | `@JsonSerializable`, `@JsonKey` annotations | [VERIFIED: pubspec.yaml] Already used by every existing asset |
| `json_serializable` | ^6.9.4 | Codegen for `_$XxxFromJson` / `_$XxxToJson` | [VERIFIED: pubspec.yaml] |
| `build_runner` | ^2.4.15 | Runs codegen | [VERIFIED: pubspec.yaml] |
| `flutter_riverpod` | ^2.6.1 | (Indirectly — leaf widgets only) `ConsumerWidget` | [VERIFIED: pubspec.yaml] Stack itself does not need Riverpod |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Flutter Material `ReorderableListView` | SDK | Drag-to-reorder subdevice list | Identical to CX5010 dialog at `beckhoff.dart:240-274` |
| Flutter Material `DropdownButtonFormField` | SDK | Filtered "Add" picker | Identical to CX5010 at `beckhoff.dart:197-214` |
| `logger` package | (existing) | Sanitiser log line for dropped foreign types | Mirrors `AssetRegistry._log.t/.d/.e` style (`registry.dart:35`) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline whitelist `Map<String, Asset Function()>` | Reflect-by-type via `defaultFactories.entries.where(...)` | Inline map is what CX5010 uses (`_availableSubdevices` at `beckhoff.dart:21-28`) — clearer, no runtime-type magic, easier diff against CX5010 |
| `retainWhere` on `subdevices` inside `fromJson` | A separate `sanitise()` instance method | `retainWhere` inside the factory matches "permissive render, restrictive add" — sanitisation happens once at load, not on every `allKeys` call |
| Override `allKeys` to recurse generically | Loop with `sub is BaseAsset` cast | CX5010 uses the cast pattern; recursion happens naturally because each sub's own `allKeys` recurses (subdevices that are themselves composites — STACK-FUT-01 future-proofing) |

**Installation:** Nothing to install — all dependencies already in `pubspec.yaml`.

**Version verification:** Skipped — no new packages. The build_runner command remains `dart run build_runner build --delete-conflicting-outputs` (project convention).

## Architecture Patterns

### System Architecture Diagram

```
[ Operator drag from palette ]
            │
            ▼
[ AdvantysSTBStackConfig.preview() ]   ◄── from defaultFactories[AdvantysSTBStackConfig]
            │
            ▼
[ Place on page → save → JSON ]
            │
            ▼  jsonEncode round-trip
[ Saved JSON in SharedPreferences ]
            │
            ▼
[ AssetRegistry.parse → AssetListConverter.fromJson ] ──┐
            │                                            │ for each subdevice JSON
            ▼                                            ▼
[ AdvantysSTBStackConfig.fromJson ]               [ STBxxxxConfig.fromJson ]
            │                                            │
            ▼ post-fromJson sanitiser                    │
[ retainWhere(_isAllowedSTBChildType) ]                  │
            │                                            │
            ▼                                            ▼
[ stack.subdevices = [STBxxxxConfig, ...] ─ filtered ]
            │
            ▼  page render
[ FittedBox(BoxFit.contain) ]
            │
            ▼
[ Row(mainAxisSize.min, ...) ]
            │
            ├─► _SubdeviceNormalized(child: sub.build(context))    ◄── one per subdevice
            ├─► _SubdeviceNormalized(...)
            └─► _SubdeviceNormalized(...)
                                │
                                ▼
                  [ Each STBxxxxConfig.build → its live ConsumerWidget ]
                                │
                                ▼  subscribe via stateManProvider
                  [ StateMan / OPC UA / Modbus ]
                                │
                                ▼
                  [ Live LEDs, force overlays, tap-to-detail ]

[ Operator opens configure dialog ]
            │
            ▼
[ _AdvantysSTBStackConfigContent ]
            │
            ├─► SizeField, CoordinatesField (BaseAsset metadata)
            └─► RIGHT pane:
                    ├─► DropdownButtonFormField    (4 STB types ONLY)
                    └─► ReorderableListView         (drag-handle + delete IconButton)

[ alarms / collectors enumerate keys ]
            │
            ▼
[ stack.allKeys ]
            │
            ▼  override flat-maps
[ for sub in subdevices: keys.addAll(sub.allKeys) ]
            │
            ▼
[ Set<String> → de-duplicated, empty-filtered list ]
```

### Recommended Project Structure
```
lib/page_creator/assets/
├── advantys_stb.dart        # APPEND AdvantysSTBStackConfig + _SubdeviceNormalized clone + _AdvantysSTBStackConfigContent
├── advantys_stb.g.dart      # REGENERATED by build_runner
├── registry.dart            # ADD 2 lines (one per map)
└── common.dart              # NO CHANGES

test/page_creator/assets/
├── advantys_stb_test.dart   # APPEND ~6 test groups for the stack
└── goldens/advantys_stb/
    ├── stack_full_light.png # NEW
    └── stack_full_dark.png  # NEW
```

### Pattern 1: CX5010-Verbatim Composite Class Skeleton
**What:** The class shape to clone, line-by-line, from `beckhoff.dart:30-110`.
**When to use:** Always — this is the locked Phase 5 pattern.
**Example:**
```dart
// Source: lib/page_creator/assets/beckhoff.dart:21-110 (CX5010 verbatim)
const Map<String, Asset Function()> _availableSTBSubdevices = {
  "STBNIP2311 (Ethernet Head)": STBNIP2311Config.preview,
  "STBPDT3100 (24 VDC PDM)":    STBPDT3100Config.preview,
  "STBDDI3725 (16-Ch DI)":      STBDDI3725Config.preview,
  "STBDDO3705 (16-Ch DO)":      STBDDO3705Config.preview,
};

// The set of allowed runtimeType strings — used by the sanitiser.
const Set<String> _kAllowedSTBChildTypeNames = {
  'STBNIP2311Config',
  'STBPDT3100Config',
  'STBDDI3725Config',
  'STBDDO3705Config',
};

@JsonSerializable()
class AdvantysSTBStackConfig extends BaseAsset {
  @override
  String get displayName => 'Advantys STB Stack';
  @override
  String get category => 'Advantys STB';

  @AssetListConverter()
  List<Asset> subdevices = [];

  AdvantysSTBStackConfig();
  AdvantysSTBStackConfig.preview() : super();

  @override
  List<String> get allKeys {
    final keys = <String>{};
    for (final sub in subdevices) {
      if (sub is BaseAsset) {
        keys.addAll(sub.allKeys);
      }
    }
    return keys.toList();
  }

  // The ONE piece without a CX5010 precedent — the sanitiser.
  factory AdvantysSTBStackConfig.fromJson(Map<String, dynamic> json) {
    final cfg = _$AdvantysSTBStackConfigFromJson(json);
    final before = cfg.subdevices.length;
    cfg.subdevices.retainWhere(
      (s) => _kAllowedSTBChildTypeNames.contains(s.runtimeType.toString()),
    );
    final dropped = before - cfg.subdevices.length;
    if (dropped > 0) {
      // Same logger style as AssetRegistry.parse (registry.dart:35,154).
      Logger().w('AdvantysSTBStack: dropped $dropped non-STB subdevice(s)');
    }
    return cfg;
  }

  @override
  Map<String, dynamic> toJson() => _$AdvantysSTBStackConfigToJson(this);

  // build() and configure() — see Patterns 2 and 3 below.
}
```
**Note:** The `Logger()` import is `package:logger/logger.dart` — already a transitive dep, and `AssetRegistry` uses `Logger _log = Logger();` exactly this way (`registry.dart:35`).

### Pattern 2: build() — FittedBox + Row of `_SubdeviceNormalized`
**What:** The render shape. CX5010 sits its OWN body painter to the left of the subdevice row; the stack has NO body painter, so the Row contains ONLY normalised subdevices.
**When to use:** Always.
**Example:**
```dart
// Source: lib/page_creator/assets/beckhoff.dart:56-92 (CX5010 build)
// AdvantysSTBStack variant: drop the leading CustomPaint, keep the Row.
@override
Widget build(BuildContext context) {
  final targetSize = size.toSize(MediaQuery.of(context).size);
  return SizedBox.fromSize(
    size: targetSize,
    child: FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final sub in subdevices)
            _STBSubdeviceNormalized(
              child: sub.build(context),
              targetHeight: _stackNativeHeight,  // any reasonable native; 1000 mirrors CX5010
            ),
        ],
      ),
    ),
  );
}
```

### Pattern 3: `_STBSubdeviceNormalized` — drop-in clone
**What:** ~20 LoC private widget at the bottom of `advantys_stb.dart`. Per CONTEXT.md §Compose Pattern, do NOT extract this to a shared location (no cross-cutting refactor while shipping additive features — OOS-07 / project anti-pattern).
**Example:**
```dart
// Source: lib/page_creator/assets/beckhoff.dart:114-134 (_SubdeviceNormalized)
class _STBSubdeviceNormalized extends StatelessWidget {
  final double targetHeight;
  final Widget child;
  const _STBSubdeviceNormalized({
    required this.targetHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: targetHeight,
      child: FittedBox(
        fit: BoxFit.fitHeight,
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}
```

### Pattern 4: Configure Dialog — `_AdvantysSTBStackConfigContent`
**What:** The full configure dialog. Verbatim copy of `_CXxxxxConfigContent` at `beckhoff.dart:136-285` with one substitution: `_availableSubdevices` → `_availableSTBSubdevices`.
**When to use:** Always.
**Example:** See `beckhoff.dart:136-285`. Specifically:
- LEFT pane: `Padding(EdgeInsets.all(20))` + `SizeField` + `CoordinatesField(enableAngle: true)`.
- RIGHT pane: header Row with "Subdevices" + "Done" button → DropdownButtonFormField (label "Add Subdevice", iterates `_availableSTBSubdevices.keys`) → Empty-state Centered Text → `ReorderableListView.builder`:
  - `buildDefaultDragHandles: false`
  - `ListTile(key: ObjectKey(sub), leading: ReorderableDragStartListener, title: Text(sub.runtimeType.toString()), onTap: showDialog → sub.configure(context), trailing: IconButton(Icons.delete))`
  - `onReorder` adjusts index, removeAt + insert.

The CONTEXT.md mentions "confirmation" on delete but the CX5010 source has NO confirmation — direct `setState(() => widget.config.subdevices.removeAt(index))`. Mirror CX5010 (no confirmation); CONTEXT.md was loose phrasing.

### Pattern 5: Registry Registration
**What:** Two single-line additions in `registry.dart`.
**Example:**
```dart
// In _fromJsonFactories map (after STBPDT3100Config, registry.dart:69):
AdvantysSTBStackConfig: AdvantysSTBStackConfig.fromJson,

// In defaultFactories map (after STBPDT3100Config, registry.dart:114):
AdvantysSTBStackConfig: AdvantysSTBStackConfig.preview,
```
The import for `AdvantysSTBStackConfig` is already in place: `registry.dart:17` already imports `'advantys_stb.dart'` (Phases 1–4 set this up).

### Anti-Patterns to Avoid
- **Extracting `_SubdeviceNormalized` to a shared file.** OOS-07 + CONTEXT.md §Compose Pattern. Cross-cutting refactor while shipping additive features is the locked-out anti-pattern.
- **Adding a body painter to the stack.** CONTEXT.md §Specifics: "the stack itself has no painter body — it's a pure composition wrapper." `build()` returns `FittedBox + Row` only.
- **Putting the whitelist filter ONLY in the dropdown.** Restrictive add is necessary but not sufficient — without the post-`fromJson` sanitiser, a hand-edited JSON (or a malicious copy-paste from another page) could inject a non-STB type, and STACK-05 requires both layers.
- **Putting the sanitiser ONLY in the sanitiser.** Permissive render: if a non-STB type DOES survive (e.g., from a forward-compat scenario where v3.0 adds a new STB type), `build()` must NOT crash. CX5010's `for sub in subdevices: sub.build(context)` is type-agnostic; mirror it.
- **Using `ref.watch` from inside a non-Riverpod composite.** The stack itself does not subscribe to anything; each subdevice handles its own subscription. Adding a Riverpod read here would defeat the QUAL-03 hoisting discipline already established in Phases 1–4.
- **Calling `setState` from anything other than the configure dialog State class.** The stack config is a plain data class; subdevices list mutation happens inside `_AdvantysSTBStackConfigContentState.setState`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Polymorphic List<Asset> JSON converter | A custom converter that switches on `asset_name` | `@AssetListConverter()` — already at `lib/page_creator/page.dart:35-47` | Delegates to `AssetRegistry.parse`; correctly handles nested composites; battle-tested for CX5010, EK1100, and the top-level `AssetPage.assets` |
| Drag-to-reorder list UI | A custom DragTarget+Draggable stack | Flutter SDK `ReorderableListView.builder` | CX5010 uses it verbatim; handles accessibility, keyboard reorder, and animation |
| Filtered "Add" dropdown | A custom popup menu | `DropdownButtonFormField<String>` iterating `_availableSTBSubdevices.keys` | CX5010 pattern; integrates with Material form theming automatically |
| `allKeys` recursion for nested composites | Manual recursion code | The leaf's own `allKeys` getter recurses naturally | If a subdevice is itself a composite, its `allKeys` walks ITS subdevices; the parent just calls `sub.allKeys` once |
| Foreign-type detection by `is X || is Y || is Z` | Series of `is`-checks | `_kAllowedSTBChildTypeNames.contains(s.runtimeType.toString())` | Symmetric with `AssetRegistry.parse`'s `factory.key.toString() == assetName` convention (`registry.dart:148`); the runtimeType string IS the canonical discriminator everywhere else |
| JSON codegen | Hand-written fromJson/toJson | `@JsonSerializable()` + `dart run build_runner build` | Every other asset uses codegen; consistency >> bespoke |

**Key insight:** The CX5010 IS the pattern. The temptation to "improve" anything (extract helpers, generalize, sanitize earlier in the pipeline) breaks the line-by-line diff against CX5010, which is the locked invariant for review.

## Common Pitfalls

### Pitfall 1: Override `allKeys` but forget the empty-string filter
**What goes wrong:** A subdevice with a null `rawStateKey` serialises to JSON-null but the default `_extractKeysFromJson` already filters those (`common.dart:238`: `if (value is String && value.isNotEmpty)`). However, an explicit override that just does `subdevices.expand((s) => s.allKeys).toList()` is fine because the children already filter empties — but a *minor* drift like `subdevices.expand((s) => s.allKeys).toSet().toList()` LOSES the order, which goldens-of-keys tests may care about. **Mirror CX5010's `for ... keys.addAll(...)` shape exactly** for stable enumeration.
**Warning sign:** `expect(keys, ['a', 'b'])` style tests fail with `['b', 'a']` after a refactor — that's the Set ordering issue.

### Pitfall 2: Sanitiser drops legitimate types because of class-name typos
**What goes wrong:** `_kAllowedSTBChildTypeNames` contains a class name that doesn't match what Dart's `runtimeType.toString()` returns. For example, if someone writes `'STBDDI3725'` instead of `'STBDDI3725Config'`, every legitimate child is silently dropped on load. The page appears empty after a save/load cycle.
**Why it happens:** `runtimeType.toString()` returns the unprefixed class name (`'STBDDI3725Config'`), NOT `'package:tfc/page_creator/assets/advantys_stb.dart::STBDDI3725Config'`. Easy to assume otherwise.
**How to avoid:** Write a unit test that constructs one instance of each allowed type and asserts `_kAllowedSTBChildTypeNames.contains(it.runtimeType.toString())`. The test fails LOUDLY if a typo slips in.
**Warning sign:** Integration test passes (because the test constructs the stack in-memory), but a save → restart → load cycle drops all children.

### Pitfall 3: Add the new asset to ONLY ONE registry map
**What goes wrong:** Add to `_fromJsonFactories` but forget `defaultFactories` (or vice versa). Symptoms:
- Forgot `_fromJsonFactories`: saved pages with the stack silently disappear (`AssetRegistry.parse` skips unknown `asset_name`).
- Forgot `defaultFactories`: palette has no "Advantys STB Stack" entry; operator cannot place one.
**Why it happens:** Two separate Maps at `registry.dart:37-81` and `83-126`; easy to update one and miss the other.
**How to avoid:** Phase 5's `STACK-01` requirement explicitly says "registered in `AssetRegistry` (both `_fromJsonFactories` and `defaultFactories`)". Tests `createDefaultAssetByName` AND `AssetRegistry.parse` round-trip — the existing pattern at `advantys_stb_test.dart:778-827`.
**Warning sign:** Half the tests pass.

### Pitfall 4: Codegen drift after editing fromJson factory
**What goes wrong:** The sanitiser wraps `_$AdvantysSTBStackConfigFromJson(json)`. If you forget to run `build_runner` after adding the class, that generated function doesn't exist → compile error. If you edit the class signature later (e.g., add a field) without re-running build_runner, the generated code goes stale → tests fail with mismatched fields.
**How to avoid:** Always run `dart run build_runner build --delete-conflicting-outputs` after editing any `@JsonSerializable()` class. CI runs `flutter analyze` which catches the missing-symbol case.
**Warning sign:** `_$AdvantysSTBStackConfigFromJson is not defined`.

### Pitfall 5: Test the wrong taps-pass-through assertion
**What goes wrong:** CONTEXT.md §Integration Test claims "taps register on each subdevice (not falling through to the stack frame — verified by `GestureDetector(HitTestBehavior.opaque)` wrapping)." But NIP and PDT do NOT have GestureDetector — they are decorative. Writing a test that asserts "tapping on the NIP body opens a detail dialog" would fail because NIP has no `onTap`. Worse, asserting "no exception" is too weak — a test that taps anywhere passes vacuously.
**Correct assertion:** Only DDI and DDO have tap-to-open-dialog behaviour. The integration test should:
1. Tap on DDI's body → AlertDialog appears.
2. Tap on DDO's body → AlertDialog appears.
3. Tap on NIP/PDT bodies → no exception thrown, no dialog (decorative-only).
**Warning sign:** Test passes that shouldn't (taps in empty space).

### Pitfall 6: `ObjectKey(sub)` in ReorderableListView breaks on type-changing edits
**What goes wrong:** CX5010 uses `key: ObjectKey(sub)` (`beckhoff.dart:255`). The Asset object identity must be stable across rebuilds. If the configure dialog replaces a subdevice with a fresh `STBxxxxConfig` instance (e.g., from `preview()` again), the key changes and ReorderableListView re-animates from scratch — visual glitch but not a bug.
**How to avoid:** Use `ObjectKey(sub)` as CX5010 does; do not synthesize a derived key. The mutation flow is "remove + insert" not "replace in place," so identity is stable across reorders.

## Code Examples

### Adding a sanitiser unit test (NET-NEW pattern)
```dart
// Source: NEW — no CX5010 precedent. Lives at advantys_stb_test.dart.
group('AdvantysSTBStackConfig.fromJson sanitiser', () {
  test('retains only the 4 STB module types', () {
    final json = <String, dynamic>{
      'asset_name': 'AdvantysSTBStackConfig',
      'coordinates': {'x': 0.0, 'y': 0.0},
      'size': {'width': 0.5, 'height': 0.5},
      'subdevices': [
        STBNIP2311Config.preview().toJson(),
        STBDDI3725Config.preview().toJson(),
        ButtonConfig.preview().toJson(), // foreign — must be dropped
        STBPDT3100Config.preview().toJson(),
      ],
    };
    final cfg = AdvantysSTBStackConfig.fromJson(json);
    expect(cfg.subdevices, hasLength(3));
    expect(cfg.subdevices.map((s) => s.runtimeType.toString()), [
      'STBNIP2311Config',
      'STBDDI3725Config',
      'STBPDT3100Config',
    ]);
  });

  test('runtimeType strings of allowed children match the whitelist exactly', () {
    // Guards against typos in _kAllowedSTBChildTypeNames.
    expect(STBNIP2311Config.preview().runtimeType.toString(),
        'STBNIP2311Config');
    expect(STBPDT3100Config.preview().runtimeType.toString(),
        'STBPDT3100Config');
    expect(STBDDI3725Config.preview().runtimeType.toString(),
        'STBDDI3725Config');
    expect(STBDDO3705Config.preview().runtimeType.toString(),
        'STBDDO3705Config');
  });
});
```

### Integration test (the QUAL-07 anchor)
```dart
// Source: NEW. Mirrors existing 'mount sanity' pattern at advantys_stb_test.dart:281+.
group('AdvantysSTBStack full-stack integration (QUAL-07)', () {
  testWidgets('1× NIP + 1× PDT + 1× DDI + 1× DDO renders cleanly', (tester) async {
    final stack = AdvantysSTBStackConfig()
      ..subdevices = [
        STBNIP2311Config.preview(),
        STBPDT3100Config.preview(),
        STBDDI3725Config(nameOrId: 'DI', rawStateKey: 'plc.di.raw'),
        STBDDO3705Config(nameOrId: 'DO', rawStateKey: 'plc.do.raw'),
      ]
      ..size = const RelativeSize(width: 0.8, height: 0.3);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Same stateManProvider override convention as Phases 1-4 tests.
          stateManProvider.overrideWith((ref) async => _FakeStateMan()),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: stack.build(tester.element(find.byType(Scaffold)))))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  test('stack.allKeys returns the union of every subdevice\'s keys', () {
    final stack = AdvantysSTBStackConfig()
      ..subdevices = [
        STBDDI3725Config(rawStateKey: 'di.raw', forceValuesKey: 'di.force'),
        STBDDO3705Config(rawStateKey: 'do.raw'),
        STBPDT3100Config(inputOkKey: 'pdt.ok'),
        STBNIP2311Config(), // contributes nothing — decorative
      ];
    expect(stack.allKeys, containsAll(['di.raw', 'di.force', 'do.raw', 'pdt.ok']));
    expect(stack.allKeys, hasLength(4)); // no duplicates, no empties
  });
});
```

### Golden test for `stack_full_{light,dark}.png`
```dart
// Source: mirrors existing ddi3725 goldens at advantys_stb_test.dart:327-501.
group('AdvantysSTBStack goldens',
    skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
  const goldenKey = Key('stb_stack_full_golden');

  Future<void> pumpStack(WidgetTester tester, {required Brightness theme}) async {
    final stack = AdvantysSTBStackConfig()
      ..subdevices = [
        STBNIP2311Config.preview(),
        STBPDT3100Config.preview(),
        STBDDI3725Config.preview(),
        STBDDO3705Config.preview(),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [stateManProvider.overrideWith((ref) async => _FakeStateMan())],
        child: MaterialApp(
          theme: theme == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: goldenKey,
                child: SizedBox(width: 800, height: 200, child: stack.build(tester.element(find.byType(Scaffold)))),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('stack_full_light.png', (tester) async {
    await pumpStack(tester, theme: Brightness.light);
    await expectLater(find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/stack_full_light.png'));
  });

  testWidgets('stack_full_dark.png', (tester) async {
    await pumpStack(tester, theme: Brightness.dark);
    await expectLater(find.byKey(goldenKey),
        matchesGoldenFile('goldens/advantys_stb/stack_full_dark.png'));
  });
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-written polymorphic JSON converters | `@AssetListConverter()` delegating to `AssetRegistry.parse` | CX5010 introduction (pre-Phase-5) | New composites just annotate; no per-class converter |
| Goldens skipped via comment | Golden tests double-gated: `dart_test.yaml` tag + `skip: !Platform.isMacOS` | Phase 1 (this milestone) | Goldens run only on macOS dev hardware, never in CI by default |

**Deprecated/outdated:** None applicable — Phase 5 is pure additive composition; no migration concerns.

## Project Constraints (from CLAUDE.md)

- **Tech stack:** Flutter + Riverpod + Asset Registry + StateMan only — no new frameworks. ✓ Phase 5 adds zero new dependencies.
- **Pattern fidelity:** Mirror existing conventions; deviating breaks operator muscle memory and forces rework. ✓ Mirror CX5010 verbatim is the literal pattern-fidelity contract.
- **Backwards compatibility:** Saved pages must continue to load. ✓ Sanitiser is permissive (drops foreign types silently instead of throwing); legacy pages without the stack remain unaffected.
- **Codegen:** New configs require `*.g.dart` via build_runner. ✓ `dart run build_runner build --delete-conflicting-outputs` must run after the new class lands.
- **State-key driven:** No hard-coded values in production paths. ✓ Stack has no state keys of its own; only flat-maps children's.
- **TDD-first** (project skill / MEMORY.md feedback_tdd): Write tests before implementation. ✓ Plan structure should be: write sanitiser unit tests → write `allKeys` flat-map test → write integration test → THEN implement the class.
- **Gestures through translation** (MEMORY.md feedback_gesture_through_translation): Children's GestureDetectors must keep working. ✓ The stack is a Row (no Transform) so no translation; gestures pass through `FittedBox` and `Row` normally to subdevices.
- **flutter_lints / lints:** `flutter analyze` clean across new files (QUAL-06). ✓ Append-only changes; no new imports beyond `package:logger/logger.dart` (already widely used in lib/).
- **No `print()` in tfc_mcp_server:** N/A — Phase 5 lives in the main `lib/`, not in `packages/tfc_mcp_server/`.

## Runtime State Inventory

This section is **N/A** — Phase 5 is greenfield composite-class addition, not a rename/refactor/migration. No databases, services, OS-registered tasks, secrets, or build artifacts reference the new class name. Build artifact concern: after editing `pubspec.yaml` or adding new annotation usage, `dart run build_runner build` must regenerate `advantys_stb.g.dart` — but this is normal codegen, not migration. The `_$AdvantysSTBStackConfigFromJson` symbol does not exist until that runs.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The sanitiser should log dropped foreign types via `Logger().w(...)` (NOT throw, NOT silently retain) | Pattern 1 | If logger style drifts from `AssetRegistry`'s convention, log discoverability suffers but no functional impact. [CITED: registry.dart:35,152-160] confirms `_log.t/.d/.e` usage but `.w` is symmetrically valid. |
| A2 | The dropdown items should be the human-readable display strings ("STBDDI3725 (16-Ch DI)") rather than raw class names ("STBDDI3725Config") | Pattern 4 | CX5010 uses short keys ("EL1008"); the leaf configs have `displayName` already defined. Either choice works for operators — the keys above use displayName for parity with the LeftPane's `Text(sub.runtimeType.toString())` shown for added subdevices. Planner may simplify to short names like CX5010 uses. |
| A3 | `_stackNativeHeight = 1000` for `_STBSubdeviceNormalized.targetHeight` (mirrors CX5010's 1000 native units) | Pattern 2 | This is a unitless reference height that gets scaled by the outer FittedBox; any positive value produces the same visual result. The 1000 choice keeps math identical to CX5010 for easier diff. |
| A4 | No "confirmation" dialog before delete (CONTEXT.md says "with confirmation" but CX5010 has none) | Pattern 4 / Anti-Patterns | Adding a confirmation would diverge from CX5010 verbatim mirror. If user truly wants confirmation, planner should clarify — but CX5010-verbatim wins by default. |

If the planner finds any of these unacceptable, surface to `/gsd-discuss-phase` before locking the plan.

## Open Questions

1. **Should the configure dialog's "Add" dropdown use display names or class names?**
   - What we know: CX5010 uses short codes ("EL1008") matching the `_availableSubdevices` map keys; the STB leaf configs have richer `displayName` strings ("STBDDI3725 (16-Ch DI)").
   - What's unclear: Which the operator prefers reading in a Material dropdown.
   - Recommendation: Use the human-readable `displayName` strings as Map keys (e.g., `"STBDDI3725 (16-Ch DI)": STBDDI3725Config.preview`) — they're already operator-tested in palette listings. Planner can swap to short codes if a stakeholder requests it.

2. **Where do nameOrId / Coordinates / Size fields live in the configure dialog left pane?**
   - What we know: CX5010 shows ONLY `SizeField` + `CoordinatesField(enableAngle: true)` in its left pane. There is NO nameOrId field on `BeckhoffCX5010Config` (only on leaf modules).
   - What's unclear: Whether `AdvantysSTBStackConfig` needs a `nameOrId` field.
   - Recommendation: Omit `nameOrId` for parity with CX5010. Subdevices carry their own names; the stack is just a container. CONTEXT.md §Specifics implies it should ("stack-level metadata `nameOrId`, `Coordinates`, `Size`") but the CX5010 mirror says otherwise. If desired, add it later as a deferred enhancement.

3. **Should `enableAngle` be true on the stack's `CoordinatesField`?**
   - What we know: CX5010 uses `enableAngle: true` (`beckhoff.dart:168`). The four leaf STB modules do NOT enable angle in their configurators.
   - Recommendation: `enableAngle: true` mirror CX5010 — operators may want to rotate a horizontal stack 90° to stand vertically on the page.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK (stable) | All build/test | ✓ | (per nix flake) | — |
| Dart SDK | Codegen + tests | ✓ | ^3.5.1 (root) / ^3.6.0 (centroid-hmi) | — |
| build_runner | Codegen | ✓ | ^2.4.15 [VERIFIED: pubspec.yaml] | — |
| json_serializable | Codegen | ✓ | ^6.9.4 [VERIFIED: pubspec.yaml] | — |
| All four STB leaf module configs (Phases 1-4) | Whitelist + integration test | ✓ | Phases 1-4 complete (per ROADMAP.md, all ✅) | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK) + `dart_test ^1.25.0` |
| Config file | `/Users/jonb/Projects/tfc-hmi2/dart_test.yaml` (golden tag skip) |
| Quick run command | `flutter test test/page_creator/assets/advantys_stb_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STACK-01 | Stack registered in both registry maps | unit | `flutter test --plain-name "createDefaultAssetByName returns a typed AdvantysSTBStackConfig" test/page_creator/assets/advantys_stb_test.dart` | ❌ Wave 0 (append new test group) |
| STACK-02 | `subdevices: List<Asset>` with `@AssetListConverter()` round-trips JSON | unit | `flutter test --plain-name "AdvantysSTBStack full JSON round-trip" test/page_creator/assets/advantys_stb_test.dart` | ❌ Wave 0 (append) |
| STACK-03 | `allKeys` flat-map de-duplicates + filters empties | unit | `flutter test --plain-name "stack.allKeys returns the union" test/page_creator/all_keys_test.dart` | ❌ Wave 0 (append to existing all_keys_test.dart) |
| STACK-04 | Configure dialog: filtered dropdown + ReorderableListView + delete | widget | `flutter test --plain-name "AdvantysSTBStack configure dialog" test/page_creator/assets/advantys_stb_test.dart` | ❌ Wave 0 (append) |
| STACK-05 | Post-fromJson sanitiser drops foreign types | unit | `flutter test --plain-name "AdvantysSTBStackConfig.fromJson sanitiser" test/page_creator/assets/advantys_stb_test.dart` | ❌ Wave 0 (append) |
| QUAL-06 | `flutter analyze` zero issues on all new files | static | `flutter analyze lib/page_creator/assets/advantys_stb.dart lib/page_creator/assets/registry.dart` | ✓ (analyze always available) |
| QUAL-07 | Integration test: 1× of each + goldens render + taps register on DDI/DDO | widget + golden | `flutter test test/page_creator/assets/advantys_stb_test.dart` (full file) + `flutter test --update-goldens` for golden creation | ❌ Wave 0 (append integration + 2 goldens) |

### Sampling Rate
- **Per task commit:** `flutter test test/page_creator/assets/advantys_stb_test.dart` (the full STB test file — ~135 tests today + ~10-15 new = 30s on M-series Mac).
- **Per wave merge:** `flutter test test/page_creator/` (covers cross-file `all_keys_test.dart` + registry tests).
- **Phase gate:** `flutter test && flutter analyze` — both green before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `test/page_creator/assets/advantys_stb_test.dart` — append ~6 new test groups (sanitiser, allKeys, configure dialog, JSON round-trip, JSON back-compat, integration + goldens) for STACK-01..05 + QUAL-07. ~200-300 LoC appended.
- [ ] `test/page_creator/all_keys_test.dart` — append `AdvantysSTBStackConfig returns keys from subdevices` + `AdvantysSTBStackConfig with empty subdevices returns empty` (mirror lines 220-237 for CX5010).
- [ ] `test/page_creator/assets/goldens/advantys_stb/stack_full_light.png` + `stack_full_dark.png` — produced via `flutter test --update-goldens` on macOS dev hardware.
- [ ] No framework install required — all tooling already present.

## Security Domain

`security_enforcement` is **not configured** in `.planning/config.json` (treat as enabled per project convention). Applicable analysis:

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Not applicable — UI composite; no auth surface |
| V3 Session Management | no | Not applicable |
| V4 Access Control | no | Not applicable (TFC_GOD gate is at page-editor level, not asset level) |
| V5 Input Validation | yes | JSON deserialization via `json_serializable` codegen; the new sanitiser is itself an input-validation control (rejecting foreign types) |
| V6 Cryptography | no | Not applicable |

### Known Threat Patterns for Flutter + JSON deserialization

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Untrusted JSON injection via hand-edited page config | Tampering | Post-`fromJson` sanitiser (STACK-05) — restricts subdevices to 4 known types regardless of input |
| Type-confusion via `asset_name` collision | Tampering | `AssetRegistry.parse` matches via `factory.key.toString() == assetName` (`registry.dart:148`); only registered types deserialize |
| Resource exhaustion via 1000s of subdevices | Denial of Service | No mitigation today; CX5010 has no cap either. Out of scope — page persistence is user-controlled |
| Codegen drift hiding a removed `@JsonSerializable` field | Tampering | `flutter analyze` catches symbol mismatches; codegen is checked into git and reviewable |

**Conclusion:** The sanitiser IS the security control. No other ASVS exposure introduced by Phase 5.

## Sources

### Primary (HIGH confidence)
- `lib/page_creator/assets/beckhoff.dart` lines 21-285 — CX5010 verbatim source for every locked pattern (the line-by-line mirror)
- `lib/page_creator/assets/beckhoff.dart` lines 287-355 — EK1100 (a second composite using the exact same shape; cross-checks the pattern)
- `lib/page_creator/assets/beckhoff.g.dart` lines 9-34 — Generated `_$BeckhoffCX5010ConfigFromJson` showing exact codegen shape with `AssetListConverter`
- `lib/page_creator/page.dart` lines 35-47 — `AssetListConverter` definition (delegates to `AssetRegistry.parse`)
- `lib/page_creator/assets/registry.dart` lines 37-126 — Both factory Maps, current STB registrations confirm Phases 1-4 wiring
- `lib/page_creator/assets/registry.dart` lines 138-176 — `AssetRegistry.parse` crawler (silent log-and-skip convention)
- `lib/page_creator/assets/advantys_stb.dart` (1249 LoC) — All four leaf STB configs verified: STBNIP2311Config (903), STBPDT3100Config (1058), STBDDI3725Config (62), STBDDO3705Config (548); each has `.preview()` factory and `runtimeType.toString()` returns the exact class name
- `lib/page_creator/assets/common.dart` lines 218-243 — `BaseAsset.allKeys` default + `_extractKeysFromJson` regex (`^key$|^key\d+$|Key$|_key$`)
- `test/page_creator/assets/advantys_stb_test.dart` (2829 LoC, 135 tests) — Established Phase 1-4 test patterns: registry-resolution (778), JSON round-trip (849), back-compat (896), goldens (327, macOS-gated), mount-sanity (281)
- `test/page_creator/all_keys_test.dart` lines 220-237 — Existing CX5010 allKeys test pattern (the direct precedent to mirror)
- `dart_test.yaml` — Golden skip tag config
- `pubspec.yaml` — Dependency versions (build_runner ^2.4.15, json_serializable ^6.9.4, flutter_riverpod ^2.6.1)

### Secondary (MEDIUM confidence)
- `.planning/ROADMAP.md` §Phase 5 — Phase contract; Success Criteria 1-5 (lines 84-89)
- `.planning/REQUIREMENTS.md` STACK-01..05 + QUAL-06,07 (lines 15-19, 66-67)
- `.planning/phases/05-advantysstbstack-composite-parent/05-CONTEXT.md` — User decisions (locked)

### Tertiary (LOW confidence)
- None — every claim is verifiable in the codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; everything is reuse of confirmed in-tree libraries.
- Architecture: HIGH — CX5010 source is the literal pattern; verified line-by-line.
- Pitfalls: HIGH — sanitiser-typo and registry-half-update are real risks observed in adjacent code reviews; the GestureDetector asymmetry is verified in source (DDI/DDO have it, NIP/PDT don't).

**Research date:** 2026-05-12
**Valid until:** 30 days (stable Flutter/Riverpod surface; no fast-moving dependencies)
