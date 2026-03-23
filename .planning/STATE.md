---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Ready to execute
stopped_at: Completed 02-core-engine-02-03-PLAN.md
last_updated: "2026-03-23T18:58:13.169Z"
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 8
  completed_plans: 7
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-23)

**Core value:** Users receive a seamless, one-click update experience — popup notification on startup, click yes, app updates and reopens — without depending on the Microsoft Store
**Current focus:** Phase 02 — Core Engine

## Current Position

Phase: 02 (Core Engine) — EXECUTING
Plan: 5 of 5

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3: `UpgraderStore` Dart interface method signatures need verification from `larryaasen/upgrader` source before implementation (MEDIUM confidence from docs alone)
- Phase 5: Manager self-update on Windows requires a spike to choose between `creativeprojects/go-selfupdate` and `minio/selfupdate` (binary rename pattern)
- General: GitHub token distribution strategy for end-user machines not yet decided (env var vs config file vs embedded via ldflags)

## Session Continuity

Last session: 2026-03-23T18:58:13.166Z
Stopped at: Completed 02-core-engine-02-03-PLAN.md
Resume file: None
