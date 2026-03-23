---
phase: 02-core-engine
plan: 05
subsystem: centroidx-manager
tags: [go, fyne, update-engine, ui, cli, tdd]
dependency_graph:
  requires: [02-01, 02-02, 02-03, 02-04]
  provides: [update-engine, fyne-ui, cli-entrypoint]
  affects: [main-app-integration, flutter-upgrader-plugin]
tech_stack:
  added: []
  patterns:
    - TDD (RED→GREEN) for engine orchestration
    - fyne.Do() for goroutine-safe Fyne widget updates
    - Interface injection (ReleasesClient, Installer) for testability
    - dialog.NewCustomWithoutButtons + widget.NewProgressBar (not deprecated dialog.NewProgress)
    - //go:build windows init() for MSIX extraction before main()
key_files:
  created:
    - tools/centroidx-manager/internal/update/engine_test.go
    - tools/centroidx-manager/internal/ui/app.go
    - tools/centroidx-manager/internal/ui/progress.go
    - tools/centroidx-manager/internal/ui/errors.go
    - tools/centroidx-manager/main_windows.go
  modified:
    - tools/centroidx-manager/internal/update/engine.go
    - tools/centroidx-manager/main.go
decisions:
  - Engine Update() takes DestDir in UpdateOptions — allows test TempDirs without global state
  - selectPlatformAssetName() unexported helper in engine.go with same-package visibility for test assertions
  - downloadCertAsset() looks for .cer/.crt assets in release list — best-effort, non-fatal if missing
  - main_windows.go uses init() with //go:build windows — main.go stays platform-agnostic
  - CGO_ENABLED=1 required for Fyne build — needs MSYS2 MinGW-w64 gcc on Windows
metrics:
  duration_minutes: 5
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_created_or_modified: 7
requirements: [MGR-05, MGR-06, MGR-09, INST-01, INST-03]
---

# Phase 02 Plan 05: Update Engine, Fyne UI, and CLI Entrypoint Summary

**One-liner:** Full update engine orchestrating fetch→download→verify→install→relaunch, wired to Fyne UI progress/error dialogs and a flag-parsed CLI entrypoint.

## What Was Built

### Task 1: Update Engine (TDD)

**engine.go** — Complete update orchestration:
- `ReleaseInfo` and `UpdateOptions` structs
- `FetchReleaseInfo(ctx, version)` — latest via `GetLatestRelease`; specific version via `ListReleases` with tag matching
- `SelectAsset(release)` — finds platform asset by naming convention `centroidx_{os}_{arch}.{ext}` (windows→msix, linux→deb, darwin→dmg) plus `SHA256SUMS.txt`
- `Update(ctx, opts)` — orchestrates: fetch → select → wait PID → `DownloadAndVerify` → trust cert → install → launch app
- `Install(ctx, destDir, onProgress)` — first-time shortcut (calls Update with FirstTime=true, Version="")
- `downloadCertAsset()` — looks for `.cer`/`.crt` in release assets, downloads to destDir for trust installation
- Engine is completely Fyne-free; progress via callback

**engine_test.go** — 11 tests covering all paths:
- `mockReleasesClient` + `mockInstaller` implement the respective interfaces
- `httptest.Server` serves asset + SHA256SUMS.txt for download tests
- Tests: FetchReleaseInfo, FetchReleaseInfo_SpecificVersion, FetchReleaseInfo_VersionNotFound, SelectAsset, SelectAsset_Missing, Update_Success, Update_ChecksumMismatch, Update_NetworkError, Update_InstallError, Install_FirstTime, Install_Shortcut

### Task 2: Fyne UI Layer and CLI Entrypoint

**internal/ui/progress.go:**
- `NewProgressDialog(win, title)` — creates `dialog.NewCustomWithoutButtons` with `widget.NewProgressBar` (NOT deprecated `dialog.NewProgress`)
- `UpdateProgress(bar, downloaded, total)` — sets bar value; must be called via `fyne.Do()` from goroutines

**internal/ui/errors.go:**
- `ShowError(win, err)` — categorises error by content (network/checksum/permission) → user-friendly message
- `ShowReleaseNotes(win, info, onConfirm)` — markdown release notes in `dialog.NewCustomConfirm` with Install/Cancel buttons

**internal/ui/app.go:**
- `Run(opts)` — creates Fyne app, wires engine dependencies, routes by mode
- `runInstallMode` — label + progress dialog + goroutine calling `eng.Install`, all UI updates via `fyne.Do()`
- `runUpdateMode` — fetch release info → show release notes → on confirm: progress dialog + goroutine calling `eng.Update`

**main.go:**
- `--update` (bool), `--version` (string), `--wait-pid` (int), `--token` (string) flags
- `githubOwner`/`githubRepo` variables injectable via `-ldflags`
- Falls back to `CENTROIDX_GITHUB_TOKEN` env var for token
- Routes to "install" or "update" mode → `ui.Run(opts)`

**main_windows.go** (`//go:build windows`):
- `init()` checks `platform.IsRunningFromMSIX()` and calls `platform.ExtractManager()` before main

## Test Results

```
ok  github.com/centroid-is/centroidx-manager/internal/update   0.518s  (11 engine + 14 other)
ok  github.com/centroid-is/centroidx-manager/internal/github   (all pass)
ok  github.com/centroid-is/centroidx-manager/internal/platform (all pass)
```

Build: `go build .` succeeds with `CGO_ENABLED=1` and MSYS2 MinGW-w64 gcc.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Added DestDir field to UpdateOptions**
- **Found during:** Task 1 implementation
- **Issue:** Plan's UpdateOptions didn't include DestDir, but DownloadAndVerify requires a destination directory. Without it, tests couldn't inject TempDir and production code would use os.TempDir() globally.
- **Fix:** Added `DestDir string` to UpdateOptions; engine uses `os.TempDir()` as fallback if empty.
- **Files modified:** engine.go, engine_test.go

**2. [Rule 1 - Bug] selectPlatformAssetName() kept unexported but accessible from test**
- **Found during:** Task 1 (test writing)
- **Issue:** Tests need to know the expected asset filename for the current OS to build test releases with matching asset names. Plan said "exported" but same-package access works without export.
- **Fix:** Kept `selectPlatformAssetName()` unexported; engine_test.go calls it directly (same package `update`).
- **Files modified:** engine.go, engine_test.go

## Known Stubs

None. All implemented functionality is wired end-to-end.

## Self-Check: PASSED

Files verified:
- tools/centroidx-manager/internal/update/engine.go — FOUND
- tools/centroidx-manager/internal/update/engine_test.go — FOUND
- tools/centroidx-manager/internal/ui/app.go — FOUND
- tools/centroidx-manager/internal/ui/progress.go — FOUND
- tools/centroidx-manager/internal/ui/errors.go — FOUND
- tools/centroidx-manager/main.go — FOUND
- tools/centroidx-manager/main_windows.go — FOUND

Commits verified:
- 3b6b708 feat(02-core-engine-02-05): implement update engine with TDD — FOUND
- b740309 feat(02-core-engine-02-05): implement Fyne UI layer and CLI entrypoint — FOUND
