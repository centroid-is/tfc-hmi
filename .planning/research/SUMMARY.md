# Project Research Summary

**Project:** centroidx-manager
**Domain:** Cross-platform desktop app manager / auto-updater (Go + Fyne, MSIX sideloading, GitHub Releases)
**Researched:** 2026-03-23
**Confidence:** MEDIUM-HIGH

## Executive Summary

centroidx-manager is a cross-platform desktop updater for an industrial Flutter HMI application, targeting Windows (MSIX), Linux (deb/AppImage), and macOS (dmg). The recommended pattern is a Go + Fyne binary that acts as an on-demand installer: the Flutter app detects updates via a custom `UpgraderStore` plugin backed by the GitHub Releases API, then spawns the manager as a fully detached process and exits. The manager handles all privileged operations — certificate trust installation, MSIX sideloading, SHA256 verification, and app relaunch — outside the Flutter process. This "fire and forget" handoff is the correct architectural choice because MSIX installation fails if any process from the package family is running; the manager must wait for the Flutter PID to exit before invoking `Add-AppxPackage`.

The two biggest technical risks are Windows-specific and must be resolved before any feature work begins. First: the MSIX `Publisher` CN in `pubspec.yaml` must exactly match the signing certificate Subject — a mismatch makes Windows treat updates as a different application (side-by-side install instead of upgrade), with no migration path once packages are deployed in the wild. Second: switching from `store: true` to `store: false` in the MSIX config is a prerequisite for sideloading; the current pubspec targets Store submission format. Both of these, along with certificate timestamping, define Phase 1 and cannot be deferred. The macOS Gatekeeper constraint (Sequoia 15.1+ requires either notarization or programmatic quarantine removal via `xattr`) is a known per-platform constraint that must be addressed in the macOS packaging phase — right-click-Open as a user workaround is no longer available on current macOS versions.

The recommended stack — Go 1.26, Fyne v2.7.3, go-github/v84 — is well-matched to the requirements. Fyne is the only mature cross-platform Go GUI toolkit that compiles to a static binary with no runtime dependencies, which is critical for locked-down industrial machines. CI should use native runners (windows-latest, ubuntu-latest, macos-latest) rather than Docker-based fyne-cross for packaging steps, since MSIX and macOS .app signing are only supported on native hosts. The full update flow from GitHub Release creation through end-to-end install has well-documented patterns; the main unknowns are in MSIX-specific edge cases and the exact `upgrader` package Dart interface signatures, which should be verified against source before implementation.

## Key Findings

### Recommended Stack

The core stack is Go 1.26 + Fyne v2.7.3 for the manager binary and a custom Dart package implementing the `upgrader` `UpgraderStore` interface for the Flutter side. Fyne requires CGO, which means cross-compilation requires either Docker-based fyne-cross images (recommended for local development) or native GitHub Actions runners per platform (recommended for CI packaging and signing). The standard library `net/http` is sufficient for asset downloads — no extra HTTP library is needed. `github.com/google/go-github/v84` covers all required GitHub Releases API endpoints. `golang.org/x/sys/windows` provides UAC elevation via `ShellExecute` with the `runas` verb.

**Core technologies:**
- Go 1.26.1: Primary language — Green Tea GC, 30% lower CGO overhead vs 1.25, current stable
- fyne.io/fyne/v2 v2.7.3: GUI framework — only mature cross-platform Go GUI toolkit; static binary, no runtime deps
- fyne.io/tools v1.7.0+: Fyne packaging CLI — required for .exe/.app/.appimage output; separate module from fyne v2.5+
- github.com/google/go-github/v84: GitHub Releases API client — official, Google-maintained; covers list/latest/asset endpoints
- golang.org/x/sys: Windows API (UAC elevation, ShellExecute) — standard library extension for Windows-specific calls
- net/http (stdlib): Asset download — custom `io.Reader` wrapper feeds Fyne progress bar; avoids extra dependencies
- Masterminds/semver/v3: Version comparison — handles YYYY.MM.DD CalVer coercion; `StrictNewVersion` must be avoided for this format
- github.com/creativeprojects/go-selfupdate v1.x: Manager self-update — GitHub-native binary replacement with Windows rename trick

