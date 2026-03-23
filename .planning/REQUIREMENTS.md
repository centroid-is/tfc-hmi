# Requirements: CentroidX Manager

**Defined:** 2026-03-23
**Core Value:** Users receive a seamless, one-click update experience without depending on the Microsoft Store

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Foundation & Certificate Infrastructure

- [x] **CERT-01**: MSIX config changed from `store: true` to `store: false` for sideloading
- [x] **CERT-02**: Self-signed certificate generated with correct Publisher CN matching MSIX manifest
- [x] **CERT-03**: Manager installs self-signed cert to `LocalMachine\TrustedPeople` with UAC elevation on Windows
- [x] **CERT-04**: Certificate has a timestamp so packages remain installable after cert expiry

### Go Manager Core (centroidx-manager)

- [x] **MGR-01**: Go + Fyne app compiles to single exe on Windows, Linux, and macOS
- [x] **MGR-02**: Manager fetches available versions from GitHub Releases API
- [x] **MGR-03**: Manager downloads release assets with progress indicator in Fyne UI
- [x] **MGR-04**: Manager verifies download integrity via SHA256 checksum
- [x] **MGR-05**: Manager displays release notes (GitHub Release body) before install
- [x] **MGR-06**: Manager shows clear error messages for network, permission, and checksum failures
- [x] **MGR-07**: Platform-specific installation: `Add-AppxPackage` (Windows), `dpkg -i` (Linux), `hdiutil` mount + copy (macOS)
- [x] **MGR-08**: Manager waits for Flutter app PID to exit before installing (PID-gated install)
- [x] **MGR-09**: Manager relaunches the main app after successful install
- [x] **MGR-10**: Manager extracted from MSIX to `%APPDATA%\centroidx\manager\` on first launch (Windows)

### First-Time Install

- [x] **INST-01**: User downloads standalone manager exe, it fetches and installs the latest main app
- [x] **INST-02**: First-time install flow handles certificate trust (Windows) before app installation
- [x] **INST-03**: First-time install works on all 3 platforms without prerequisites

### Flutter Integration

- [x] **FLT-01**: Custom `UpgraderStore` plugin checks GitHub Releases for new versions
- [x] **FLT-02**: `UpgraderStoreController` registered for Windows, Linux, and macOS
- [x] **FLT-03**: Update prompt shown on app startup when new version available
- [x] **FLT-04**: User confirms update → Flutter app launches bundled manager as detached process, then exits
- [x] **FLT-05**: `microsoft_store_upgrader` package removed from dependencies
- [x] **FLT-06**: Manager exe bundled inside platform packages (MSIX, deb, dmg)
- [x] **FLT-07**: macOS Gatekeeper quarantine attribute removed via `xattr -r -d com.apple.quarantine` before app launch on macOS 15.1+ (no right-click-Open workaround available)

### Version Management & Rollback

- [x] **VER-01**: Manager UI lists all available versions from GitHub Releases
- [x] **VER-02**: User can install any previous version (rollback)
- [x] **VER-03**: Settings page in Flutter app links to manager's version picker
- [x] **VER-04**: Version comparison handles YYYY.MM.DD+build format correctly

### CI/CD & Distribution

- [x] **CI-01**: GitHub Actions builds manager exe for Windows, Linux, macOS using native runners
- [x] **CI-02**: GitHub Actions builds Flutter app for all platforms
- [x] **CI-03**: Tag push creates GitHub Release with all platform artifacts + SHA256SUMS.txt
- [x] **CI-04**: Asset naming follows convention: `centroidx-manager_{os}_{arch}[.ext]`

### Integration Tests

- [x] **TEST-01**: Unit tests for version comparison, GitHub API client, download+verify logic
- [x] **TEST-02**: Integration test: mock HTTP server simulating GitHub Releases API
- [x] **TEST-03**: E2E test: download real asset from GitHub Release and verify checksum
- [x] **TEST-04**: Platform install test: verify install commands execute correctly per platform

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Distribution

- **DIST-01**: Manager self-update capability (update the manager binary itself)
- **DIST-02**: Apple Developer ID notarization for macOS ($99/year)
- **DIST-03**: Microsoft Trusted Signing integration ($9.99/month) for proper code signing
- **DIST-04**: Update channels (stable/beta) via GitHub Release tag filtering

### UX Polish

- **UX-01**: "Remind me later" / "Defer until restart" option on update prompt
- **UX-02**: Automatic rollback if new version crashes on first launch

## Out of Scope

| Feature | Reason |
|---------|--------|
| Microsoft Store distribution | Too slow for update approval cycles — the entire reason for this project |
| Silent/automatic updates | Dangerous for industrial HMI — always require user confirmation |
| Delta/incremental updates | Full package replacement is simpler and packages aren't large |
| Polished/branded manager UI | Fyne defaults are functional; correctness over aesthetics |
| Mobile platform updates | Manager is desktop-only (Windows/Linux/macOS) |
| MDM/group policy enterprise deployment | Internal known users — manager + direct distribution is sufficient |
| Background download without prompt | Wastes bandwidth, violates user consent principle |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CERT-01 | Phase 1 | Complete |
| CERT-02 | Phase 1 | Complete |
| CERT-03 | Phase 1 | Complete |
| CERT-04 | Phase 1 | Complete |
| MGR-01 | Phase 1 | Complete |
| MGR-02 | Phase 2 | Complete |
| MGR-03 | Phase 2 | Complete |
| MGR-04 | Phase 2 | Complete |
| MGR-05 | Phase 2 | Complete |
| MGR-06 | Phase 2 | Complete |
| MGR-07 | Phase 2 | Complete |
| MGR-08 | Phase 2 | Complete |
| MGR-09 | Phase 2 | Complete |
| MGR-10 | Phase 2 | Complete |
| INST-01 | Phase 2 | Complete |
| INST-02 | Phase 2 | Complete |
| INST-03 | Phase 2 | Complete |
| FLT-01 | Phase 3 | Complete |
| FLT-02 | Phase 3 | Complete |
| FLT-03 | Phase 3 | Complete |
| FLT-04 | Phase 3 | Complete |
| FLT-05 | Phase 3 | Complete |
| FLT-06 | Phase 3 | Complete |
| FLT-07 | Phase 3 | Complete |
| VER-01 | Phase 4 | Complete |
| VER-02 | Phase 4 | Complete |
| VER-03 | Phase 4 | Complete |
| VER-04 | Phase 4 | Complete |
| CI-01 | Phase 1 | Complete |
| CI-02 | Phase 1 | Complete |
| CI-03 | Phase 1 | Complete |
| CI-04 | Phase 1 | Complete |
| TEST-01 | Phase 2 | Complete |
| TEST-02 | Phase 2 | Complete |
| TEST-03 | Phase 5 | Complete |
| TEST-04 | Phase 5 | Complete |

**Coverage:**
- v1 requirements: 36 total
- Mapped to phases: 36
- Unmapped: 0

---
*Requirements defined: 2026-03-23*
*Last updated: 2026-03-23 — FLT-07 promoted from v2 UX-03 (macOS Gatekeeper xattr removal is non-deferrable on macOS 15.1+); traceability count corrected to 36*
