---
phase: 04-version-management
plan: 02
subsystem: flutter-ui
tags: [flutter, dart, tdd, version-management, manager-launcher, beamer]
dependency_graph:
  requires:
    - "03-flutter-integration-03-01: ManagerLauncher class with injection pattern"
    - "03-flutter-integration-03-02: centroidx_upgrader wired into centroid-hmi/main.dart"
  provides:
    - "launchForPicker() method on ManagerLauncher for version picker launch"
    - "VersionManagerPage widget: thin launcher delegating to Go manager UI"
    - "Advanced Settings -> Version Manager menu entry with /advanced/version-manager route"
  affects:
    - "04-version-management-04-01: Go manager --picker flag must be handled by the picker UI"
tech_stack:
  added: []
  patterns:
    - "Module-level ManagerLauncher instance (matches dbusCompleter pattern) — accessible from route closures without parameter threading"
    - "StatefulWidget initState launch pattern: fire-and-forget launchForPicker(), show PID or error in state"
    - "TDD RED/GREEN cycle: 5 failing compile-error tests -> 20-line implementation -> all pass"
key_files:
  created:
    - packages/centroidx_upgrader/lib/src/manager_launcher.dart (launchForPicker method added)
    - centroid-hmi/lib/pages/version_manager_page.dart
  modified:
    - packages/centroidx_upgrader/test/manager_launcher_test.dart (5 new tests appended)
    - centroid-hmi/lib/main.dart (managerLauncher promoted to module level, Version Manager menu item and route added)
decisions:
  - "managerLauncher promoted to module level: avoids threading it as a parameter through createLocationBuilder, matching the existing dbusCompleter pattern"
  - "VersionManagerPage is a thin launcher — no version list UI in Flutter; all version management UI lives in the Go Fyne picker window"
  - "ProcessStartMode.normal for launchForPicker: picker window is interactive and stays open alongside Flutter app (unlike launchForUpdate which uses detached mode)"
metrics:
  duration_seconds: 152
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_created: 2
  files_modified: 2
---

# Phase 04 Plan 02: Version Manager Flutter Integration Summary

**One-liner:** launchForPicker() method on ManagerLauncher (TDD, --picker flag, ProcessStartMode.normal) wired to Advanced Settings Version Manager menu entry via Beamer route.

## What Was Built

### Task 1: TDD launchForPicker on ManagerLauncher

Applied TDD discipline:

**RED:** Added 5 test functions inside the existing `group('ManagerLauncher', ...)` block in `manager_launcher_test.dart`. Tests covered:
- `launchForPicker passes --picker flag` — asserts `args == ['--picker']`, excludes --update/--version/--wait-pid
- `launchForPicker uses ProcessStartMode.normal` — captures mode, asserts `normal` not `detached`
- `launchForPicker returns spawned process PID` — injects `_FakeProcess(5678)`, asserts return is 5678
- `launchForPicker calls ensureExtracted` — uses non-existent path, asserts assetLoader was invoked
- `launchForPicker strips quarantine on macOS` — injects `_RecordingCommandRunner`, asserts `xattr` was called

Tests failed at compile time (5 compile errors — method did not exist).

**GREEN:** Added `launchForPicker()` to `ManagerLauncher`:
```dart
Future<int> launchForPicker() async {
  await ensureExtracted();
  final path = await resolveManagerPath();
  await stripQuarantine(path);
  final process = await _startProcess(path, ['--picker'], mode: ProcessStartMode.normal);
  return process.pid;
}
```

All 23 tests pass (9 github_release_store + 9 existing manager_launcher + 5 new).

### Task 2: Wire Version Manager into Flutter Advanced Settings

**VersionManagerPage** (`centroid-hmi/lib/pages/version_manager_page.dart`):
- Accepts `ManagerLauncher` via constructor
- Calls `launchForPicker()` in `initState` via `_launchManager()`
- Shows "Opening version manager..." → "Version manager opened (PID: N)" or error message
- Thin launcher only — no version list, no UI beyond status text

**main.dart changes:**
1. Import `pages/version_manager_page.dart` added
2. `managerLauncher` promoted from local `main()` variable to module-level `final` (matches `dbusCompleter` pattern)
3. `MenuItem(label: 'Version Manager', path: '/advanced/version-manager', icon: Icons.update)` added to Advanced children after Key Repository
4. Beamer route `/advanced/version-manager` → `VersionManagerPage(launcher: managerLauncher)` added to `createLocationBuilder`

**flutter analyze results:**
- `version_manager_page.dart`: No issues found
- `main.dart`: 4 pre-existing info/warnings (dbus, font_awesome_flutter, unused registry import, tfc_dart) — no new errors introduced

## Verification

- `flutter test` (centroidx_upgrader): 23/23 pass
- `flutter analyze lib/pages/version_manager_page.dart`: No issues
- VER-03: "Version Manager" MenuItem in Advanced menu, Beamer route wired, calls `launchForPicker()`
- launchForPicker passes `['--picker']` with `ProcessStartMode.normal`

## Deviations from Plan

### Automatic: Phase 03 merge required

**Found during:** Pre-execution environment check
**Issue:** Worktree `worktree-agent-a413b025` was branched from main before Phase 03 work (centroidx_upgrader package) landed. The package files did not exist in the worktree.
**Fix:** Merged `f094a05` (docs(03-02): complete flutter integration wiring plan) into this worktree branch, bringing in the full `packages/centroidx_upgrader/` tree and updated `centroid-hmi/main.dart`.
**Impact:** No code changes required after merge — all existing interfaces were exactly as the plan specified.

## Known Stubs

None — `launchForPicker()` is fully implemented. `VersionManagerPage` correctly delegates all UI to the Go manager binary; there are no hardcoded placeholder values that block the plan goal.

## Self-Check: PASSED

- `/c/Users/Centroid/Projects/tfc-hmi2/.claude/worktrees/agent-a413b025/packages/centroidx_upgrader/lib/src/manager_launcher.dart` — FOUND (launchForPicker present)
- `/c/Users/Centroid/Projects/tfc-hmi2/.claude/worktrees/agent-a413b025/packages/centroidx_upgrader/test/manager_launcher_test.dart` — FOUND (5 new tests present)
- `/c/Users/Centroid/Projects/tfc-hmi2/.claude/worktrees/agent-a413b025/centroid-hmi/lib/pages/version_manager_page.dart` — FOUND
- `/c/Users/Centroid/Projects/tfc-hmi2/.claude/worktrees/agent-a413b025/centroid-hmi/lib/main.dart` — FOUND (contains version-manager)
- Commit `41be4c4` (feat(04-02): implement launchForPicker) — FOUND
- Commit `cb9d619` (feat(04-02): wire Version Manager) — FOUND