**CI approach:** 3 native GitHub Actions runners (windows-latest, ubuntu-latest, macos-latest). Each builds its own platform binary. fyne-cross Docker is local-development only — MSIX and macOS .app signing require native hosts.

### Expected Features

The Flutter `upgrader` package (v11.5.1) already handles update detection and the user prompt dialog. The only Flutter-side work is implementing a custom `UpgraderStore` subclass that queries GitHub Releases instead of the App Store, and a manager launcher that spawns the Go binary as a detached process.

**Must have (table stakes — v1):**
- Custom Flutter `UpgraderStore` plugin (GitHub Releases backend) — entry point; without this Flutter cannot detect updates
- Update available dialog with user confirmation — mandatory; auto-install is explicitly prohibited
- Asset download with progress bar — users expect progress; absence reads as "frozen"
- SHA256 integrity verification — non-optional security requirement before any install
- Platform install step: Windows MSIX via `Add-AppxPackage`, Linux deb via `dpkg -i`, macOS dmg via `hdiutil + cp`
- App relaunch after install — completes the one-click loop
- Certificate trust installation (Windows) — without this MSIX sideloading fails on clean machines
- First-time install flow (standalone manager) — the distribution vehicle for new users
- GitHub Releases CI pipeline — must exist before manager can be tested end-to-end
- Integration tests for the happy-path update flow

**Should have (competitive — v1.x):**
- Version picker / rollback UI — high value for industrial HMI; one-click revert if new version breaks production line
- Release notes display in update dialog — low effort, meaningful UX; GitHub Release body (Markdown) → dialog
- Settings deep-link from Flutter app to version picker — rollback is only accessible if users can reach it
- Manager self-update — manager needs updating too; add once update pipeline is stable

**Defer (v2+):**
- macOS notarization (requires Apple Developer Program, $99/year) — defer until macOS is a real deployment priority
- Update deferral / scheduling ("install at midnight") — defer until users request it
- Multi-architecture arm64 support — defer until there is an arm64 deployment target
- Update channels (stable/beta) — unnecessary complexity for known internal user base

### Architecture Approach

The system uses a two-component model: a Flutter Dart package (`packages/centroidx_upgrader/`) that handles version detection and process handoff, and a Go/Fyne binary (`tools/centroidx-manager/`) that owns all privileged install operations. The Flutter-to-manager communication is strictly one-way CLI args with a detached process spawn — no bidirectional IPC. The manager receives `--update --version=X --wait-pid=Y --asset=Z` and is autonomous after that. Flutter cannot know if the manager succeeded; the design must assume "it worked." On Windows, the manager binary is bundled inside the MSIX package and extracted to `%APPDATA%\centroidx\manager\` on first launch (MSIX installs to a read-only VFS; the manager must live outside it to operate independently).

**Major components:**
1. Flutter `UpgraderStore` (Dart) — queries `GET /releases/latest`, maps `tag_name` + `body` to `UpgraderVersionInfo`; lives in `packages/centroidx_upgrader/`
2. Flutter manager launcher (Dart) — `Process.start(mode: detached)` with `--wait-pid` and `--version` args; extracts bundled manager if not present at `%APPDATA%` path
3. centroidx-manager: Update Engine (Go) — orchestrates check → download → SHA256 verify → platform install → relaunch; lives in `internal/update/`
4. centroidx-manager: Platform Installer (Go) — `Installer` interface with build-tag-isolated implementations in `internal/platform/` (windows.go, linux.go, macos.go); no `runtime.GOOS` switches
5. centroidx-manager: Certificate Trust (Go/Windows) — `Import-Certificate` to `LocalMachine\TrustedPeople`; UAC re-launch via `ShellExecute` runas; lives in `internal/platform/windows_cert.go`
6. centroidx-manager: Version Store (Go) — reads/writes `~/.centroidx/versions.json`; atomic write (temp + rename); rollback snapshots in `~/.centroidx/packages/`
7. centroidx-manager: GitHub Client (Go) — authenticated REST calls; follows redirects with auth header on CDN redirect; SHA256SUMS.txt verification; lives in `internal/github/`
8. centroidx-manager: Fyne GUI (Go) — progress bar, confirm dialog, version picker; all download logic runs in goroutines — never on the Fyne main thread

### Critical Pitfalls

1. **MSIX Publisher CN mismatch** — Generate the self-signed cert first; lock the exact Subject string into `pubspec.yaml` MSIX `publisher` field before building. This becomes the package identity anchor forever — changing it forces users to uninstall and reinstall fresh (no upgrade path).

2. **Certificate in wrong Windows store** — Must be `LocalMachine\TrustedPeople`, not `CurrentUser\TrustedPeople`. Requires admin elevation. PowerShell `Import-Certificate` defaults to CurrentUser without explicit `-CertStoreLocation Cert:\LocalMachine\TrustedPeople`. Test on a clean machine with a non-admin account.

3. **Missing timestamp on self-signed cert signature** — Without RFC 3161 timestamping (`signtool /tr http://timestamp.digicert.com`), the package becomes uninstallable when the cert expires. Recovery requires users to manually reinstall from scratch. Add `/tr` flag to signtool in CI before any package is deployed.

