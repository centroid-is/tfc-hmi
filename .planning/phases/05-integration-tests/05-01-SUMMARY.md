---
phase: 05-integration-tests
plan: 01
subsystem: testing
tags: [go, integration-test, github-releases, sha256, ci, github-actions]

# Dependency graph
requires:
  - phase: 02-core-engine
    provides: DownloadAndVerify, ParseSHA256SUMS, VerifyFile functions in update package
  - phase: 02-core-engine
    provides: github.NewClient ReleasesClient implementation
  - phase: 01-foundation
    provides: build-manager.yml CI workflow

provides:
  - E2E integration test that downloads real GitHub Release assets and verifies SHA256 checksums
  - //go:build integration gated test file with 3 test functions exercising live GitHub API
  - CI integration-test job running on all 3 platforms after build succeeds

affects:
  - Any future phase that modifies download.go, checksum.go, or github/client.go

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Integration tests in same package (package update) for white-box access to unexported helpers"
    - "//go:build integration tag to gate tests from normal go test runs"
    - "requireToken/requireRelease helpers with t.Skip for graceful degradation without credentials"
    - "120-second context timeout for all integration network calls"

key-files:
  created:
    - tools/centroidx-manager/internal/update/integration_test.go
  modified:
    - .github/workflows/build-manager.yml

key-decisions:
  - "Same package (package update) for integration tests to access selectPlatformAssetName() and other unexported helpers"
  - "Integration test skips gracefully (t.Skip) when no suitable release exists — avoids hard failures in repos without matching platform assets"
  - "needs: [build] dependency ensures integration tests only run after successful build"
  - "300s CI timeout for real downloads, 120s local test timeout"

patterns-established:
  - "Integration test pattern: requireToken() + requireRelease() helpers with t.Skip for graceful degradation"
  - "Platform-agnostic asset discovery using selectPlatformAssetName() from engine.go"
  - "Independent SHA256 re-verification in TestIntegration_ChecksumActuallyMatches to catch pipeline inconsistency"

requirements-completed: [TEST-03]

# Metrics
duration: 2min
completed: 2026-03-23
---

# Phase 5 Plan 1: Integration Tests Summary

**E2E integration test suite that downloads real GitHub Release assets via live API and verifies SHA256 checksums end-to-end, gated behind //go:build integration with CI job on all 3 platforms**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-23T20:19:56Z
- **Completed:** 2026-03-23T20:21:34Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created `integration_test.go` with `//go:build integration` tag containing 3 test functions: `TestIntegration_ListReleases`, `TestIntegration_DownloadAndVerifyChecksum`, and `TestIntegration_ChecksumActuallyMatches`
- All 3 tests skip gracefully when `GITHUB_TOKEN` is not set — verified locally
- Added `integration-test` CI job to `build-manager.yml` that runs after `build` succeeds, on all 3 platforms (windows-latest, ubuntu-latest, macos-latest), with 300s timeout and `GITHUB_TOKEN` secret injection
- `go vet -tags integration ./internal/update/` passes cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: Write E2E integration test for live GitHub Release download + checksum** - `c482926` (test)
2. **Task 2: Add integration test job to CI workflow** - `92403fa` (feat)

**Plan metadata:** (final docs commit below)

## Files Created/Modified
- `tools/centroidx-manager/internal/update/integration_test.go` - 3 integration tests exercising ListReleases, DownloadAndVerify, and independent SHA256 re-verification against live GitHub API
- `.github/workflows/build-manager.yml` - Added `integration-test` job with 3-platform matrix that runs after `build`

## Decisions Made
- Tests live in `package update` (same package as download.go) so they can access the unexported `selectPlatformAssetName()` helper for platform-agnostic asset discovery
- Used `t.Skip` (not `t.Fatal`) when no suitable release with matching platform assets is found — this keeps CI green in environments where only some platform assets exist
- `needs: [build]` dependency ensures expensive integration tests are gated behind a successful build

## Deviations from Plan

None — plan executed exactly as written. The test file matches the specified structure: `requireToken`, `requireRelease` helpers, 3 test functions using real `githubclient.NewClient`, 120-second context timeout, same package for unexported helper access.

## Issues Encountered
- This worktree branch was behind `main` and lacked the centroidx-manager codebase. Resolved by merging `main` into the worktree branch before proceeding (fast-forward merge, no conflicts).

## User Setup Required
None — `GITHUB_TOKEN` is a built-in GitHub Actions secret that is automatically available in all workflows. No manual configuration required.

## Next Phase Readiness
- Integration tests are ready to run against any future GitHub Release that includes a platform asset (`centroidx_{os}_{arch}.{ext}`) and `SHA256SUMS.txt`
- CI will automatically run integration tests on all 3 platforms on every merge after the `build` job passes
- No blockers — waiting for actual GitHub Releases to be published to test against live assets

---
*Phase: 05-integration-tests*
*Completed: 2026-03-23*

## Self-Check: PASSED

- FOUND: tools/centroidx-manager/internal/update/integration_test.go
- FOUND: .github/workflows/build-manager.yml
- FOUND: .planning/phases/05-integration-tests/05-01-SUMMARY.md
- FOUND commit: c482926 (test: integration test)
- FOUND commit: 92403fa (feat: CI integration-test job)
