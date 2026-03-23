---
phase: 02-core-engine
plan: "03"
subsystem: update-engine
tags: [download, checksum, progress, pid-wait, cross-platform, tdd]
dependency_graph:
  requires: [02-01, 02-02]
  provides: [DownloadAndVerify, WaitForPIDExit]
  affects: [engine.go, future GUI layer]
tech_stack:
  added: []
  patterns:
    - "DownloadAndVerify: fetch SHA256SUMS, download to temp file, verify hash, rename"
    - "WaitForPIDExit: build-tag-split platform impl (Signal(0) on Unix, OpenProcess on Windows)"
    - "TDD RED-GREEN: stubs first, tests written against stubs, then real implementation"
key_files:
  created:
    - tools/centroidx-manager/internal/update/download.go
    - tools/centroidx-manager/internal/update/download_test.go
    - tools/centroidx-manager/internal/update/process.go
    - tools/centroidx-manager/internal/update/process_unix.go
    - tools/centroidx-manager/internal/update/process_windows.go
    - tools/centroidx-manager/internal/update/process_test.go
  modified: []
decisions:
  - "DownloadAndVerify uses net/http directly for SHA256SUMS.txt fetch and delegates to github.DownloadWithProgress for the asset - keeps separation clean"
  - "Temp file named centroidx-download-* (os.CreateTemp) then renamed to assetFilename on success - atomic visible change only after verified"
  - "WaitForPIDExit delegates to waitForPIDExitPlatform in build-tag files; process.go has no build tag"
  - "Both platform PID implementations return nil on timeout (no force-kill) - Flutter app exits voluntarily"
  - "process_test.go uses 'go env GOROOT' as cross-platform subprocess (no sleep/timeout builtins needed)"
metrics:
  duration_seconds: 145
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_created: 6
  files_modified: 0
---

# Phase 02 Plan 03: Download+Verify Pipeline and PID Wait Summary

**One-liner:** SHA256-verified asset download pipeline (httptest-tested) plus build-tag-isolated cross-platform PID wait using Signal(0) on Unix and OpenProcess+WaitForSingleObject on Windows.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | Write tests for download+verify pipeline and PID wait | 7d621e9 | download.go (stub), download_test.go, process.go, process_unix.go, process_windows.go, process_test.go |
| 2 (GREEN) | Implement download+verify pipeline and platform PID wait | 398aa9c | download.go (real implementation) |

## What Was Built

### Download+Verify Pipeline (`download.go`)

`DownloadAndVerify(ctx, assetURL, checksumURL, assetFilename, destDir, onProgress)` orchestrates the critical data path:

1. Fetches `checksumURL` via `net/http`, parses it with `ParseSHA256SUMS`
2. Looks up the expected hash for `assetFilename`
3. Creates a temp file (`centroidx-download-*`) in `destDir`
4. Downloads the asset via `github.DownloadWithProgress` (progress callbacks forwarded)
5. Calls `VerifyFile` against the expected hash
6. On success: renames temp file to final `assetFilename` path, returns path
7. On any failure: removes temp file before returning error

### Cross-Platform PID Wait (`process.go` + platform files)

`WaitForPIDExit(pid, timeout)` delegates to:
- **Unix** (`process_unix.go`, `//go:build !windows`): polls `p.Signal(syscall.Signal(0))` every 200ms until error (process gone) or timeout
- **Windows** (`process_windows.go`, `//go:build windows`): `OpenProcess` with `PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE`, then `WaitForSingleObject`

Both implementations return `nil` on timeout — no force-kill (Flutter app exits voluntarily).

## Test Coverage

All 17 tests in `./internal/update/...` pass:

| Test | Scenario | Result |
|------|----------|--------|
| TestDownloadAndVerify_Success | Correct checksum, file saved | PASS |
| TestDownloadAndVerify_ChecksumMismatch | Wrong hash in SHA256SUMS | PASS (error contains "checksum mismatch", temp file cleaned up) |
| TestDownloadAndVerify_DownloadError | HTTP 500 from server | PASS |
| TestDownloadAndVerify_Progress | Progress callback called with increasing values | PASS |
| TestWaitForPIDExit_AlreadyExited | PID 99999999 (non-existent) | PASS |
| TestWaitForPIDExit_RunningProcess | Real subprocess via `go env GOROOT` | PASS |
| (+ 11 pre-existing from 02-01) | Checksum, version parsing | PASS |

## Verification

```
cd tools/centroidx-manager && go test ./internal/update/...
ok  github.com/centroid-is/centroidx-manager/internal/update  0.510s
```

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

Files exist:
- FOUND: tools/centroidx-manager/internal/update/download.go
- FOUND: tools/centroidx-manager/internal/update/download_test.go
- FOUND: tools/centroidx-manager/internal/update/process.go
- FOUND: tools/centroidx-manager/internal/update/process_unix.go
- FOUND: tools/centroidx-manager/internal/update/process_windows.go
- FOUND: tools/centroidx-manager/internal/update/process_test.go

Commits exist:
- FOUND: 7d621e9 (test - RED phase)
- FOUND: 398aa9c (feat - GREEN phase)
