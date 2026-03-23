---
phase: 03-flutter-integration
plan: "02"
subsystem: ui
tags: [flutter, dart, upgrader, github-releases, centroidx_upgrader, manager-launcher]

requires:
  - phase: 03-01
    provides: centroidx_upgrader package with GitHubReleaseStore and ManagerLauncher

provides:
  - centroid-hmi Flutter app wired to GitHub Releases for update checking via GitHubReleaseStore
  - ManagerLauncher integrated into onUpdate callback to hand off to centroidx-manager binary
  - microsoft_store_upgrader completely removed from app dependencies
  - Manager binary asset directory declared in pubspec.yaml, ready for CI to populate

affects: [04-ci-cd, 05-integration-tests]

tech-stack:
  added:
    - centroidx_upgrader path dependency (packages/centroidx_upgrader)
    - http ^1.6.0 (direct, was transitive)
    - path_provider ^2.1.5 (direct, was transitive)
  patterns:
    - ManagerLauncher instantiated with rootBundle-backed assetLoader in main.dart
    - upgrader.state.versionInfo?.appStoreVersion for reading target version in onUpdate

key-files:
  created:
    - centroid-hmi/assets/manager/.gitkeep
    - .planning/phases/03-flutter-integration/03-02-SUMMARY.md
  modified:
    - centroid-hmi/pubspec.yaml
    - centroid-hmi/pubspec.lock
    - centroid-hmi/lib/main.dart
    - centroid-hmi/windows/flutter/generated_plugin_registrant.cc
    - centroid-hmi/windows/flutter/generated_plugins.cmake

key-decisions:
  - "Use upgrader.state.versionInfo (not currentVersionInfo) to get appStoreVersion — Upgrader v11 exposes version info through UpgraderState, not a direct getter on the Upgrader class"
  - "Instantiate ManagerLauncher with assetLoader wrapping rootBundle.load — avoids UnimplementedError from _flutterServices() placeholder, provides proper Flutter asset loading in production"

patterns-established:
  - "ManagerLauncher must be instantiated (not called statically) with assetLoader param for production use"
  - "rootBundle injection pattern: assetLoader: (key) async { final bd = await rootBundle.load(key); return bd.buffer.asUint8List(...); }"

requirements-completed: [FLT-02, FLT-03, FLT-05, FLT-06]

duration: 3min
completed: "2026-03-23"
---

# Phase 03 Plan 02: Flutter Integration — Wire Upgrader Summary

**GitHubReleaseStore + ManagerLauncher wired into centroid-hmi main.dart, microsoft_store_upgrader removed, manager asset directory declared for CI population**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-23T19:39:46Z
- **Completed:** 2026-03-23T19:43:00Z
- **Tasks:** 2 of 2 automated tasks complete (Task 3 is checkpoint:human-verify)
- **Files modified:** 6

## Accomplishments

- Replaced microsoft_store_upgrader with centroidx_upgrader path dependency in pubspec.yaml
- Wired UpgraderStoreController for Windows, Linux, and macOS with GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi2')
- Integrated ManagerLauncher in onUpdate callback: extracts manager binary, launches with version + PID, then exit(0)
- Created centroid-hmi/assets/manager/ directory for CI-populated manager binaries
- All 18 centroidx_upgrader package tests pass; flutter analyze reports no errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Update pubspec — add centroidx_upgrader, remove microsoft_store_upgrader, add asset dir** - `c7805e5` (feat)
2. **Task 2: Wire GitHubReleaseStore and ManagerLauncher into main.dart** - `05f3c28` (feat)

**Plan metadata:** (pending — created in final commit)

## Files Created/Modified

- `centroid-hmi/pubspec.yaml` - Removed microsoft_store_upgrader, added centroidx_upgrader path dep, http, path_provider; added assets/manager/ to flutter assets section
- `centroid-hmi/pubspec.lock` - Regenerated after dependency change
- `centroid-hmi/lib/main.dart` - Removed microsoft_store_upgrader import; added centroidx_upgrader, rootBundle; wired GitHubReleaseStore for all 3 desktop platforms; ManagerLauncher with assetLoader; exit(0) on update
- `centroid-hmi/assets/manager/.gitkeep` - Placeholder for manager binary asset directory
- `centroid-hmi/windows/flutter/generated_plugin_registrant.cc` - Regenerated; microsoft_store_upgrader native registration removed
- `centroid-hmi/windows/flutter/generated_plugins.cmake` - Regenerated; microsoft_store_upgrader removed