4. **PID race: `Add-AppxPackage` fails if Flutter processes still alive** — Manager must poll for `--wait-pid` to exit before invoking `Add-AppxPackage`. Include `-ForceApplicationShutdown` flag as additional guard. Flutter's GPU sub-processes outlive the main process; a 10-second timeout with force-kill is required.

5. **macOS Sequoia 15.1+ Gatekeeper blocks unnotarized apps with no bypass** — The right-click-Open workaround is gone in macOS 15.1+. The manager must programmatically run `xattr -r -d com.apple.quarantine` on the downloaded `.app` before launch. This must be addressed in the macOS packaging phase — not deferred to polish.

6. **Version format YYYY.MM.DD+buildNumber breaks string comparison at month > 9** — `"2026.9.30"` > `"2026.10.1"` lexicographically but is semantically older. Strip `+buildNumber` suffix; use `Masterminds/semver/v3` `NewVersion` (not `StrictNewVersion`) for coercion. Write unit tests before any comparison logic ships.

7. **GitHub API rate limit 60 req/hour unauthenticated per IP** — Always accept a GitHub token (env var `CENTROIDX_GITHUB_TOKEN` or config file). Cache the latest-release check result for 5 minutes. Integration tests in CI must use `GITHUB_TOKEN` from secrets.

## Implications for Roadmap

Based on the dependency graph from ARCHITECTURE.md and pitfall phase assignments from PITFALLS.md, a 5-phase structure is recommended. Each phase produces a testable artifact before the next begins.

### Phase 1: Foundation — Certificate Infrastructure, MSIX Config, CI Pipeline

**Rationale:** The highest-recovery-cost pitfalls (Publisher CN mismatch, missing cert timestamp, `store: false` migration) must be locked down before any packaging work. CI must also produce valid binaries on all three platforms before feature work can be tested end-to-end. These are correctness and infrastructure concerns with no user-facing deliverable — get them right first.

**Delivers:** A buildable Go + Fyne hello-world binary on all 3 platforms from CI; a `store: false` MSIX that sideloads via `Add-AppxPackage` on a clean VM; a self-signed cert with the correct CN locked into `pubspec.yaml` and signed with an RFC 3161 timestamp; cert imported into `LocalMachine\TrustedPeople` on a clean machine via PowerShell.

**Addresses:** First-time install prerequisite (Windows cert trust); CI pipeline (prerequisite for all further testing)

**Avoids:** Publisher CN mismatch (Pitfall 1), wrong cert store (Pitfall 2), missing timestamp (Pitfall 10), Fyne CGO CI setup (Pitfall 5), `store: false` misconfiguration (Pitfall 6)

**Research flag:** Standard patterns — well-documented by Microsoft and Fyne docs. No additional research needed.

