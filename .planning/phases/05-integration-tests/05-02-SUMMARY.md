---
phase: 05-integration-tests
plan: 02
subsystem: testing
tags: [go, integration-test, platform, windows, linux, darwin, ci, github-actions]

# Dependency graph
requires:
  - phase: 05-integration-tests
    provides: integration-test CI job structure (from 05-01)
  - phase: 02-core-engine
    provides: platform/installer.go with installWindows, installLinux, installDarwin, parseMountPoint

provides:
  - Per-platform integration test files verifying real OS install tooling on native CI runners
  - //go:build integration && {os} gated test files for Windows, Linux, macOS
  - Shared test helpers runCommand/requireCommand in integration_test.go
  - CI integration-test job extended with platform test step on all 3 native runners

affects:
  - Any future phase modifying installer.go, windows.go, linux.go, or darwin.go

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Platform-specific integration tests with compound build tags: //go:build integration && windows"
    - "runCommand helper with 30-second context timeout capturing stdout and stderr separately"
    - "requireCommand helper using exec.LookPath with t.Skipf for graceful degradation"
    - "Minimal .deb construction via Go archive/tar + compress/gzip + ar command (no root)"
    - "Full hdiutil DMG lifecycle test: create + attach + parseMountPoint + detach"
    - "Same package (package platform) for integration tests to access unexported parseMountPoint"

key-files:
  created:
    - tools/centroidx-manager/internal/platform/integration_test.go
    - tools/centroidx-manager/internal/platform/integration_windows_test.go
    - tools/centroidx-manager/internal/platform/integration_linux_test.go
    - tools/centroidx-manager/internal/platform/integration_darwin_test.go
  modified:
    - .github/workflows/build-manager.yml

key-decisions:
  - "Same package (package platform) so integration tests access parseMountPoint() without exporting it"
  - "Linux DpkgDryRun uses dpkg --info (not dpkg -i) so no root access is needed on CI runners"
  - "Platform test step gets 120s timeout vs 300s for download tests — local commands only, no network"
  - "No GITHUB_TOKEN in platform test step — tests verify OS tooling, not GitHub API"

# Metrics
duration: 2min
completed: 2026-03-23
---

# Phase 5 Plan 2: Platform Integration Tests Summary

**Per-platform integration tests verifying Add-AppxPackage/dpkg/hdiutil install tooling on native CI runners, gated with //go:build integration && {os} build tags**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-23T20:24:56Z
- **Completed:** 2026-03-23T20:27:06Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Created `integration_test.go` with `//go:build integration` containing `runCommand` (30s context timeout, separate stdout/stderr) and `requireCommand` (exec.LookPath + t.Skipf) shared helpers
- Created `integration_windows_test.go` with `//go:build integration && windows` containing 3 tests: `TestIntegration_PowerShellAvailable` (Get-Command Add-AppxPackage), `TestIntegration_AddAppxPackage_InvalidPath` (-ErrorAction Stop verifies non-zero exit on bad path), `TestIntegration_ImportCertificate_CommandExists`
- Created `integration_linux_test.go` with `//go:build integration && linux` containing 3 tests: `TestIntegration_DpkgAvailable` (dpkg --version contains "Debian"), `TestIntegration_DpkgDryRun` (builds minimal valid .deb via ar + tar, runs dpkg --info without root), `TestIntegration_ElevationToolExists` (pkexec or sudo on PATH)
- Created `integration_darwin_test.go` with `//go:build integration && darwin` containing 3 tests: `TestIntegration_HdiutilAvailable` (hdiutil info exit 0), `TestIntegration_HdiutilCreateMountUnmount` (full DMG create+attach+parseMountPoint+verify+detach lifecycle), `TestIntegration_XattrAvailable` (which xattr)
- All Windows integration tests pass locally: `TestIntegration_PowerShellAvailable`, `TestIntegration_AddAppxPackage_InvalidPath`, `TestIntegration_ImportCertificate_CommandExists`
- Added "Run platform integration tests" step to `integration-test` job in `build-manager.yml` after the existing download tests step

## Task Commits

Each task was committed atomically:

1. **Task 1: Write per-platform integration tests for install command verification** - `c7d246a` (test)
2. **Task 2: Add platform integration test step to CI workflow** - `cab495d` (feat)

**Plan metadata:** (final docs commit below)

## Files Created/Modified

- `tools/centroidx-manager/internal/platform/integration_test.go` — Shared helpers: `runCommand` with 30s context timeout capturing stdout+stderr, `requireCommand` with exec.LookPath and t.Skipf
- `tools/centroidx-manager/internal/platform/integration_windows_test.go` — 3 tests: PowerShell cmdlet availability (Add-AppxPackage + Import-Certificate), Add-AppxPackage error behavior with -ErrorAction Stop
- `tools/centroidx-manager/internal/platform/integration_linux_test.go` — 3 tests: dpkg version output, minimal .deb construction via Go stdlib + ar + dpkg --info (no root), elevation tool (pkexec/sudo) presence
- `tools/centroidx-manager/internal/platform/integration_darwin_test.go` — 3 tests: hdiutil info, full DMG create/attach/parseMountPoint/detach lifecycle, xattr availability
- `.github/workflows/build-manager.yml` — "Run platform integration tests" step added to integration-test job: `go test -tags integration -v -timeout 120s ./internal/platform/ -run TestIntegration`

## Decisions Made

- Tests live in `package platform` (same package as installer.go) to access the unexported `parseMountPoint()` function without having to export it
- Linux `DpkgDryRun` uses `dpkg --info` not `dpkg -i` — avoids needing root access on CI runners while still confirming dpkg can parse the package format
- Platform test step uses 120s timeout (vs 300s for download tests) since it only runs local OS commands with no network I/O
- No `GITHUB_TOKEN` environment variable in the platform test step — tests are purely OS tooling verification

## Deviations from Plan

None — plan executed exactly as written. All 4 test files created with specified build tags, all 3 tests per platform, CI workflow step added as specified.

## Known Stubs

None — all tests exercise real OS tooling. No placeholder data or hardcoded empty values.

## Self-Check: PASSED

- FOUND: tools/centroidx-manager/internal/platform/integration_test.go
- FOUND: tools/centroidx-manager/internal/platform/integration_windows_test.go
- FOUND: tools/centroidx-manager/internal/platform/integration_linux_test.go
- FOUND: tools/centroidx-manager/internal/platform/integration_darwin_test.go
- FOUND: .github/workflows/build-manager.yml (contains "Run platform integration tests")
- FOUND commit c7d246a (test: per-platform integration tests)
- FOUND commit cab495d (feat: CI platform integration test step)