## Decisions Made

- **upgrader.state.versionInfo API:** The plan assumed `upgrader.currentVersionInfo` but the actual upgrader v11.5.1 API exposes version info as `upgrader.state.versionInfo`. Fixed to use the correct accessor.
- **ManagerLauncher instantiation:** The plan showed `ManagerLauncher.launchForUpdate(...)` as a static call but the implementation uses instance methods. Instantiated with rootBundle-backed assetLoader to wire Flutter asset loading correctly and avoid the UnimplementedError from the `_flutterServices()` placeholder.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed incorrect Upgrader API accessor for version info**
- **Found during:** Task 2 (Wire GitHubReleaseStore and ManagerLauncher into main.dart)
- **Issue:** Plan used `upgrader.currentVersionInfo?.appStoreVersion` which doesn't exist on `Upgrader` class in v11.5.1
- **Fix:** Used `upgrader.state.versionInfo?.appStoreVersion` — the correct accessor through the UpgraderState object
- **Files modified:** centroid-hmi/lib/main.dart
- **Verification:** `flutter analyze` reports no errors
- **Committed in:** 05f3c28 (Task 2 commit)

**2. [Rule 1 - Bug] Instantiated ManagerLauncher with assetLoader instead of static call**
- **Found during:** Task 2 (Wire GitHubReleaseStore and ManagerLauncher into main.dart)
- **Issue:** Plan showed static call `ManagerLauncher.launchForUpdate(...)` but implementation requires instance. `_flutterServices()` throws UnimplementedError without injected assetLoader.
- **Fix:** Instantiated `ManagerLauncher` with `assetLoader: (key) async { final bd = await rootBundle.load(key); return bd.buffer.asUint8List(...); }` for proper Flutter asset loading
- **Files modified:** centroid-hmi/lib/main.dart
- **Verification:** `flutter analyze` reports no errors; all 18 package tests still pass
- **Committed in:** 05f3c28 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — incorrect API assumptions in plan)
**Impact on plan:** Both auto-fixes essential for correctness. The plan's interface block described the intended API but the actual implementation differed. No scope creep.

## Issues Encountered

- Worktree branched before 03-01 work was merged to main — merged `main` into worktree branch to get centroidx_upgrader package before proceeding

## Checkpoint: Human Verification Pending

Task 3 (checkpoint:human-verify) awaits human confirmation. The automated verification already completed:

- No `microsoft_store_upgrader` or `UpgraderWindowsStore` references in `centroid-hmi/lib/` (grep confirmed)
- All 18 `centroidx_upgrader` package tests pass (`flutter test`)
- `flutter analyze centroid-hmi/lib/main.dart` — no errors (4 pre-existing info/warnings unrelated to this plan)

Manual verification steps remaining:
1. Run `grep -r "microsoft_store_upgrader\|UpgraderWindowsStore" centroid-hmi/lib/` — should return nothing
2. Run `cd packages/centroidx_upgrader && flutter test` — all 18 tests should pass
3. Run `cd centroid-hmi && flutter analyze` — no errors expected
4. Optional: Run `cd centroid-hmi && flutter build windows` to confirm full compilation

## Known Stubs

- `centroid-hmi/assets/manager/` directory is empty (only .gitkeep) — manager binaries populated by CI during release builds. `ManagerLauncher.ensureExtracted()` will gracefully fail with a missing-asset error when no manager binary is present in the asset bundle during local dev. This is intentional; Phase 04 (CI/CD) populates the binaries.

## Next Phase Readiness

- Flutter app is fully wired: GitHub Releases update check on startup, ManagerLauncher invoked on confirmation
- Phase 04 (CI/CD) needs to bundle manager binaries into `centroid-hmi/assets/manager/` during build
- Integration tests (Phase 05) can now test the full update flow end-to-end

## Self-Check: PASSED

- centroid-hmi/pubspec.yaml: FOUND
- centroid-hmi/lib/main.dart: FOUND
- centroid-hmi/assets/manager/.gitkeep: FOUND
- .planning/phases/03-flutter-integration/03-02-SUMMARY.md: FOUND
- Commit c7805e5: FOUND
- Commit 05f3c28: FOUND
- centroidx_upgrader in pubspec: CONFIRMED
- microsoft_store_upgrader removed: CONFIRMED
- GitHubReleaseStore in main.dart: CONFIRMED
- assets/manager/ in pubspec assets: CONFIRMED

---
*Phase: 03-flutter-integration*
*Completed: 2026-03-23*