### Phase 2: Core Engine — GitHub Client, Download, Verification, Platform Installer, Version Store

**Rationale:** The update engine is the mechanical core that all user-facing features depend on. It must be correct and tested (unit + mock HTTP) before any Flutter integration is attempted. The PID-wait logic and version comparison must be proven in isolation before being wired to a real install.

**Delivers:** Go package that fetches GitHub Releases metadata, downloads a given asset with progress reporting, verifies SHA256 against `SHA256SUMS.txt`, invokes the platform installer (PowerShell MSIX on Windows, dpkg on Linux, hdiutil+cp on macOS), waits for a given PID to exit, and writes the result to `versions.json`. All logic unit-tested with mock HTTP server (`net/http/httptest`).

**Uses:** go-github/v84, net/http stdlib, golang.org/x/sys (Windows), Masterminds/semver/v3; build-tag-isolated platform files

**Implements:** `internal/github/`, `internal/update/`, `internal/platform/`, `internal/versions/` packages

**Avoids:** Windows file lock self-update (Pitfall 3), PID race condition (Pitfall 9), GitHub rate limiting (Pitfall 7), version format comparison (Pitfall 8)

**Research flag:** PID-wait cross-platform behavior is well-documented. Windows file locking for self-update uses established patterns (`minio/selfupdate` rename trick). No additional research needed.

### Phase 3: Flutter Integration — UpgraderStore Plugin, Manager Launcher, MSIX Embedding

**Rationale:** Flutter integration requires the manager binary to exist and be functional. The custom `UpgraderStore` Dart package is straightforward once the Go side is proven. MSIX embedding (bundling manager inside the Flutter MSIX and extracting to `%APPDATA%` on first launch) is an MSIX-specific pattern that must be implemented and tested on a real device before the end-to-end flow works.

**Delivers:** A working end-to-end update flow: Flutter app detects a new GitHub Release, shows the `UpgradeAlert` dialog, spawns the manager as a detached process with `--wait-pid`, exits, and the manager completes the install and relaunches the app. Tested on Windows with real MSIX. Linux and macOS tested with real deb and dmg.

**Addresses:** Custom Flutter UpgraderStore plugin (P1), Manager launcher in Dart (P1), Update available dialog (P1), App relaunch after install (P1), First-time install flow (P1)

**Implements:** `packages/centroidx_upgrader/` Dart package; manager extraction on first launch

**Avoids:** Flutter downloading the asset (anti-pattern from ARCHITECTURE.md); manager as Windows service (anti-pattern)

**Research flag:** The `UpgraderStore` Dart interface shape (method signatures, `UpgraderVersionInfo` fields) was confirmed from pub.dev docs but not verified from source. Before implementation, read the `larryaasen/upgrader` source to confirm the exact interface. MEDIUM confidence on this interface.

### Phase 4: Platform Packaging — Full Windows / Linux / macOS Install Flows

**Rationale:** Platform packaging details (macOS quarantine stripping, Linux deb vs AppImage branching, MSIX sideload Developer Mode requirements) require platform-specific testing that cannot be done on a CI matrix alone. macOS Gatekeeper on Sequoia 15.1+ is a blocking constraint that must be addressed here, not in polish.

**Delivers:** Full end-to-end install on a clean Windows machine (no Developer Mode, no prior cert trust), a clean Ubuntu machine, and a clean macOS 15.1+ machine. macOS quarantine removal via `xattr` verified. Linux AppImage `chmod +x` path verified alongside deb path. Windows `Add-AppxPackage` with `-ForceApplicationShutdown` verified.

**Addresses:** All P1 platform install steps; macOS Gatekeeper constraint

**Avoids:** macOS Sequoia Gatekeeper blocking (Pitfall 4), Linux AppImage chmod omission, Linux deb vs AppImage branching gap

**Research flag:** macOS Gatekeeper xattr removal is well-documented. macOS packaging for release mode requires a native macos-latest runner — no additional research needed. Consider whether Apple Developer ID ($99/year) is worth budgeting for macOS distribution at this phase.

