# Pitfalls Research — v2.0 Modicon Momentum I/O Assets

**Domain:** Industrial HMI — multi-module fieldbus I/O stacks (head adapter + power module + 16-channel DI + 16-channel DO), with force overrides, per-channel filters, and per-channel descriptions, all driven by Modbus-resident PLC state keys.
**Pattern source of truth:** `lib/page_creator/assets/beckhoff.dart` (BeckhoffCX5010/EK1100 stack + EL1008/EL2008 modules) and `lib/painter/beckhoff/io8.dart`.
**Researched:** 2026-05-11
**Confidence:** HIGH for items grounded in current beckhoff.dart / io8.dart / conveyor.dart code; MEDIUM for Modbus-specific items (Schneider Momentum register layout cited from training data + Schneider portal hit, not verified against a live device — flagged inline); user photo at `/Users/jonb/.claude/image-cache/fe2be5fa-6578-40a7-bc7b-7475838556e9/3.png` consulted for actual physical layout (16-channel modules are vertical strips with two columns of channel terminals).

This file enumerates failure modes the v2.0 Momentum milestone must guard against. Each pitfall cites the specific tfc-hmi2 file where it would manifest in, the warning signs an operator/developer would see, the prevention strategy, and the phase that owns the mitigation.

---

## Critical Pitfalls

### Pitfall M-01: `MomentumStack.allKeys` silently drops sub-module keys when a child fails to override the getter

**What goes wrong:**
The Beckhoff stack works because `BeckhoffCX5010Config.allKeys` walks `subdevices` and unions each child's `allKeys` (beckhoff.dart:42-50). The default `BaseAsset.allKeys` (common.dart:218) introspects `toJson()` for fields matching `^key$|^key\d+$|Key$|_key$` — so the EL1008's `rawStateKey`, `forceValuesKey`, `onFiltersKey`, `offFiltersKey` etc. are auto-discovered by suffix.

If a new Modicon module is added with a field name that does NOT match that regex — e.g. `inputWordTag`, `forces`, `description_map` — the default `allKeys` silently returns an empty list. `MomentumStackConfig.allKeys` would then expose the head module's keys but not the DI/DO module's keys. The alarm engine and collector skip the module. Operators don't see any error — alarms just never fire and history is empty for those channels.

**Why it happens:**
`BaseAsset.allKeys` is opt-out (regex-based) rather than explicit. The regex was tuned for EL1008/EL2008's naming. New module developers don't know the regex exists until alarms go quiet.

**Warning signs:**
- Alarm Editor shows no entries when filtered to the new module's keys.
- `Collector` PostgreSQL table is empty for the module's channels even though the page renders correctly.
- `lib/chat/asset_context_menu.dart` "Ask Claude about this asset" includes no PLC values for the new module — Claude says "no PLC context available."
- A `print(config.allKeys)` in tests returns `[]` for a module that obviously has tag keys configured.

**Prevention:**
1. **Name every state-key field with the `*Key` suffix** to stay in the regex's happy path: `rawStateKey`, `forceValuesKey`, `onFiltersKey`, `offFiltersKey`, `descriptionsKey` — mirror EL1008 verbatim.
2. **Override `allKeys` on every new config that has nested children or non-String key storage** (e.g. `MomentumStackConfig`, `DDI3725Config` if it gains a list of per-channel descriptions). Always test the override via a unit test that constructs a fully-configured instance and asserts `allKeys` contains every expected key.
3. **Add an `allKeys` regression test per module config** in `test/page_creator/assets/modicon_<module>_allkeys_test.dart` that hardcodes the expected key set — drift becomes a failing test, not a silent alarm outage.

**Phase:** Every phase that adds a new `BaseAsset` subclass — DI module phase, DO module phase, NIP head phase, PDT power phase, MomentumStack composition phase. The stack-composition phase MUST add an integration test that constructs a populated MomentumStack and asserts `allKeys` contains keys from every child.

---

### Pitfall M-02: 16-channel bit-extraction off-by-one and bit-order ambiguity (DDI3725 / DDO3705)

**What goes wrong:**
EL1008 packs 8 channels into one Modbus/OPC-UA integer using LSB-first ordering: `(map["raw"]!.asInt & (1 << i)) != 0` where `i ∈ 0..7` and `i==0` is channel 1 (beckhoff.dart:1374, 1378, 1290-1300). Cloning this pattern for 16 channels at a glance gives:

```dart
List.generate(16, (i) => (raw.asInt & (1 << i)) != 0)
```

Two failure modes:

1. **Off-by-one in the label/channel mapping.** Schneider's Momentum docs number channels 1..16 (and the DDI3725 datasheet labels terminals `I1..I16`). If the painter labels `ioLabels = ['I0', ..., 'I15']` (zero-indexed) but operators see `I1..I16` on the physical module, the visible "I3 is on" doesn't match the actual energised terminal. The opposite is also a trap — `['I1', ..., 'I16']` on the painter while internal arrays are `0..15` is fine for display but the per-channel description/force/filter arrays must use the SAME indexing convention end-to-end.

