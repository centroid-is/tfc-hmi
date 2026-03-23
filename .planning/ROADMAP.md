# Roadmap: CentroidX Manager

## Overview

Five phases that take centroidx-manager from zero to a fully-tested, cross-platform auto-updater. Phase 1 locks down the certificate and CI infrastructure that everything depends on. Phase 2 builds the Go update engine in isolation with unit tests. Phase 3 wires the Flutter side to the engine and handles platform-specific packaging constraints (including macOS Gatekeeper), producing the complete end-to-end update flow. Phase 4 adds version management and rollback. Phase 5 validates the full system with integration tests against real GitHub Releases.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - Certificate infrastructure, MSIX sideload config, CI pipeline, and Go scaffolding on all three platforms (completed 2026-03-23)
- [ ] **Phase 2: Core Engine** - GitHub client, download/verify, platform installer, PID-wait, first-time install, and unit/mock tests
- [ ] **Phase 3: Flutter Integration** - Custom UpgraderStore plugin, manager launcher, MSIX embedding, macOS quarantine handling, and end-to-end update flow
- [ ] **Phase 4: Version Management** - Version picker UI, rollback, Flutter Settings deep-link, and CalVer comparison
- [ ] **Phase 5: Integration Tests** - E2E tests against real GitHub Releases and platform install verification

## Phase Details

### Phase 1: Foundation
**Goal**: The certificate infrastructure, MSIX sideload configuration, and CI pipeline are correct and locked before any package reaches a user machine
**Depends on**: Nothing (first phase)
**Requirements**: CERT-01, CERT-02, CERT-03, CERT-04, MGR-01, CI-01, CI-02, CI-03, CI-04
**Success Criteria** (what must be TRUE):
  1. A `store: false` MSIX with the self-signed certificate's exact Publisher CN installs via `Add-AppxPackage` on a clean Windows VM that has never seen the app
  2. The self-signed certificate installs into `LocalMachine\TrustedPeople` with UAC elevation and the package becomes installable without Developer Mode
  3. The certificate carries an RFC 3161 timestamp so the package remains installable after the cert's validity window expires
  4. A Go + Fyne hello-world binary compiles and runs on Windows, Linux, and macOS via CI (native GitHub Actions runners), with artifacts uploaded to a GitHub Release
  5. CI produces a GitHub Release with all platform artifacts and a `SHA256SUMS.txt` file named per the `centroidx-manager_{os}_{arch}` convention
**Plans:** 3/3 plans complete

Plans:
- [x] 01-01-PLAN.md — Certificate generation scripts and MSIX sideload pubspec config
- [x] 01-02-PLAN.md — Go+Fyne project scaffolding (hello-world)
- [x] 01-03-PLAN.md — CI pipeline (windows.yml signing, build-manager.yml, tag.yml release job)

### Phase 2: Core Engine
**Goal**: The centroidx-manager Go binary can fetch, download, verify, and install a release on any platform — and is fully unit-tested with mock HTTP — before any Flutter code is touched
**Depends on**: Phase 1
**Requirements**: MGR-02, MGR-03, MGR-04, MGR-05, MGR-06, MGR-07, MGR-08, MGR-09, MGR-10, INST-01, INST-02, INST-03, TEST-01, TEST-02
**Success Criteria** (what must be TRUE):
  1. Running the standalone manager exe on a clean machine fetches the latest release from GitHub, displays release notes, downloads the platform asset with a progress bar, verifies the SHA256 checksum, and installs the main app
  2. The manager waits for a given `--wait-pid` to exit before invoking the platform installer, and relaunches the main app after a successful install
  3. Network failures, checksum mismatches, and permission errors each produce a clear error message in the Fyne UI rather than a silent crash or hang
  4. On Windows, the manager extracts itself to `%APPDATA%\centroidx\manager\` and the first-time install handles certificate trust before package installation
  5. Unit tests (version comparison, GitHub API client, download+verify) and mock-HTTP integration tests all pass in CI
**Plans:** 2/5 plans executed

Plans:
- [x] 02-01-PLAN.md — Interfaces, version parser (CalVer), and SHA256 checksum verification (TDD)
- [x] 02-02-PLAN.md — GitHub Releases API client with httptest mock tests
- [ ] 02-03-PLAN.md — Download+verify pipeline and cross-platform PID wait
- [ ] 02-04-PLAN.md — Platform installers (Windows/Linux/macOS), cert trust, MSIX extraction
- [ ] 02-05-PLAN.md — Update engine orchestration, Fyne UI, and CLI entrypoint

### Phase 3: Flutter Integration
**Goal**: The Flutter app detects a new GitHub Release on startup, prompts the user, and hands off to the bundled manager — which completes the install and relaunches the app — on all three platforms, including macOS Sequoia Gatekeeper handling
**Depends on**: Phase 2
**Requirements**: FLT-01, FLT-02, FLT-03, FLT-04, FLT-05, FLT-06, FLT-07
**Success Criteria** (what must be TRUE):
  1. On app startup, when a newer GitHub Release exists, an upgrade prompt appears within the existing `upgrader` dialog flow (not a custom dialog from scratch)
  2. User confirms the update prompt → Flutter spawns the manager as a detached process with `--wait-pid` and the current app exits cleanly
  3. The `microsoft_store_upgrader` dependency is removed from `pubspec.yaml` and the build succeeds
  4. The manager binary is bundled inside the MSIX, deb, and dmg packages and is accessible to the Flutter launcher without manual user steps
  5. The full update flow completes on Windows (MSIX), Linux (deb), and macOS 15.1+ (dmg) with no extra user steps — macOS quarantine attribute is stripped programmatically before launch
**Plans**: TBD

### Phase 4: Version Management
**Goal**: Users can view all available versions and roll back to any previous version from within the app, and the version format is handled correctly throughout
**Depends on**: Phase 3
**Requirements**: VER-01, VER-02, VER-03, VER-04
**Success Criteria** (what must be TRUE):
  1. The manager UI lists all available versions from GitHub Releases with their release dates and notes
  2. Selecting any previous version from the list installs it, replacing the current version (rollback works)
  3. A deep-link from the Flutter app's Settings page opens the manager directly to the version picker
  4. Version comparisons using the `YYYY.MM.DD+build` format are correct — `2026.10.1` is correctly identified as newer than `2026.9.30`
**Plans**: TBD

### Phase 5: Integration Tests
**Goal**: The complete update flow is validated against real GitHub Releases in CI, confirming each platform's install commands execute correctly on clean machines
**Depends on**: Phase 4
**Requirements**: TEST-03, TEST-04
**Success Criteria** (what must be TRUE):
  1. A CI job downloads a real asset from a GitHub Release, verifies the SHA256 checksum, and the test passes against the live GitHub Releases API
  2. Platform install commands (`Add-AppxPackage`, `dpkg -i`, `hdiutil`+copy) execute correctly and are verified per platform in CI
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 3/3 | Complete   | 2026-03-23 |
| 2. Core Engine | 2/5 | In Progress|  |
| 3. Flutter Integration | 0/TBD | Not started | - |
| 4. Version Management | 0/TBD | Not started | - |
| 5. Integration Tests | 0/TBD | Not started | - |