### Phase 5: Polish — Rollback UI, Manager Self-Update, Settings Deep-Link, Integration Tests

**Rationale:** These are the v1.x features that add significant value but depend on the full update pipeline being stable. Rollback is high-value for the industrial context but is mechanically identical to the update flow (same download + install path, different version selection). Integration tests against real GitHub Releases can only run meaningfully once all platform install paths are proven.

**Delivers:** Version picker UI in Fyne (list all GitHub Releases, restore any version), rollback from `versions.json` + saved package in `~/.centroidx/packages/`, manager self-update via `creativeprojects/go-selfupdate`, Flutter Settings deep-link (`centroidx-manager --version-manager` CLI flag launch), end-to-end integration tests on CI matrix against real GitHub Releases.

**Addresses:** Version picker/rollback (P2), Settings deep-link (P2), Release notes in dialog (P2), Manager self-update (P2), Integration tests (P1 — required by PROJECT.md)

**Avoids:** Fyne UI blocking main goroutine during download (anti-pattern: run in goroutine); hardcoded GitHub token in binary (security mistake)

**Research flag:** Manager self-update on Windows (the binary replacement + `.old` file pattern) is worth a quick spike before committing to `creativeprojects/go-selfupdate` vs `minio/selfupdate`. The rollback UX (how to handle the second install cycle required to restore a previous MSIX) may need a design decision — MSIX rollback is not a file copy, it re-runs `Add-AppxPackage` with the old asset.

### Phase Ordering Rationale

- **Phase 1 before everything**: Publisher CN and cert timestamping have HIGH recovery cost once packages are in the wild. CI pipeline correctness is a prerequisite for testing anything else.
- **Phase 2 before Phase 3**: Flutter integration cannot be tested end-to-end until the Go binary exists and can download/install. Testing the Dart `UpgraderStore` in isolation is possible but not meaningful without the binary.
- **Phase 3 before Phase 4**: Platform packaging edge cases (quarantine strip, AppImage chmod) are validated in the context of the full flow, not in isolation.
- **Phase 5 last**: Rollback, self-update, and integration tests require a stable pipeline. Integration tests that run against real GitHub Releases need all platform paths proven first.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3:** Verify `UpgraderStore` Dart interface method signatures and `UpgraderVersionInfo` field names from `larryaasen/upgrader` source (MEDIUM confidence — confirmed from docs, not source).
- **Phase 5:** Spike manager self-update on Windows to choose between `creativeprojects/go-selfupdate` and `minio/selfupdate`; evaluate MSIX rollback UX (second install cycle vs keeping old package on disk).

Phases with standard patterns (skip research-phase):
- **Phase 1:** Microsoft MSIX cert docs + signtool docs are authoritative and complete.
- **Phase 2:** GitHub Releases API is HIGH confidence; PID-wait and platform installer patterns are well-established.
- **Phase 4:** macOS quarantine xattr removal and Linux dpkg patterns are well-documented.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Go/Fyne versions verified from official sources; CGO CI patterns confirmed by Fyne docs; fyne-cross Docker limitation for release-mode packaging confirmed |
| Features | HIGH (industry patterns) / MEDIUM (Dart interface) | Updater feature landscape is well-understood; `UpgraderStore` interface shape confirmed from pub.dev docs but not verified from source — needs source validation before Phase 3 |
| Architecture | HIGH | Process lifecycle, detached spawn, PID-wait pattern, MSIX VFS/AppData extraction — all well-documented; MSIX embedding pattern has MEDIUM confidence (less common pattern) |
| Pitfalls | HIGH (Windows/MSIX, GitHub API) / MEDIUM (macOS Gatekeeper, fyne-cross) | Windows MSIX pitfalls sourced from official Microsoft docs; macOS Sequoia 15.1 Gatekeeper change confirmed via OSnews + Apple docs |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **UpgraderStore Dart interface:** Read `larryaasen/upgrader` source to confirm exact method signatures and `UpgraderVersionInfo` struct fields before writing the custom store. Docs-only confirmation is insufficient for an interface that drives the update flow.
- **`upgrader` v11.x `onUpdate` callback vs detached process spawn:** Confirm how the `upgrader` package's update confirmation callback works in v11.x — does `onUpdate` replace or supplement the built-in dialog? The architecture assumes Flutter exits after spawning the manager, which requires the callback to call `exit(0)`.
- **MSIX `store: false` + existing installation migration:** When switching from `store: true` packages already distributed to `store: false`, the `PackageFamilyName` changes (different publisher hash). Document the one-time manual reinstall requirement for existing users before any `store: false` packages are released.
- **macOS Apple Developer ID decision:** Budget and timeline for `$99/year` Apple Developer ID should be confirmed by project stakeholders before Phase 4. The `xattr` workaround is functional for internal users but requires documentation and user training.
- **GitHub token distribution strategy:** How will the manager receive its GitHub token on end-user machines? Options: embedded at build time via `ldflags` (acceptable for public repo), config file at `~/.centroidx/config.json`, or environment variable. Decision should be made in Phase 2.

