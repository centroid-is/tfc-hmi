---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Phase complete — ready for verification
stopped_at: Completed 05-02-PLAN.md
last_updated: "2026-03-23T20:28:07.081Z"
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 14
  completed_plans: 14
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-23)

**Core value:** Users receive a seamless, one-click update experience — popup notification on startup, click yes, app updates and reopens — without depending on the Microsoft Store
**Current focus:** Phase 05 — Integration Tests

## Current Position

Phase: 05 (Integration Tests) — EXECUTING
Plan: 2 of 2

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01-foundation P01 | 2 | 2 tasks | 4 files |
| Phase 01-foundation P02 | 6 | 1 tasks | 4 files |
| Phase 01-foundation P03 | 3 | 3 tasks | 3 files |
| Phase 02-core-engine P01 | 3 | 2 tasks | 9 files |
| Phase 02-core-engine P02 | 2 | 2 tasks | 6 files |
| Phase 02-core-engine P04 | 5 | 2 tasks | 7 files |
| Phase 02-core-engine P03 | 145 | 2 tasks | 6 files |
| Phase 02-core-engine P05 | 5 | 2 tasks | 7 files |
| Phase 03-flutter-integration P01 | 6 | 2 tasks | 7 files |
| Phase 03-flutter-integration P02 | 3 | 2 tasks | 6 files |
| Phase 04-version-management P02 | 152 | 2 tasks | 4 files |
| Phase 04-version-management P01 | 25 | 2 tasks | 6 files |
| Phase 05-integration-tests P01 | 2 | 2 tasks | 2 files |
| Phase 05 P02 | 2 | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Phase 1 must lock Publisher CN into pubspec.yaml before any package ships — changing it later forces a full reinstall on all user machines (no upgrade path)
- Roadmap: Phase 3 needs source validation of `UpgraderStore` Dart interface before implementation (docs-only confirmation is insufficient)
- [Phase 01-foundation]: Import cert to LocalMachine\TrustedPeople (not Root) — avoids extra Windows security dialog, sufficient for MSIX sideloading
- [Phase 01-foundation]: RFC 3161 timestamp (/tr /td SHA256) in signtool_options — omitting makes packages uninstallable after cert expiry with no recovery path
- [Phase 01-foundation]: PFX cert generated once locally, never in CI — regenerating changes thumbprint and breaks upgrade path for existing installs
- [Phase 01-foundation]: MSYS2 MinGW-w64 required for CGO on Windows — Fyne's OpenGL renderer needs GCC; CI uses native runners with pre-installed compilers
- [Phase 01-foundation]: macOS CI builds darwin/arm64 only on macos-latest (Apple Silicon); darwin/amd64 deferred - CGO cross-compile from arm64 unreliable
- [Phase 01-foundation]: create-release job guarded by startsWith(github.ref, refs/tags/) to prevent spurious releases on workflow_dispatch
- [Phase 01-foundation]: MSIX cert password uses inline GitHub Actions expression in --certificate-password CLI flag, not env: + envvar pattern
- [Phase 02-core-engine]: Use semver.NewVersion (not StrictNewVersion) for CalVer - StrictNewVersion rejects YYYY.MM.DD format
- [Phase 02-core-engine]: BrowserDownloadURL for asset download - avoids CDN Authorization header conflict with DownloadReleaseAsset
- [Phase 02-core-engine]: ReleasesClient constructor accepts baseURL param for httptest injection - keeps interface clean, enables test doubles
- [Phase 02-core-engine]: progressWriter unexported - external tests use local copy to verify Write counting without accessing private types
- [Phase 02-core-engine]: testdataPath uses runtime.Caller(0) for OS-portable fixture path resolution in tests
- [Phase 02-core-engine]: DownloadWithProgress falls back to resp.ContentLength when caller passes total=0
- [Phase 02-core-engine]: Helper functions in installer.go (no build tag) instead of per-platform files — enables one test file to cover all platform command construction via mockRunner
- [Phase 02-core-engine]: installLinux uses exec.LookPath for pkexec/sudo detection at runtime — avoids hardcoding elevation path
- [Phase 02-core-engine]: extractManagerFrom takes src+appdataRoot params for testability; pathIsFromMSIX extracted from IsRunningFromMSIX for table-driven testing
- [Phase 02-core-engine]: DownloadAndVerify uses net/http for SHA256SUMS.txt fetch and github.DownloadWithProgress for asset - temp file renamed atomically on verify success
- [Phase 02-core-engine]: WaitForPIDExit returns nil on timeout (no force-kill) - Flutter app exits voluntarily; process.go has no build tag, platform files implement waitForPIDExitPlatform
- [Phase 02-core-engine]: Engine Update() takes DestDir in UpdateOptions — allows test TempDirs without global state
- [Phase 02-core-engine]: main_windows.go uses init() with build tag — main.go stays platform-agnostic, MSIX extraction runs before main
- [Phase 02-core-engine]: CGO_ENABLED=1 required for Fyne build — MSYS2 MinGW-w64 gcc must be on PATH for Windows builds
- [Phase 03-flutter-integration]: AssetLoader typedef returns List<int> not ByteData so tests run without Flutter binding initialization
- [Phase 03-flutter-integration]: platformIsWindows/platformIsMacOS injected as constructor params instead of dart:io Platform.isX to enable platform-branch testing on any OS
- [Phase 03-flutter-integration]: Injectable typedefs pattern (ProcessStarter, CommandRunner, AssetLoader, PathResolver) established for testable process/filesystem operations in Dart
- [Phase 03-flutter-integration]: Use upgrader.state.versionInfo (not currentVersionInfo) for appStoreVersion - Upgrader v11 exposes version info through UpgraderState, not a direct getter on Upgrader class
- [Phase 03-flutter-integration]: Instantiate ManagerLauncher with rootBundle-backed assetLoader in main.dart - avoids UnimplementedError from _flutterServices() placeholder in production
- [Phase 04-version-management]: managerLauncher promoted to module level — avoids threading it through createLocationBuilder, matches dbusCompleter pattern
- [Phase 04-version-management]: ProcessStartMode.normal for launchForPicker — picker window is interactive and stays open alongside Flutter app unlike launchForUpdate (detached)
- [Phase 04-01]: Use -tags ci for Fyne UI tests to disable GLFW driver (no CGO required in test environment)
- [Phase 04-01]: ShowVersionPicker returns *widget.List for testability, accepts nil window for unit tests
- [Phase 04-01]: ListAllReleases uses sort.Slice with semver.GreaterThan to avoid month boundary pitfall of string comparison
- [Phase 05-integration-tests]: Integration tests placed in package update (same package) to access unexported selectPlatformAssetName() helper for platform-agnostic asset discovery
- [Phase 05-integration-tests]: Tests use t.Skip (not t.Fatal) when no matching platform asset found — keeps CI green in repos without all platform assets
- [Phase 05]: Same package (package platform) for integration tests to access parseMountPoint() without exporting it
- [Phase 05]: Linux DpkgDryRun uses dpkg --info (not dpkg -i) so no root access is needed on CI runners
- [Phase 05]: Platform test step gets 120s timeout vs 300s for download tests — local commands only, no network

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3: `UpgraderStore` Dart interface method signatures need verification from `larryaasen/upgrader` source before implementation (MEDIUM confidence from docs alone)
- Phase 5: Manager self-update on Windows requires a spike to choose between `creativeprojects/go-selfupdate` and `minio/selfupdate` (binary rename pattern)
- General: GitHub token distribution strategy for end-user machines not yet decided (env var vs config file vs embedded via ldflags)

## Session Continuity

Last session: 2026-03-23T20:28:07.078Z
Stopped at: Completed 05-02-PLAN.md
Resume file: None