2. **Word ordering / endianness.** Schneider Modicon by historical convention is big-endian (Motorola format). Modbus/TCP transports each register as a 2-byte big-endian word, but the bit-within-word ordering inside that word is NOT standardised across vendors. Some Schneider modules pack channel 1 → bit 0 of the low byte; others pack channel 1 → bit 15 (MSB). The Beckhoff EL1008 LSB-first assumption is NOT portable to Momentum. (MEDIUM confidence: training data + Schneider portal references the bit-mapping but I have not verified against the DDI3725 datasheet at this session — see [Modicon Momentum I/O Base User Guide](https://iportal2.schneider-electric.com/Contents/docs/MODICON%20MOMENTUM%20_IO_%20BASE%20USER%20GUIDE.PDF), and the [Momentum 170ENT11001/170ENT11002 Ethernet Communications Adapter](https://igate.alamedaelectric.com/Modicon%20Documents/PLC%20Momentum%20PLC%20Ethernet%20(ENT)%20Adapter%20User%20Guide%20v2.0.pdf) which is the NIP family adapter manual.) If the PLC backend pre-normalises bit order before publishing to StateMan, the HMI can stay LSB-first; if it does NOT, the HMI is silently inverted (channel 16 shows when channel 1 is energised).

**Warning signs:**
- During on-site commissioning the operator energises terminal `I1` and the WRONG LED lights up (e.g. `I16`, or `I9` if the high/low byte is swapped).
- All 16 LEDs light in a coherent pattern but mirrored compared to the physical wiring.
- Unit tests pass (because they pass the same bit ordering both directions) but goldens look fine to the developer and wrong to the operator.

**Prevention:**
1. **Make the bit-ordering decision an explicit constant in `lib/painter/modicon/io16.dart`**, e.g. `const _channelOrder = ChannelBitOrder.lsbFirst;` (or `msbFirst`). Document the chosen convention in a comment block referencing the Schneider datasheet section.
2. **Add an explicit unit test** `test/page_creator/assets/modicon/ddi3725_bit_mapping_test.dart` that constructs a raw state value `0x0001` and asserts the painter draws channel 1 (and only channel 1) as `IOState.high`. Then `0x8000` → channel 16. Then `0xAAAA` → alternating LEDs. The test fails the moment someone swaps the constant.
3. **Add an alignment assert in the config class:** `assert(ioLabels.length == 16 && forceValues.length <= 16)`. EL1008 does this at io8.dart:37 — copy the pattern.
4. **In the configure dialog, expose a "Bit order" debug toggle** (only when `TFC_GOD=true`) so a commissioning engineer can flip it without a rebuild. Persist to JSON with a default that matches the documented Schneider convention.
5. **Confirm the bit convention with backend / PLC team before locking the golden tests**, so goldens encode the correct truth — not the developer's first guess.

**Phase:** DI module phase (DDI3725) — owns the bit-order decision. DO module phase (DDO3705) — must reuse the same convention. MomentumStack phase — no new exposure, but the stack-composition golden test will catch a regression if either module flips its convention.

---

### Pitfall M-03: Stream resubscribe storm when 16-channel painter rebuilds — N keys × N modules × N rebuilds

**What goes wrong:**
The EL1008 widget already uses `CombineLatestStream` over 2 keys (`raw`, `force`) for the painter and 6 keys (`raw`, `processed`, `force`, `descriptions`, `on_filters`, `off_filters`) for the dialog (beckhoff.dart:1272-1288). Each call to `stateMan.subscribe(key)` returns a `Future<Stream<DynamicValue>>` whose underlying OPC UA subscription is ref-counted via `AutoDisposingStream` with a 10-minute idle timeout.

If a 16-channel Momentum module is built naively — e.g. one `StreamBuilder` per channel — that's 16 subscriptions per module × 2 modules (DI + DO) = 32 subscriptions per stack on a single page. Worse, if the StreamBuilder lives inside a function called during `build()` (e.g. inside `LayoutBuilder.builder` or a list-builder closure), every Flutter rebuild creates a fresh stream subscription, fires the AutoDisposingStream listener count up to 2, then disposes the old one. The OPC UA / Modbus stack sees a churn of monitored-item add/remove operations. Symptoms: PLC CPU climbs, latency spikes, eventually subscriptions time out and LEDs go grey.

For a Modbus device specifically: every monitored-item creation forces a backoff-retry handshake. The Momentum NIP2311 is documented for hundreds of registers/sec but not for hundreds of subscribe/unsubscribe cycles/sec.

**Warning signs:**
- Open a page with several MomentumStack instances and watch the OPC UA log spam `MonitoredItem created/deleted/created/deleted` for the same NodeId.
- Flutter DevTools shows the same StreamSubscription being disposed and re-allocated every animation frame.
- CPU usage on the HMI machine climbs over 50% with one elevator page open.
- After ~10 minutes idle the LEDs go grey (AutoDisposingStream timeout fired because the last listener was disposed before a new one attached).

**Prevention:**
1. **Hoist subscriptions to the OUTERMOST stable widget.** The painter must NOT subscribe — it receives a `List<IOState>` already computed. Subscribe at the level of `_BeckhoffEL1008` / `_ModiconDDI3725`, which is a `ConsumerWidget` that is identity-stable across rebuilds.
2. **Combine multi-key reads with ONE `CombineLatestStream`**, not multiple `StreamBuilder`s. Copy the `_combinedStream` helper at beckhoff.dart:1272 verbatim into `lib/page_creator/assets/modicon.dart`. Each module exposes ONE state stream to its widget.
3. **Cache the stream in `initState` or memoize per-config-instance.** A `StatefulWidget` with `late final Stream<...> _stream = _combinedStream(...)` in initState (or a `useMemoized` analogue) prevents per-build resubscription. EL1008 currently gets away with rebuilding the stream because StateMan's `AutoDisposingStream` deduplicates, but with 32 keys per stack the dedup overhead compounds.
4. **Add a leak test** `test/page_creator/assets/modicon/ddi3725_subscription_lifecycle_test.dart` that mounts the widget, drives 100 rebuilds, and asserts the count of `StateMan.subscribe` calls is `O(1)`, not `O(rebuilds)`.
5. **Dialog subscriptions are scoped to the dialog.** When the operator opens the per-channel detail dialog with 6 keys, those subscriptions must end when the dialog closes — `showDialog` already handles this because the StreamBuilder lives inside the route. Verify by closing/reopening the dialog repeatedly and asserting no listener leak.

**Phase:** DI module phase (16-ch DI is the worst offender — 6 streams × 16 channels worth of detail). DO module phase (same pattern). NIP head phase (only 1 synthetic "comm OK" stream — minor exposure). MomentumStack phase: end-to-end leak test on a populated stack.

---

### Pitfall M-04: Force-override semantics drop the underlying raw state — painter shows `forcedHigh` but operator can't see whether the wire is actually live

**What goes wrong:**
EL1008's `_ledStates` (beckhoff.dart:1290-1300) collapses raw + force into a single `IOState`:

```dart
if (forceValue == 1) return IOState.forcedLow;
if (forceValue == 2) return IOState.forcedHigh;
if (data["raw"] == null) return IOState.low;
return (raw & (1 << i)) != 0 ? IOState.high : IOState.low;
```

The painter then draws `forcedHigh` as solid green with a red animated border (io8.dart:407-411). This is correct UX for an 8-channel module — the operator knows the channel is forced AND the border tells them so.

But the underlying physical wire state is lost: if `force == forcedLow` but the actual sensor on `I3` is energised, the operator sees a green-with-red-border LED that says "I'm forced low" — they CANNOT tell whether the input is actually present or not. For commissioning and fault diagnosis this is a non-trivial gap. The Momentum dialog needs to surface BOTH raw and forced state side-by-side, which is what EL1008's `RowIOView` does for the dialog (beckhoff.dart:1647-1670) via the `TriangleBoxPainter` showing left-half-raw / right-half-processed.

**The pitfall when adding Momentum:** because the milestone goal is "functionally on par with Beckhoff," the implementer copies the IOState enum verbatim and ships the same single-channel-state collapse. Operators then complain that they can't see the underlying input on a forced channel. Fixing this AFTER the painter / golden tests are locked is a much bigger rework than designing for it day 1.

**Warning signs:**
- Operator asks "is I3 actually energised right now, or just forced?" and there's no answer on the panel — only the dialog shows it.
- Goldens were taken at `force == auto, raw == high` and `force == forcedHigh, raw == low` but no golden exists for `force == forcedLow, raw == high` (the case where reality and operator intent diverge).
- The PLC code service or maintenance team needs to override-test wiring and finds the HMI useless for confirming the underlying input.

**Prevention:**
1. **Design a 4-state-per-channel struct from day 1**, not a single enum: `({bool raw, bool? processed, ForceMode force})`. The painter's IO state enum stays, but the data model preserves both axes.
2. **Painter visual decision: add a small dot or stripe inside the forced LED that reflects the underlying raw state.** E.g. a forced-low LED shows red border + green corner pip if the underlying input is actually high. This is one extra painter call per channel and one extra golden per (force × raw) combination = 6 goldens per module (auto/forcedLow/forcedHigh × raw low/high), not 5.
3. **Dialog ALWAYS shows raw + processed + force as three separate visual elements per channel** — copy the `TriangleBoxPainter` pattern (beckhoff.dart:1647) and scale it to 16 rows. Operators rely on this for commissioning.
4. **Confirm the four-state intent with the user before locking goldens.** This is a UX call; ship the wrong choice and rework costs are high.

**Phase:** DI module phase (the only phase where this matters — DO module has the same force-override mechanic but no "raw" axis since the output IS the forced value). The dialog covering all three axes must ship in the DI module phase; the painter pip / corner indicator is a separate decision that the phase plan should explicitly call out.

---

### Pitfall M-05: NIP2311 status LEDs (RUN / PWR / ERR / ST / TEST) are NOT Modbus-addressable — wiring them to PLC state keys produces meaningless renderings

**What goes wrong:**
A NIP2311 (Ethernet Modbus/TCP adapter) head module on a Modicon Momentum has a row of status LEDs on its faceplate. These reflect the adapter's INTERNAL state — Ethernet link status, Modbus protocol activity, comm error count, self-test state. They are driven by firmware inside the adapter ASIC, not by PLC application code. (MEDIUM confidence — per the [Momentum 170ENT11001/170ENT11002 Ethernet Communications Adapter](https://igate.alamedaelectric.com/Modicon%20Documents/PLC%20Momentum%20PLC%20Ethernet%20(ENT)%20Adapter%20User%20Guide%20v2.0.pdf) which is the NIP family doc. The newer NIP2311 follows the same conventions.)

Naively the implementer adds a `runStatusKey`, `pwrStatusKey`, `errStatusKey` etc. to NIP2311Config and exposes them in the configure dialog. Two failure modes:

1. **Operator misconfigures them with arbitrary PLC tags.** The HMI then renders LEDs that have NO causal relationship to the actual adapter state — they reflect whatever bool tag the operator picked. This is dangerous because operators will trust the visual.
2. **The keys are left empty.** The painter renders 5 grey LEDs forever. Operators don't know whether the module is healthy or whether the keys just aren't wired. The asset looks broken.

**Warning signs:**
- The configure dialog has fields for status LEDs whose default values are unclear and whose intent is undocumented.
- Operator reports "the RUN LED on the NIP is green on the panel but red on the HMI" — because they're disconnected.
- Onsite engineer says "where do I get the NIP status from?" and there's no answer in the backend.

**Prevention:**
1. **Make the NIP status LEDs decorative by default.** Render them statically as a faithful visual of a powered, running adapter: RUN green solid, PWR green solid, ERR off, ST off, TEST off. No state keys. This matches the physical module 99% of the time and avoids the misconfiguration trap.
2. **Optionally accept ONE "comm OK" boolean state key** that the backend synthesizes from "have I received a valid Modbus response in the last N seconds." When that key is configured, RUN goes red and ERR goes red if comm is down. All other LEDs remain decorative. Document this clearly in the configure dialog: "Synthetic comm-OK boolean from backend — leave empty to render as healthy."
3. **Do NOT expose five separate status-LED keys in the configure dialog.** Surface only the one synthetic key, with a docstring tooltip explaining why.
4. **Render the dual Ethernet port LEDs (link / activity) statically** unless / until the backend offers a "Ethernet up" boolean per port. Same rationale.

**Phase:** NIP head phase — owns this decision entirely. Must NOT add five `*Key` fields to NIP2311Config (which would dirty `allKeys` with meaningless tags). The configure dialog spec is the deliverable.

---

### Pitfall M-06: JSON round-trip breaks when v2.0 introduces a new field on a config that exists in v1.0 saved pages

**What goes wrong:**
v1.0 has shipped saved pages with `BeckhoffEL1008Config`, `ElevatorConfig`, `SensorConfig`, etc. If the v2.0 milestone touches a shared base class (e.g. `BaseAsset`, or adds a field to `BaseAsset.toJson`), or modifies an existing asset's schema (e.g. adds a per-channel description to EL1008), saved JSON without the new field will fail to deserialize.

The conveyor's `_gatesFromJson` legacy shim (conveyor.dart:26-48) is the prior-art pattern: it accepts BOTH the old schema (flat `ConveyorGateConfig` with `asset_name` at root) AND the new schema (`ChildGateEntry` wrapping the gate) and produces the new representation. The cost is that EVERY new field needs a `defaultValue:` annotation OR a custom `fromJson` helper that tolerates absence.

**Two concrete failure modes for v2.0:**

1. **MomentumStack borrows the BeckhoffCX5010 `subdevices: List<Asset>` field via `AssetListConverter`.** This works for new MomentumStacks but if an operator's saved page somehow contains a Momentum-prototype stack with a different field name (e.g. `modules` from an earlier prototype), deserialization throws. Prevention: pin the field name to `subdevices` from day 1 and don't rename it.

2. **`*.g.dart` not regenerated after schema change.** Build runner caches aggressively. A developer adds a field, edits an existing fromJson by hand, and forgets to `flutter pub run build_runner build`. CI passes because the test harness regenerates, but operator pages saved before the change fail to load — and the failure is silent (asset just disappears from the page) because `AssetRegistry.parse` swallows per-asset deserialization errors.

**Warning signs:**
- After pulling latest, opening an existing page shows fewer assets than before — silently dropped.
- `flutter analyze` or test runs locally pass but a teammate's machine fails because their `*.g.dart` is stale.
- A field added to `BeckhoffEL1008Config` last week is `null` even though the saved JSON contains a value (because the `fromJson` was hand-edited and the field was missed).
- The codegen log shows `Skipping: file already up to date` — but it isn't, because build_runner's freshness check is `mtime`-based, not content-based.

**Prevention:**
1. **Every new field on an existing config gets `@JsonKey(defaultValue: <sensible default>)`** or is nullable (`String?`). This is the v1.0 convention — keep it.
2. **Every new field on a NEW config (e.g. `DDI3725Config`)** can use required initializers, but the constructor must accept null/default for forward compat with future v2.1 additions.
3. **Add a JSON round-trip test per new module** (`test/page_creator/assets/modicon/ddi3725_json_test.dart`) that: (a) constructs a fully-populated config, (b) toJson, (c) fromJson the result, (d) asserts deep equality.
4. **Add a "legacy JSON" test** — paste a hand-written JSON snippet that omits future fields and assert it loads cleanly with sensible defaults.
5. **Pre-commit or CI gate: run `flutter pub run build_runner build --delete-conflicting-outputs` and assert no uncommitted `*.g.dart` changes.** This catches stale-codegen drift.
6. **Polymorphic child wrappers (per the v1.0 elevator's `ChildGateEntry` lesson):** if MomentumStack ever needs per-child metadata (e.g. a slot number or position-on-DIN-rail), wrap children in a `ModuleSlotEntry { String id, int slot, Asset module }` from DAY 1 — never retrofit. Mid-milestone schema changes to `subdevices: List<Asset>` will break v1.0 + early-v2.0 saved pages.

**Phase:** Every phase. Phase plans must include a JSON round-trip test as a "definition of done" checkbox. The MomentumStack composition phase owns the decision on whether children are bare `Asset` or wrapped `ModuleSlotEntry` — make the call once and stick to it.

---

### Pitfall M-07: Hit-testing through the stack — child module's GestureDetector doesn't fire when it's inside a `FittedBox`/`Row` MomentumStack composition

**What goes wrong:**
`feedback_gesture_through_translation.md` from v1.0 documents that gestures must survive parent translation. The Beckhoff CX5010 stack composes children inside a `FittedBox(fit: BoxFit.contain, child: Row(...))` (beckhoff.dart:64-91) and each subdevice is `_SubdeviceNormalized(child: sub.build(context), ...)`. `FittedBox` applies a scale transform — the painted glyph and the hit-test region BOTH scale together because `FittedBox` is a real layout widget (uses a `Transform.scale` under the hood, which DOES correctly propagate hit-tests).

The v2.0 MomentumStack will replicate this pattern. The risk: if the implementer reaches for an optimization like `Transform(transform: Matrix4.scale, child: ...)` WITHOUT `transformHitTests: true` (the default IS true, but readable code is one CustomPainter offset away from the wrong choice), or composes children via `CustomPaint(painter: ..., child: child)` with manual offsets, the hit-test region detaches from the painted region. Operator taps on the DDI3725 LED and the GestureDetector on the NIP fires instead. Subtler: at certain stack widths the FittedBox shrinks the modules below their gesture-detector minimums and taps land on the parent.

**Warning signs:**
- Tapping a module mid-stack opens the wrong module's dialog.
- Tapping a module at a non-default stack scale opens NO dialog (tap lands in the FittedBox's empty letterbox area).
- Manual test: shrink the page-creator viewport to half-size — module taps stop firing.

**Prevention:**
1. **Use `FittedBox` + `Row` (the existing pattern).** Do NOT introduce `Transform` or `CustomPaint(child: ...)` with manual offsets.
2. **Add a widget test per module** `test/page_creator/assets/modicon/<module>_tap_in_stack_test.dart` that wraps the module in a `MomentumStack`, scales the parent to 50% and 200%, and asserts a tap on the module fires its specific dialog (not the stack's, not a sibling's).
3. **Each module's tappable area uses `GestureDetector` with `HitTestBehavior.opaque`** — copy the EL1008 pattern at beckhoff.dart:1337. `opaque` ensures the tap doesn't fall through to siblings or the parent stack.
4. **No painter-only hit detection.** A `CustomPainter` does NOT participate in hit-testing — the `GestureDetector` MUST be a separate widget wrapping the `CustomPaint`.

**Phase:** Each module phase (DI, DO, NIP, PDT) owns its own gesture wiring. MomentumStack phase owns the composition test that scales the stack and asserts taps still land correctly.

---

## Moderate Pitfalls

### Pitfall M-08: `shouldRepaint` misses a new field — stale paint on force-mode change

**What goes wrong:**
`IO8Painter.shouldRepaint` (io8.dart:335-343) compares every field. If the v2.0 painter adds a field (e.g. `bitOrder` enum or per-channel description list) and the developer forgets to add it to `shouldRepaint`, the painter caches stale frames. The force-override animation flickers because the animation field IS in shouldRepaint but the new field's changes are ignored — the painter sees "nothing changed" for several frames, then a force change re-triggers and the new field's last-known value appears.

The opposite is worse: returning `true` unconditionally from `shouldRepaint` repaints every frame. Combined with the 32 streams per stack from Pitfall M-03, the GPU runs flat-out.

**Warning signs:**
- Per-channel descriptions changed in StateMan don't update on the painter until something else triggers a rebuild.
- DevTools "rebuild stats" or the rendering overlay shows the painter rebuilding 60 fps even when nothing visible changed.
- Memory grows monotonically (painter caches Picture objects per repaint).

**Prevention:**
1. **`shouldRepaint` is a covariant `==` check.** Add every painter field. If a field is a `List`, use `listEquals` (already imported via `flutter/foundation.dart` at io8.dart:2). If it's a custom struct, implement `==` on the struct first.
2. **Add a golden test that verifies repaint on each field change** — change one field at a time, re-render, and confirm the golden differs. A field that doesn't affect the golden when it should is a missing shouldRepaint clause OR a missing painter call.
3. **Lint check:** consider a custom `dart analyze` rule (or just a code-review checklist) — "every field in the painter's constructor must appear in `shouldRepaint` OR be marked `@immutable` and prove it doesn't affect paint."

**Phase:** Every painter phase.

---

### Pitfall M-09: 16-channel layout doesn't scale gracefully below ~80 px wide

**What goes wrong:**
`IO8Painter` lays out 8 LEDs in a 2×4 grid plus terminal blocks (io8.dart:432-452). At small sizes (height ~150 px) the LED rectangles are ~8 px each and the channel labels become unreadable but still legible. For 16 channels on the same footprint (107×152 mm physical), the grid is 2×8 — each LED is half the height. At 80 px wide × 160 px tall (small page-creator placement) the LEDs are 4×8 px and the channel labels degrade into a blob.

The user's photo confirms the physical layout: a vertical strip with two columns of terminal blocks running floor-to-ceiling, channels numbered down the left then down the right. The painter's column-major layout (channels 1-8 in left column, 9-16 in right column) matches the physical module. Row-major (channels 1, 9, 2, 10, ...) does NOT match the physical and will confuse operators during commissioning.

**Warning signs:**
- Operators say "the panel is unreadable when the page is shrunk for the overview."
- The painter draws "16" / "I16" as just a coloured block — text painter clips.
- Channel labels overlap with terminal block visuals at small sizes.
- Goldens at one size look fine; goldens at half size look like garbage.

**Prevention:**
1. **Column-major LED ordering per the photo.** Channels 1-8 in the left column top-to-bottom, channels 9-16 in the right column top-to-bottom. Match the physical terminal-block layout. Add a comment in the painter referencing the photo path.
2. **Two-tier rendering: above a size threshold (e.g. width >= 100 px), draw labels; below, draw the LED grid only without labels.** Operators at a small overview size only need to see whether anything is energised, not which channel. Copy the io8.dart `disconnected` icon-render pattern at lines 126-147 for the conditional rendering.
3. **Add goldens at three sizes** — full (e.g. 200×400), medium (100×200), small (60×120) — per module. A regression at any size fails CI.
4. **DXF proportions are guidance, not gospel.** The IO_BASE DXF gives 107×152 mm (`.planning/research/dxf/README.md`), so the painter aspect ratio is ~0.7:1. But the LED block within that should be proportionally LARGER than DXF if the LEDs need to be visible at small sizes. Document the deviation in the painter file.

**Phase:** DI module phase, DO module phase. The same painter file (or shared base painter) services both — the DXF mapping is `IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf` shared between DI and DO.

---

### Pitfall M-10: Hard-coded colours don't survive theme changes — Schneider cream looks like dirty grey on dark theme

**What goes wrong:**
The Beckhoff painter hard-codes `bodyColor = Color(0xFFF7F5E6)` (io8.dart:102) and `ioLabelColor = Color(0xFFC0C040)` (io8.dart:5). On dark theme the cream module body sits against a dark canvas and looks fine. The Schneider cream `~Color(0xFFE8E2D0)` (typical Schneider Electric Momentum chassis colour) is similar.

Hardcoding is correct for module-body recognition — operators recognize the colour. But the BORDER colours, terminal-block colours, and text colour DO need to respond to theme. EL1008's text is hardcoded black (`color: Colors.black` at io8.dart:165, 313) — on a light theme this is fine; on a dark theme overlaid against a dark page background OUTSIDE the module, the bottom labels "EL1008" / "BECKHOFF" become invisible because they're black-on-dark-canvas at the boundary.

The new Momentum module text "DDI3725" / "Schneider" has the same risk if cloned verbatim.

**Warning signs:**
- Operator switches to dark theme and "the labels disappeared on the new modules" — actually they're outside the cream body and now blend into the dark canvas.
- The module body's outer border is the same colour as the page background — module merges into the canvas.

**Prevention:**
1. **Module body colour is FIXED** — Schneider cream, Beckhoff cream. Operator recognition wins.
2. **Text INSIDE the cream body is FIXED black** — high contrast on cream, regardless of theme.
3. **Text OUTSIDE the cream body** (e.g. labels below the module) **uses `Theme.of(context).colorScheme.onSurface`** — passed into the painter as a parameter, NOT hardcoded.
4. **Outer border of the module uses `Theme.of(context).colorScheme.outline` or similar** so the module separates from the canvas in both themes.
5. **Add a "dark theme golden" pair for every module** — `<module>_light.png` and `<module>_dark.png`. Catches the theme-drift bug.

**Phase:** Each module's painter phase. The shared `lib/painter/modicon/io16.dart` should accept the on-surface colour as a constructor param.

---

### Pitfall M-11: Stack-composition golden fails on CI because of font rendering differences

**What goes wrong:**
EL1008's painter draws "1" through "8" + "EL1008" / "BECKHOFF" via `TextPainter` with `FontWeight.bold` and the platform default font (io8.dart:163-175). On a developer's macOS machine the SF Pro / Helvetica metrics produce one pixel layout; on the Linux CI container (typically running headless rendering via the test framework's Skia backend), font metrics differ by 1-2 pixels. Goldens generated on the dev machine fail on CI with `mismatchedPixels: ~80`.

Adding labels "1" through "16" for the Momentum module DOUBLES the surface area where this can fail.

**Warning signs:**
- CI shows golden failures with tiny pixel diffs concentrated around text glyphs.
- Re-running CI on the same commit sometimes passes, sometimes fails.
- `--update-goldens` locally produces a file that fails on CI.

**Prevention:**
1. **Goldens are generated on CI, not the dev machine.** Project convention should be: developer writes the test, sees it fail, generates a placeholder, pushes; CI runs `--update-goldens` and the developer pulls the canonical golden. (See `dart_test.yaml` — golden tests are skipped unless `--update-goldens`; verify the project's golden CI flow before assuming.)
2. **Pin a font family explicitly** — bundle a small fixed font (e.g. Roboto via pubspec assets) and use it in the TextPainter. Removes the platform-default-font variance.
3. **Set `textScaleFactor: 1.0` explicitly** in the painter's `TextPainter` setup and in the test wrapper widget. The default can drift with system accessibility settings.
4. **Use `matchesGoldenFile` with a fault tolerance** ONLY as a last resort — exact-match goldens are the strong signal.

**Phase:** Every painter phase that uses `TextPainter`. The DI module phase will hit this first; the fix (pinned font) carries over to DO + NIP + PDT.

---

### Pitfall M-12: Stack child filter — what happens if a non-Momentum asset ends up in `MomentumStack.subdevices`?

**What goes wrong:**
`BeckhoffCX5010Config.subdevices` is `List<Asset>` (beckhoff.dart:37-38), not `List<BeckhoffSubdeviceAsset>`. Any asset can be added — and the configure dialog filters via `_availableSubdevices` (beckhoff.dart:21-28) for the "add" button. But the JSON layer accepts whatever's there.

If an operator hand-edits page JSON to inject, say, a `SensorConfig` into a CX5010's subdevices, the build() at beckhoff.dart:81-86 calls `sub.build(context)` and wraps in `_SubdeviceNormalized` (height-normalized). The Sensor renders in the stack — wrong scale, weird placement, but no crash.

For MomentumStack the same vulnerability applies. The pitfall is twofold:

1. **Defensive vs strict — pick one and document it.** Strict: filter in `build()` to only the four Momentum types; render an error placeholder for anything else. Defensive: render anything but warn in a debug log.
2. **`allKeys` flattening on a foreign child** — if a `SensorConfig` is in the subdevices, its `detectionStateKey` etc. are included in the stack's `allKeys`. Alarms wire up correctly, but the operator's mental model says "this is a Momentum stack, why is there a sensor key here?" — confusing during alarm investigation.

**Warning signs:**
- The Add Subdevice dropdown only lists Momentum modules, but a saved page contains a non-Momentum subdevice (set in a previous editor version or hand-edited).
- A non-Momentum child renders at the wrong scale because `_SubdeviceNormalized` normalizes to the head's height.

**Prevention:**
1. **Decision (recommended): permissive render, restrictive add.** Mirror CX5010's behavior — the "add" dropdown only offers Momentum types, but build() renders whatever's in the list. Reduces brittleness when an operator restores a page from an older format.
2. **In `MomentumStack.build()`, wrap each child in a try/catch and render a "unknown subdevice" placeholder on exception.** Prevents one bad child from killing the whole stack.
3. **Add a unit test** that constructs a MomentumStack with a foreign child (e.g. SensorConfig) and asserts it round-trips through JSON cleanly AND renders without crashing.

**Phase:** MomentumStack composition phase.

---

## Minor Pitfalls

### Pitfall M-13: ValueKey on stack children — required for stable identity

**What goes wrong:**
The CX5010 ReorderableListView in the dialog uses `ObjectKey(sub)` (beckhoff.dart:255). This works because subdevice instances are stable across the dialog's lifetime. If MomentumStack ever supports drag-reorder of modules on the canvas (not in the dialog), child identity loss during reorder will reset `AnimatedWidget` animations (the IOForcedHigh red-border animation will restart on every reorder).

**Prevention:**
- Use `ValueKey<String>` keyed on a stable UUID per subdevice (echoing the v1.0 `ElevatorChildEntry` lesson). Add `String id;` to `MomentumModuleSlotEntry` from day 1 OR generate one lazily from `sub.hashCode`.

**Phase:** MomentumStack composition phase, only if reorder UX is added — otherwise defer.

---

### Pitfall M-14: AnimationController and stream subscription leaks across 4+ new widget classes

**What goes wrong:**
EL1008 uses `AlwaysStoppedAnimation(0)` (beckhoff.dart:1305) as a static animation — no controller to leak. The new Momentum modules will need an active `AnimationController` for the forced-LED red-border pulse (matching io8.dart:408-411). That's one per module instance per page.

Failure mode: `AnimationController` created in `initState` of a `StatefulWidget` and not disposed in `dispose()`. Symptom: hot-reload spams "AnimationController disposed by GC" warnings; over a long session memory and ticker count grow.

**Prevention:**
- `with SingleTickerProviderStateMixin` on the State; `_controller = AnimationController(...)` in initState; `_controller.dispose()` in dispose. Standard pattern, not Momentum-specific.
- Add a leak-tracking test using `flutter_test`'s `tester.binding.dispatchEnabled` and `LeakTracker` (Flutter 3.16+) for the new module widgets.

**Phase:** Each module phase.

---

### Pitfall M-15: PostgreSQL collector explosion on a 4-module stack — 16 + 16 = 32 channels × poll rate

**What goes wrong:**
Once `allKeys` is wired correctly (per Pitfall M-01), the `Collector` will subscribe to every key the stack exposes. A populated stack: 1 head sync key + 16 DI raw + 16 DO raw + force/filter keys = potentially 100+ keys per stack. Collecting them all into TimescaleDB at default rates floods the hypertable.

**Prevention:**
- The collector configuration is OUT OF SCOPE for v2.0 (PROJECT.md confirms: "Backend Modbus key plumbing — assumes StateMan keys already exist"). But the milestone owner should call out to the backend team that 100+ new keys per stack will be exposed, so they can dial the collector rates appropriately.
- Document this in `.planning/research/SUMMARY.md` as an "operational note for backend team."

**Phase:** MomentumStack composition phase — surface it in the phase plan's "downstream impacts" section.

---

### Pitfall M-16: Modbus polling cadence vs operator perception — a 100 ms LED flash at the PLC may not surface

**What goes wrong:**
StateMan's Modbus client polls at a backend-configured cadence (commonly 100-500 ms per device). A sensor wired to DDI3725 channel 3 that pulses for 50 ms may NEVER appear in the HMI — the poll cycle misses it. For commissioning, this is misleading: the operator says "the sensor isn't working" when the input IS being received by the PLC.

**Prevention:**
- Surface a small "last updated" timestamp on the per-channel detail dialog (the EL1008 dialog doesn't have one — copy the pattern from `lib/widgets/...` if one exists, or add it as a new feature).
- Document the poll cadence in a tooltip on the configure dialog: "Channel state polled every ~200 ms from PLC. Sub-100ms pulses may not be visible."
- OUT OF SCOPE to fix the cadence — but the asset must not LIE about pulse fidelity. Documenting it on the asset surface is the minimum.

**Phase:** DI module phase (DDI3725 — the only place this surfaces; DO outputs don't have an external pulse-source so the operator's mental model is different).

---

## Phase-Specific Warnings Summary

| Phase | Top three pitfalls to bake in | Mitigation in plan |
|-------|------------------------------|--------------------|
| NIP2311 head module | M-05 (status LEDs not addressable), M-07 (gesture in stack), M-10 (theme colours) | Configure dialog spec must explicitly limit to one synthetic comm-OK key; widget test for tap-in-stack at multiple scales; theme golden pairs. |
| PDT3100 power module | M-07 (gesture in stack), M-10 (theme), M-08 (shouldRepaint) | Same tap-in-stack widget test; light + dark goldens; if it has a `power_ok` bool, painter must include in shouldRepaint. |
| DDI3725 (16-ch DI) | M-02 (bit mapping), M-03 (subscription storm), M-04 (force vs raw), M-09 (small-size legibility), M-16 (poll cadence) | Bit-mapping unit test before painter is implemented; single combined-stream subscription; 4-state-per-channel data model; goldens at three sizes; cadence note in dialog. |
| DDO3705 (16-ch DO) | M-02 (must match DI convention), M-03 (subscription storm), M-09 (small-size legibility) | Reuse DI's bit-mapping constant verbatim; same combined-stream pattern. |
| MomentumStack composition | M-01 (allKeys flattening), M-06 (JSON schema), M-12 (foreign child), M-15 (collector load) | allKeys integration test; JSON round-trip + legacy-JSON test; permissive-render-restrictive-add convention; documented downstream impact. |
| Asset Registry registration | M-06 (codegen drift) | CI gate that fails on uncommitted *.g.dart; round-trip test per new config. |

---

## Sources

- **Authoritative (HIGH confidence — current codebase):**
  - `/Users/jonb/Projects/tfc-hmi2/lib/page_creator/assets/beckhoff.dart` — pattern source of truth for stack, EL1008, EL2008, EL3054, and the `_combinedStream` + `_ledStates` helpers
  - `/Users/jonb/Projects/tfc-hmi2/lib/painter/beckhoff/io8.dart` — painter pattern + `shouldRepaint` reference
  - `/Users/jonb/Projects/tfc-hmi2/lib/page_creator/assets/common.dart` — `BaseAsset.allKeys` regex (lines 217-243) and `BaseAsset` contract
  - `/Users/jonb/Projects/tfc-hmi2/lib/page_creator/assets/conveyor.dart` — `_gatesFromJson` legacy shim (lines 26-48) as prior art for backwards-compat
  - `/Users/jonb/Projects/tfc-hmi2/.planning/research/dxf/README.md` — DXF bounding boxes and DI/DO base sharing
  - `/Users/jonb/Projects/tfc-hmi2/.planning/PROJECT.md` — v2.0 scope and out-of-scope decisions
  - `/Users/jonb/.claude/image-cache/fe2be5fa-6578-40a7-bc7b-7475838556e9/3.png` — user-provided photo confirming the physical Momentum module layout (vertical strip with two columns of terminals)
  - `.claude/...feedback_gesture_through_translation.md` — v1.0 lesson about hit-test through translation
  - v1.0 elevator phase context (Pitfalls 1, 5, 7) — `.planning/milestones/v1.0/03-elevator-child-embedding/03-CONTEXT.md`
- **Schneider Momentum docs (MEDIUM confidence — referenced but not exhaustively cross-checked against the DDI3725 datasheet at this session):**
  - [Modicon Momentum I/O Base User Guide (31001697.22)](https://iportal2.schneider-electric.com/Contents/docs/MODICON%20MOMENTUM%20_IO_%20BASE%20USER%20GUIDE.PDF)
  - [Momentum 170ENT11001/170ENT11002 Ethernet Communications Adapter](https://igate.alamedaelectric.com/Modicon%20Documents/PLC%20Momentum%20PLC%20Ethernet%20(ENT)%20Adapter%20User%20Guide%20v2.0.pdf) (NIP family adapter manual — the newer NIP2311 follows the same conventions)
  - [STBDDI3725 product page (Schneider Electric)](https://www.se.com/us/en/product/STBDDI3725/basic-digital-input-module-modicon-stb-24v-dc-16i/)
  - [Modicon TSX Momentum Modbus to Ethernet Bridge User Guide 890 USE 155 00](https://igate.alamedaelectric.com/Modicon%20Documents/PLC%20Modbus%20Ethernet%20Bridge%20(CEV30010)%20User%20Manual.pdf)