## Sources

### Primary (HIGH confidence)
- [Go 1.26 release blog](https://go.dev/blog/go1.26) — Go version confirmation
- [Fyne cross-compiling docs](https://docs.fyne.io/started/cross-compiling/) — CGO requirements per platform
- [google/go-github releases](https://github.com/google/go-github/releases) — API client version confirmation
- [Add-AppxPackage PowerShell docs](https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage) — MSIX sideload install pattern
- [Create a certificate for package signing — Microsoft Learn](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing) — Publisher CN, cert store, timestamping
- [App package updates — Microsoft Learn](https://learn.microsoft.com/en-us/windows/msix/app-package-updates) — PackageFamilyName identity rules
- [GitHub REST API: Releases](https://docs.github.com/en/rest/releases/releases) — Endpoints and asset fields
- [Rate limits for the REST API — GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) — 60 req/hr unauthenticated
- [Notarizing macOS software — Apple Developer](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Gatekeeper requirements
- [Process.start detached mode — Dart API](https://api.flutter.dev/flutter/dart-io/Process/start.html) — Flutter detached process spawn
- [golang.org/x/sys/windows](https://pkg.go.dev/golang.org/x/sys/windows) — ShellExecute/runas for UAC elevation

### Secondary (MEDIUM confidence)
- [fyne-io/fyne releases](https://github.com/fyne-io/fyne/releases) — v2.7.3 as latest stable
- [fyne-cross GitHub](https://github.com/fyne-io/fyne-cross) — Docker-based cross-compile, native host required for release packaging
- [creativeprojects/go-selfupdate GitHub](https://github.com/creativeprojects/go-selfupdate) — GitHub-native manager self-update
- [upgrader Flutter package — pub.dev](https://pub.dev/packages/upgrader) — UpgraderStore interface shape (needs source validation)
- [MSIX Package Files and VFS — Advanced Installer](https://www.advancedinstaller.com/hub/msix-packaging/package-files-and-vfs.html) — MSIX VFS/AppData extraction pattern
- [Masterminds/semver](https://github.com/Masterminds/semver) — CalVer coercion for YYYY.MM.DD format
- [Self-Signed Certificate in User Store Causes MSIX Installation Error — Microsoft Community Hub](https://techcommunity.microsoft.com/discussions/msix-discussions/self-signed-certificate-in-user-store-causes-msix-installation-error/4378090) — LocalMachine vs CurrentUser cert store

### Tertiary (LOW confidence)
- [macOS 15.1 completely removes ability to launch unsigned applications — OSnews](https://www.osnews.com/story/141055/bug-or-intentional-macos-15-1-completely-removes-ability-to-launch-unsigned-applications/) — Sequoia 15.1 Gatekeeper change (single source; Apple docs confirm notarization requirement)
- go-darwin.dev/hdiutil — Go bindings for macOS hdiutil (limited usage data; stdlib `os/exec` preferred)

---
*Research completed: 2026-03-23*
*Ready for roadmap: yes*
