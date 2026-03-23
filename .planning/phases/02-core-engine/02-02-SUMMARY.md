---
phase: 02-core-engine
plan: "02"
subsystem: testing
tags: [go, github-api, httptest, go-github, io-teereader, progress-download]

# Dependency graph
requires:
  - phase: 02-core-engine-01
    provides: ReleasesClient interface and full githubClient implementation

provides:
  - httptest-based integration tests for GitHub client (ListReleases, GetLatestRelease, error cases)
  - DownloadWithProgress function with progressWriter for tracked asset downloads
  - testdata fixtures: mock_releases.json, mock_release_latest.json, SHA256SUMS.txt

affects:
  - 02-core-engine-03 (update engine consumes ReleasesClient and DownloadWithProgress)
  - 02-core-engine-04 (version selection uses ListReleases)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - httptest.NewServer mock API pattern for go-github client tests
    - io.TeeReader + progressWriter for download progress tracking
    - testdata/ directory with JSON fixtures for API response simulation

key-files:
  created:
    - tools/centroidx-manager/internal/github/client_test.go
    - tools/centroidx-manager/internal/github/download.go
    - tools/centroidx-manager/internal/github/download_test.go
    - tools/centroidx-manager/testdata/mock_releases.json
    - tools/centroidx-manager/testdata/mock_release_latest.json
    - tools/centroidx-manager/testdata/SHA256SUMS.txt
  modified: []

key-decisions:
  - "progressWriter is unexported from package github - external tests use a local copy to test the Write counting behavior"
  - "testdataPath() uses runtime.Caller to locate fixture files portably across OS and working directories"
  - "DownloadWithProgress falls back to resp.ContentLength when caller passes total=0, keeping interface flexible"

patterns-established:
  - "Pattern: httptest.NewServer with path-based routing for mock GitHub API in package_test (external test package)"
  - "Pattern: testdata/ at module root, referenced via runtime.Caller(0) for OS-portable path resolution"
  - "Pattern: io.TeeReader wrapping resp.Body through progressWriter before io.Copy to dest"

requirements-completed: [MGR-02, TEST-01, TEST-02]

# Metrics
duration: 2min
completed: 2026-03-23
---

# Phase 2 Plan 02: GitHub Client Tests and Download Progress Summary

**httptest mock-server tests for go-github v84 client (ListReleases, GetLatestRelease, error paths) plus DownloadWithProgress using io.TeeReader for tracked asset downloads**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-23T18:46:12Z
- **Completed:** 2026-03-23T18:48:14Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created three testdata fixtures with realistic GitHub Releases API payloads
- Wrote 4 client integration tests (list, latest, 401 error, 404 error) via httptest.NewServer
- Implemented DownloadWithProgress with io.TeeReader + progressWriter pattern
- Wrote 3 download tests (success, server error, progress writer unit)
- All 7 tests pass without network access

## Task Commits

Each task was committed atomically:

1. **Task 1: Create test fixtures and write tests for GitHub client and download** - `4c5ae07` (test)
2. **Task 2: Implement GitHub client to pass all tests** - already GREEN from Task 1 + Plan 02-01

_Note: Task 2 TDD GREEN state was immediate — client.go was complete from Plan 02-01, and download.go was created in Task 1. No separate implementation commit needed._

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `tools/centroidx-manager/testdata/mock_releases.json` - 2-release fixture array (2026.3.6, 2026.3.5) with assets
- `tools/centroidx-manager/testdata/mock_release_latest.json` - Single release fixture for GetLatestRelease
- `tools/centroidx-manager/testdata/SHA256SUMS.txt` - Checksum fixture for SHA256 test patterns
- `tools/centroidx-manager/internal/github/client_test.go` - httptest integration tests for ReleasesClient
- `tools/centroidx-manager/internal/github/download.go` - DownloadWithProgress + progressWriter implementation
- `tools/centroidx-manager/internal/github/download_test.go` - Download function tests

## Decisions Made
- progressWriter type is unexported (lowercase) — external test package `github_test` uses a local copy to test Write counting behavior without accessing private types
- testdataPath() helper uses `runtime.Caller(0)` to find fixture files portably from any working directory or OS path
- DownloadWithProgress falls back to `resp.ContentLength` when `total <= 0` — makes the API flexible for callers that don't know size ahead of time

## Deviations from Plan

None - plan executed exactly as written. Client.go was already fully implemented from Plan 02-01, so Task 2 reached GREEN state immediately after Task 1 created download.go.

## Issues Encountered

None. Go binary was not on PATH in the bash shell but was found at `/c/Program Files/Go/bin/go` — used full path prefix for all go commands.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- ReleasesClient fully tested with httptest — ready for update engine to consume in Plan 02-03
- DownloadWithProgress available for asset download in installer plans (02-04+)
- All GitHub client tests run in CI without network access (TEST-02 satisfied)

## Self-Check: PASSED

All created files verified present on disk. Task commit 4c5ae07 confirmed in git history.

---
*Phase: 02-core-engine*
*Completed: 2026-03-23*
