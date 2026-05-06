# Stack Research

**Domain:** Industrial HMI custom assets (Flutter) — animated child translation + custom-painted sensor glyphs
**Researched:** 2026-05-05
**Confidence:** HIGH

## TL;DR

**Add nothing.** The existing stack (Flutter 3.41 / Dart 3.11, Riverpod, RxDart, `build_runner` + `json_serializable`, `CustomPainter`, raw `AnimationController` + `Curves`) already covers every requirement of the elevator and sensor milestone. The dominant pattern in `lib/page_creator/assets/` — `ConsumerStatefulWidget` + `SingleTickerProviderStateMixin` + `AnimationController` + `ValueNotifier<double>` passed to a `CustomPainter`'s `repaint` argument — is the right tool for both new assets. No new pub.dev packages, no codegen tools beyond what's already wired.

The only nuance: the elevator's input is a *continuous* PLC value (0–100%) rather than the conveyor gate's *binary* open/close trigger, which means swapping `controller.forward()/reverse()` for `controller.animateTo(target)` (or `TweenAnimationBuilder`). Same SDK, slightly different call.

## Recommended Stack

### Core Technologies (already in the codebase — reuse)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Flutter SDK | 3.41.9 stable | UI framework | Already on stable; ships every primitive needed |
| Dart | 3.11.5 | Language | Current with codebase |
| `flutter_riverpod` | ^2.6.1 | State / DI | Already wired; `stateManProvider` is how every asset gets PLC data |
| `rxdart` | ^0.28.0 | Stream combinators | Existing assets use it for `combineLatest2` over StateMan + sub streams |
| `json_serializable` | ^6.9.4 | Config (de)serialisation | Mandatory — `BaseAsset` subclasses round-trip via `*.g.dart` |
| `build_runner` | ^2.4.15 | Codegen runner | Required for any new `*Config` class |
| `flutter/animation` (SDK) | — | `AnimationController`, `Tween`, `Curves` | The codebase's established animation idiom (see `conveyor_gate.dart:197-211`) |
| `flutter/rendering` (SDK) | — | `CustomPainter`, `Canvas`, `Path` | Every asset glyph is a `CustomPainter`; sensor glyphs follow suit |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter/widgets` SDK — `TweenAnimationBuilder` | — | Implicit animation toward a changing target | **Recommended for the elevator's 0–100% chase**. Smoothly retargets when PLC value changes mid-animation; no manual `AnimationController` needed (HIGH confidence — verified against [TweenAnimationBuilder API docs](https://api.flutter.dev/flutter/widgets/TweenAnimationBuilder-class.html)) |
| `flutter/animation` SDK — `AnimationController.animateTo(target)` | — | Explicit alternative to `TweenAnimationBuilder` | Use when you need access to status callbacks, custom velocities, or to share one controller across multiple painters. Equivalent control, more boilerplate. |
| `flutter/widgets` SDK — `Positioned` + `LayoutBuilder` | — | Pin children to platform Y position | The elevator's children are positioned inside the elevator's bounding box; `Positioned(top: progress * height)` is the simplest mapping |
| `flutter/widgets` SDK — `Stack` | — | Compose the shaft + platform + child assets | Already the pattern for `AssetStack` (`lib/pages/page_view.dart`) and conveyor gate embedding |
| `flutter/widgets` SDK — `RepaintBoundary` | — | Isolate painter repaints from sibling assets | Wrap the elevator's animated layer so 60 fps repaints don't dirty the rest of the page |

### Development Tools (already in use)

| Tool | Purpose | Notes |
|------|---------|-------|
| `build_runner watch` | Regenerate `*.g.dart` on save | Already documented; standard `dart run build_runner watch --delete-conflicting-outputs` |
| `flutter_test` (SDK) | Widget + golden tests | Codebase already skips goldens unless `--update-goldens` (`dart_test.yaml`) — sensor glyphs are good golden-test candidates |
| `flutter_lints` ^5.0.0 | Lint baseline | No change |

## Installation

**Nothing to install.** All capabilities are present in the current `centroid-hmi/pubspec.yaml`. New asset files just import:

```dart
import 'package:flutter/material.dart';        // AnimationController, Curves, Tween, TweenAnimationBuilder
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/providers/state_man.dart'; // stateManProvider
```

Run `dart run build_runner build --delete-conflicting-outputs` after adding new `@JsonSerializable()` configs.

## Pattern Recommendations (the actual decisions)

### Elevator — vertical translation of children driven by 0–100% PLC value

**Recommended: `TweenAnimationBuilder<double>` wrapping `Stack` of `Positioned` children.**

```dart
StreamBuilder<DynamicValue>(
  stream: stateMan.subscribe(config.positionKey).asStream().switchMap((s) => s),
  builder: (_, snap) {
    final target = ((snap.data?.toDouble() ?? 0) / 100).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),  // begin overwritten by builder's previous value
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, t, _) => Stack(children: [
        // shaft painter
        Positioned(
          top: (1 - t) * (shaftHeight - platformHeight),
          child: PlatformWithChildren(...),
        ),
      ]),
    );
  },
);
```

**Why TweenAnimationBuilder over the conveyor gate's manual controller:**
- The gate has a *binary* signal (open/closed) → `forward/reverse` is natural.
- The elevator has a *continuous* signal that may change mid-flight → retargeting needs `animateTo`. `TweenAnimationBuilder` gives that for free, including smooth continuation from the current value to the new target ([Flutter docs confirm: "The new animation runs from the current animation value to Tween.end of the new tween"](https://api.flutter.dev/flutter/widgets/TweenAnimationBuilder-class.html)).
- One less `AnimationController` to dispose; less ceremony.

**Curve:** `Curves.linear` matches a real elevator more faithfully (constant speed) — but `Curves.easeOut` is what the gate uses and is fine here too. Tunable as a config knob if needed; default `linear` suggested for the elevator since the PLC owns the motion profile and the HMI shouldn't double-curve it.

**Tick frequency:** 250 ms is a starting suggestion. Tune to the PLC update rate observed at `stateMan.subscribe(...)`. If updates arrive every 100 ms and the duration is 250 ms, the platform will perpetually be chasing — that's actually the desired behaviour and reads as smooth motion.

### Sensor glyphs — three custom painters, one widget, one bool input

**Recommended: a single `Sensor` `ConsumerStatefulWidget` that selects one of three `CustomPainter`s by `SensorKind` enum, with `ValueNotifier<bool>` (or `ValueNotifier<Color>`) passed as `repaint`.**

This is *exactly* the pattern in `conveyor_gate.dart:240-266` (`_createPainter(stateColor)` switching on `GateVariant`). No animation needed — the requirement is "visual flips immediately" — so a `StreamBuilder<bool>` rebuild is sufficient. No `AnimationController`.

```dart
class SensorPainter extends CustomPainter {
  SensorPainter({required this.detected, required this.kind, required this.color})
    : super(repaint: detected);                     // ValueListenable<bool>
  final ValueListenable<bool> detected;
  final SensorKind kind;
  final Color color;
  @override void paint(Canvas c, Size s) { /* switch on kind, draw beam/optic-cone/induction-loop */ }
  @override bool shouldRepaint(covariant SensorPainter old) =>
      old.kind != kind || old.color != color;       // detected drives repaints via the Listenable
}
```

**Glyph references** (build from primitives — no asset packs needed):
- **Red light beam (paired):** two filled rounded rectangles (sender + receiver) on either side of the bounding box, connected by a thin dashed/solid line; line color = `Colors.red` when active, faded grey when inactive.
- **Optic field:** sender housing + a fan / cone of arcs emanating outward (`Path.arcTo`); fill cone with semi-transparent red when active.
- **Inductive field:** rectangular sensor housing with concentric arcs in front of the face simulating the induction field; arcs animate to active color.

Use the existing painter conventions documented in PITFALLS-style notes: proportional radii from `size.shortestSide`, no hard-coded pixel values, `RenderBox` math via `size`.

### Child positioning inside the elevator

**Recommended: explicit dropdown assignment + `Stack` layout** — exactly as PROJECT.md decided. Each assigned child is rendered as a `Positioned` widget inside the elevator's `Stack`, with the elevator's animated `t` translating its `top` offset.

This mirrors `conveyor.dart:870-900`'s `ChildGateEntry` pattern:
- Wrap the child's `BaseAsset.build()` in a `SizedBox` sized to the child's own dimensions.
- `Positioned(left: childOffsetX, top: (1 - t) * shaftRange + childOffsetY, ...)` inside the elevator's Stack.
- The child's own state-key subscription is unaffected — it still renders live PLC data while riding the platform.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `TweenAnimationBuilder` for elevator | Manual `AnimationController` + `ValueNotifier<double>` (gate pattern) | If you need fine-grained status callbacks (`AnimationStatus.completed`), shared controllers across multiple painters, or to drive the painter's `repaint` directly without a builder rebuild. Trade-off: more boilerplate, an extra `dispose()`. |
| `TweenAnimationBuilder` | `AnimatedPositioned` | `AnimatedPositioned` only animates within a `Stack`, can't curve the whole elevator's painter, and rebuilds the whole subtree on every tick. Worse perf when children are complex. |
| `TweenAnimationBuilder` | `flutter_animate` package | Adds a dependency for syntactic sugar (`.fadeIn().slideY()`). Targeted at one-shot UI animations, not continuous PLC chase. Skip. |
| Single `Sensor` widget with `SensorKind` enum | Three separate asset types in the registry | Already explicitly out of scope per PROJECT.md decision matrix. |
| `StreamBuilder<bool>` for sensor visual | `AnimationController` for sensor visual | The requirement says "flips immediately." No animation needed. Adding one inflates state and visual lag for no operator benefit. |
| `CustomPainter` for sensor glyphs | SVG asset files (`flutter_svg`) | SVGs would force per-state colour swapping by string-rewriting or layered images. CustomPainter colours are a Paint argument away. The codebase has zero SVG dependency today; introducing one for three glyphs isn't justified. |
| `CustomPainter` for sensor glyphs | Icon font (`font_awesome_flutter` is already in stack) | No FontAwesome icon represents a paired through-beam sensor or an inductive proximity field correctly. Industrial sensor symbology is too domain-specific for generic icon packs. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `AnimatedPositioned` | Rebuilds full subtree on every tick; no curve control beyond what the parent provides; forces a `Stack` layout even when not desired | `TweenAnimationBuilder<double>` driving `Positioned(top: t * range)` manually |
| `flutter_animate` package | Adds dependency for sugar over primitives the codebase already uses; oriented to ephemeral UI delight, not continuous control loop | Built-in `TweenAnimationBuilder` / `AnimationController` |
| `simple_animations` package | Older, mostly-replaced abstraction over the same SDK primitives; one more thing to maintain | SDK primitives directly |
| `rive` / `lottie` | Designer-driven animation runtimes; massive overkill and a binary-asset workflow the team doesn't have | `CustomPainter` (matches every other asset) |
| `flutter_svg` for sensor glyphs | Adds a dependency, complicates state-driven recolouring, asset-pipeline overhead | `CustomPainter` with `Paint()..color = stateColor` |
| Computing animation in `paint()` (e.g. `DateTime.now()`-driven) | Bypasses Flutter's vsync; tears across frames; can't be golden-tested deterministically | `AnimationController` / `TweenAnimationBuilder` driving the painter via `ValueListenable` |
| Triggering `setState` on every PLC value | Rebuilds the whole subtree on every tick of a 100 ms PLC; pages with 50+ assets stutter | Use `ValueNotifier<double>` passed to `CustomPainter`'s `repaint:` argument — bypasses build/layout, repaint only ([Flutter rendering docs confirm](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)) |
| Re-creating `Paint` / `Path` objects inside `paint()` | Allocations every frame → GC pressure → jank | Cache as painter fields; recreate only when colour/size config changes |
| Putting the elevator's children outside the elevator's `Stack` (e.g., absolute on `AssetStack`) and computing positions via global keys | Coupling that breaks page resizing; brittle hit-testing | Children live inside the elevator's local `Stack`; positions are local to the elevator's bounding box |

## Stack Patterns by Variant

**If the PLC drives the elevator at >5 Hz and the platform must look perfectly smooth:**
- Use `TweenAnimationBuilder` with `duration` ≈ 1.5× the observed PLC update interval and `Curves.linear`.
- The animation will perpetually be chasing the latest target; this reads as silky continuous motion rather than stepwise jumps.

**If the PLC reports position only on movement-end (indexed mechanism, e.g. servo with discrete floors):**
- Same `TweenAnimationBuilder` setup but use `Curves.easeInOut` and a longer duration (500–800 ms) so the visual ride doesn't snap.
- Optional: add a `velocity` config field later if operators report it feels off.

**If a sensor's `bool` stream is noisy (chattering at PLC level):**
- **Don't** debounce in the HMI (PROJECT.md: "PLC owns debouncing"). Surface the chatter visually so operators report it.

**If a future milestone adds horizontal motion:**
- The same `TweenAnimationBuilder<double>` pattern generalises to a `TweenAnimationBuilder<Offset>` — `Offset.lerp` is built in. No restructuring needed.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Flutter 3.41 | Riverpod 2.6, RxDart 0.28, json_serializable 6.9 | All are the existing pinned versions; no upgrades needed for this milestone |
| `TweenAnimationBuilder` | Flutter ≥ 1.10 | Has been stable since 2019; no version risk |
| `CustomPainter(repaint: Listenable)` | All current Flutter versions | Standard pattern |

## Confidence Assessment

| Recommendation | Confidence | Basis |
|---|---|---|
| Reuse existing animation primitives (no new packages) | **HIGH** | Direct inspection of `conveyor_gate.dart:181-266` shows the established pattern; PROJECT.md constraint says "no new frameworks" |
| `TweenAnimationBuilder` for continuous-target elevator | **HIGH** | Verified against [Flutter API docs](https://api.flutter.dev/flutter/widgets/TweenAnimationBuilder-class.html); explicitly designed for changing-target scenarios |
| `CustomPainter` with `repaint: ValueListenable` for sensor glyphs | **HIGH** | Verified against [Flutter rendering docs](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html); already the codebase idiom |
| No published pub.dev industrial-HMI sensor symbol package worth adopting | **HIGH** | pub.dev search returns 0 packages; only `hmi_widgets` exists as an obscure GitHub repo with a single maintainer |
| Suggested 250 ms ease-out / linear curve choice | **MEDIUM** | Reasonable default extrapolated from gate's pattern; final tuning belongs to integration phase with real PLC data |

## Sources

- [Flutter API: TweenAnimationBuilder](https://api.flutter.dev/flutter/widgets/TweenAnimationBuilder-class.html) — verified retargeting behaviour and that mid-animation target changes interpolate smoothly (HIGH)
- [Flutter API: CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) — verified `repaint: Listenable` pattern bypasses build/layout for paint-only updates (HIGH)
- [Flutter API: AnimationController](https://api.flutter.dev/flutter/animation/AnimationController-class.html) — verified `animateTo(target)` performs linear interpolation from current to new value (HIGH)
- [Flutter docs: Animations overview](https://docs.flutter.dev/ui/animations/overview) — general framework grounding (HIGH)
- pub.dev search `flutter+industrial+hmi` — 0 published packages; confirms no off-the-shelf option exists (HIGH)
- Codebase: `/Users/jonb/Projects/tfc-hmi2/lib/page_creator/assets/conveyor_gate.dart` lines 181-266 — established `AnimationController` + `ValueNotifier` + `CustomPainter` pattern (HIGH)
- Codebase: `/Users/jonb/Projects/tfc-hmi2/lib/page_creator/assets/conveyor.dart` lines 860-900 — established `ChildGateEntry` + `Positioned` child-embedding pattern (HIGH)
- Codebase: `/Users/jonb/Projects/tfc-hmi2/centroid-hmi/pubspec.yaml` — confirmed no animation packages currently in use (HIGH)
- Local: `flutter --version` → 3.41.9 stable, Dart 3.11.5 (HIGH)

---
*Stack research for: industrial HMI custom assets — elevator + sensor*
*Researched: 2026-05-05*
