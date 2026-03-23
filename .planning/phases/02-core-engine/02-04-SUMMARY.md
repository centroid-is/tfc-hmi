---
phase: 02-core-engine
plan: 04
subsystem: platform
tags: [go, windows, linux, darwin, msix, dpkg, hdiutil, powershell, tdd, mock]

# Dependency graph
requires:
  - phase: 02-core-engine
    plan: 01
    provides: "Installer interface definition in internal/platform/installer.go"

provides:
  - "CommandRunner interface for testable platform command execution"
  - "installWindows/trustCertificateWindows/installLinux/installDarwin helpers"
  - "WindowsInstaller/LinuxInstaller/DarwinInstaller platform implementations with build tags"
  - "MSIX self-extraction (ExtractManager/IsRunningFromMSIX) for Windows"
  - "Mock CommandRunner test harness for verifying command construction"

affects:
  - "02-core-engine (update engine uses NewInstaller to dispatch installs)"
  - "05-integration (integration tests call NewInstaller for full flow)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CommandRunner interface injected into platform helpers — allows mock testing without build tag isolation"
    - "Helper functions (installWindows, etc.) in non-build-tagged installer.go; platform files delegate to helpers"
    - "parseMountPoint scans hdiutil -plist output for /Volumes/ path"
    - "extractManagerFrom takes src+appdataRoot params for testability"
    - "pathIsFromMSIX extracted from IsRunningFromMSIX for table-driven testing"

key-files:
  created:
    - tools/centroidx-manager/internal/platform/installer_test.go
    - tools/centroidx-manager/internal/platform/extract_windows.go
    - tools/centroidx-manager/internal/platform/extract_windows_test.go
    - tools/centroidx-manager/internal/platform/windows.go
    - tools/centroidx-manager/internal/platform/linux.go
    - tools/centroidx-manager/internal/platform/darwin.go
  modified:
    - tools/centroidx-manager/internal/platform/installer.go

key-decisions:
  - "Helper functions in installer.go (no build tag) instead of duplicating logic in each platform file — enables platform-agnostic tests via mockRunner"
  - "installLinux uses exec.LookPath for pkexec/sudo detection at runtime — avoids hardcoding elevation path per anti-pattern guidance"
  - "installDarwin uses defer for hdiutil detach — guarantees cleanup even when cp fails (verified by TestDarwinInstaller_Install_CleanupOnError)"
  - "extractManagerFrom takes src+appdataRoot params for testability instead of calling os.Executable/os.Getenv directly"
  - "pathIsFromMSIX extracted from IsRunningFromMSIX for table-driven testing of WindowsApps path detection"

patterns-established:
  - "TDD: mock CommandRunner captures (name, args) pairs; tests use hasArg/hasArgContaining for flexible assertion"
  - "Build-tag files (windows.go, linux.go, darwin.go) are thin wrappers; all logic in non-tagged installer.go"
  - "commandError type wraps exec errors with operation context for actionable error messages"

requirements-completed: [MGR-07, MGR-09, MGR-10, INST-02, INST-03]

# Metrics
duration: 5min
completed: 2026-03-23
---

# Phase 02 Plan 04: Platform Installers Summary

**Cross-platform installer logic (Windows Add-AppxPackage, Linux dpkg, macOS hdiutil+xattr) with mock CommandRunner for test isolation, plus MSIX self-extraction to APPDATA**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-23T18:46:37Z
- **Completed:** 2026-03-23T18:51:02Z
- **Tasks:** 2 (combined TDD RED+GREEN since helpers and tests live in same non-build-tagged file)
- **Files modified:** 7

## Accomplishments
- CommandRunner interface with execRunner implementation enables mock injection for all platform tests
- 12 tests covering Windows (Install/TrustCertificate/error case), Linux (pkexec+sudo), Darwin (attach/cp/xattr/cleanup), LaunchApp, parseMountPoint, and MSIX extraction
- Three platform wrappers (windows.go, linux.go, darwin.go) with correct //go:build tags delegate to testable helpers
- ExtractManager copies manager binary from MSIX VFS path to APPDATA on first run, idempotent on second run

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Platform installer tests + implementation** - `5e8292a` (test)

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `tools/centroidx-manager/internal/platform/installer.go` - Added CommandRunner interface, execRunner, and all platform helper functions
- `tools/centroidx-manager/internal/platform/installer_test.go` - Mock runner tests for all platform helpers
- `tools/centroidx-manager/internal/platform/windows.go` - `//go:build windows` wrapper with NewInstaller()
- `tools/centroidx-manager/internal/platform/linux.go` - `//go:build linux` wrapper with NewInstaller()
- `tools/centroidx-manager/internal/platform/darwin.go` - `//go:build darwin` wrapper with NewInstaller()
- `tools/centroidx-manager/internal/platform/extract_windows.go` - `//go:build windows` MSIX extraction with extractManagerFrom + pathIsFromMSIX
- `tools/centroidx-manager/internal/platform/extract_windows_test.go` - `//go:build windows` extraction tests

## Decisions Made
- Helper functions in `installer.go` (no build tag) instead of per-platform files — enables one test file to cover all platform command construction without build tag restrictions
- Used `exec.LookPath` for pkexec/sudo detection per anti-pattern guidance (Pitfall 5: never hardcode paths)
- `defer runner.Run("hdiutil", "detach", ...)` in installDarwin ensures DMG always unmounted even on cp failure
- `extractManagerFrom(src, appdataRoot)` takes explicit params instead of os.Executable/os.Getenv for clean testability

## Deviations from Plan

None — plan executed exactly as written. The plan explicitly recommended the "SIMPLEST CORRECT APPROACH" of putting helper functions in installer.go; that is what was implemented.

## Issues Encountered
- Go not in shell PATH on this Windows machine — added `/c/Program Files/Go/bin` to PATH for test runs
- Worktree branch was behind main (missing 02-01 work) — fast-forward merged main before starting

## Known Stubs

None — all functions are fully implemented. LaunchApp in windows.go uses `explorer.exe` as a placeholder for the shell:AppsFolder URI launch; this will need the actual package family name in a future plan when the MSIX package name is finalized.

## Next Phase Readiness
- Platform installers fully tested and ready for integration by the update engine
- NewInstaller() defined per platform — update engine can call it without knowing the OS
- MSIX extraction ready for Windows bundle scenario
- LaunchApp on Windows needs real package family name when MSIX packaging is finalized

## Self-Check: PASSED

- FOUND: tools/centroidx-manager/internal/platform/installer.go
- FOUND: tools/centroidx-manager/internal/platform/installer_test.go
- FOUND: tools/centroidx-manager/internal/platform/windows.go
- FOUND: tools/centroidx-manager/internal/platform/linux.go
- FOUND: tools/centroidx-manager/internal/platform/darwin.go
- FOUND: tools/centroidx-manager/internal/platform/extract_windows.go
- FOUND: tools/centroidx-manager/internal/platform/extract_windows_test.go
- FOUND: .planning/phases/02-core-engine/02-04-SUMMARY.md
- Commit 5e8292a: FOUND in git log
- 12/12 tests PASS: `go test -v ./internal/platform/...`

---
*Phase: 02-core-engine*
*Completed: 2026-03-23*
