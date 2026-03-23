# Feature Research

**Domain:** Cross-platform desktop app manager / auto-updater (Go + Fyne, GitHub Releases)
**Researched:** 2026-03-23
**Confidence:** HIGH (for industry patterns), MEDIUM (for Flutter upgrader internals — source not directly inspected)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features every updater provides. Missing any of these means the product feels broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Update available notification | Core job of any updater — app must tell the user when something new exists | LOW | Triggered on app startup via Flutter upgrader plugin; manager is spawned to install |
| User confirmation before install | All credible updaters (Sparkle, WinSparkle, electron-updater) prompt before downloading | LOW | PROJECT.md explicitly requires this — never auto-install without consent |
| Download progress indicator | Users assume a progress bar; absence triggers "is it frozen?" anxiety | MEDIUM | Fyne has progress bar widget; HTTP download with io.TeeReader feeds it |
| Install and relaunch | After install, the managed app restarts automatically | MEDIUM | Requires process management: kill old app, install, launch new; platform differences |
| Version display (current + available) | Users must be able to see what version they have and what they will get | LOW | Read from GitHub Releases API and embedded version constant |
| Release notes / changelog | Sparkle, WinSparkle, and electron-updater all show notes; users expect to see what changed | MEDIUM | GitHub Release body (Markdown) rendered in dialog |
| Error handling with clear messages | "Update failed" with no reason creates support tickets | MEDIUM | Network errors, permission failures, checksum mismatches each need distinct messages |
| Integrity verification (checksum) | Any updater that skips verification is a security liability; industry standard | MEDIUM | SHA256 of downloaded asset verified against sidecar `.sha256` file in GitHub Release |
| First-time install flow | Manager is the install vehicle for new users; must be standalone | HIGH | Downloads main app package, installs it, handles platform packaging (MSIX / deb / dmg) |
| Cross-platform operation | The specific constraint of this project; Windows, Linux, macOS from day one | HIGH | Go + Fyne compiles to single static exe per platform; platform packaging steps differ |

### Differentiators (Competitive Advantage)

Features that go beyond what standard updaters provide and match the specific value of centroidx-manager.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Self-signed certificate trust installation | Removes the single biggest friction for internal Windows deployment; no user needs to run manual PowerShell | HIGH | Windows: `Import-PfxCertificate` into `Cert:\LocalMachine\TrustedPeople` requires UAC elevation; manager handles this once on first install |
| Version picker with rollback | Industrial HMI context — if a new release breaks a production line, operators need one-click revert | HIGH | Lists all GitHub Releases, lets user install any version; replaces the broken version with an older one |
| Version picker accessible from settings in main app | Rollback is only useful if the user can reach it without opening a separate app manager manually | MEDIUM | Flutter app's settings page deep-links into manager's version picker via IPC or URL scheme |
| GitHub Releases as the only distribution channel | Removes Microsoft Store's slow approval cycle; Centroid controls their own release cadence | MEDIUM | GitHub Releases API (`/releases/latest`, `/releases`) is public, free, reliable; already used for CI |
| Custom Flutter UpgraderStore plugin | Leverages the existing `upgrader` package architecture rather than replacing it | MEDIUM | Subclass `UpgraderStore`, override `getVersionInfo()` to call GitHub Releases API; register via `UpgraderStoreController` for Windows/Linux/macOS |
| Single-binary manager (no runtime deps) | Industrial machines are often locked down; no .NET framework, no Node.js, no JVM requirement | LOW | Go compiles to static binary by default; CGO must be disabled or statically linked for Fyne |
| Bundled manager inside MSIX for update-to-update scenarios | Manager can update itself on Windows by being shipped inside the package | MEDIUM | MSIX bundles manager exe; on next update the new MSIX contains a new manager version |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Silent / fully automatic updates | Operators want zero interruption | On an industrial HMI, an unexpected restart or behavior change mid-operation is dangerous; PROJECT.md explicitly prohibits this | Always prompt; offer a "remind me later" or "defer until restart" option |
| Delta / incremental updates | Saves bandwidth on slow connections | Full package replacement is simpler, safer, and reduces the failure modes that need testing; the packages are not large (HMI app is not gigabytes) | Full package replacement with checksum verification |
| Microsoft Store distribution | "Official" channel for Windows | Approval cycles make bug fix turnaround 2–5 days; breaking the value proposition of having a self-managed updater | GitHub Releases only; already decided in PROJECT.md |
| Polished / branded UI | Nice aesthetics | The manager is a utility, not the product; time spent on Fyne theming is time not spent on correctness and testing | Fyne default theme is functional and consistent; ship it |
| Auto-download in background without prompt | Feels fast to the user | Wastes bandwidth on machines that will never be updated (e.g., test rigs), and violates AppImage community best practices (never download without consent) | Download only after user confirms via dialog |
| Multi-user / enterprise deployment tooling (MDM, group policy) | Relevant for large fleets | Out of scope for internal known-user deployment; adds significant complexity | Simple executable + manager handles it; IT distributes the initial exe directly |
| Update channels (stable / beta / nightly) | Power users want early access | Internal product with known users — channel management adds operational complexity without meaningful value | Use GitHub Release tags; if needed in the future, filter by tag prefix (e.g., `beta-*`) |

---

## Feature Dependencies

```
[First-time install]
    └──requires──> [GitHub Releases API: fetch latest release]
    └──requires──> [Asset download with progress]
    └──requires──> [Integrity verification (SHA256)]
    └──requires──> [Platform install step (MSIX/deb/dmg)]
                       └──requires──> [Certificate trust installation] (Windows only)

[Auto-update flow in Flutter app]
    └──requires──> [Custom Flutter UpgraderStore plugin]
                       └──requires──> [GitHub Releases API: compare versions]
    └──requires──> [Manager process launch from Flutter]
    └──requires──> [Manager: download + install + relaunch]
                       └──requires──> [Asset download with progress]
                       └──requires──> [Integrity verification (SHA256)]

[Version picker / rollback]
    └──requires──> [GitHub Releases API: list all releases]
    └──requires──> [Asset download with progress]
    └──requires──> [Integrity verification (SHA256)]
    └──requires──> [Platform install step]

[Settings deep-link to version picker]
    └──requires──> [Version picker / rollback]
    └──requires──> [IPC mechanism between Flutter app and manager]

[Certificate trust installation]
    └──requires──> [UAC elevation request (Windows)]

[Manager self-update]
    └──requires──> [Bundled manager inside MSIX]
    └──enhances──> [Auto-update flow]
```

### Dependency Notes

- **Certificate trust installation requires UAC elevation:** The `Import-PfxCertificate` cmdlet to `LocalMachine\TrustedPeople` requires administrator rights. The manager must either launch elevated (via manifest `requireAdministrator`) or spawn an elevated sub-process for this step only. This is a first-run-only operation.
- **Flutter UpgraderStore plugin requires understanding of `UpgraderStore` interface:** The abstract class requires implementing `getVersionInfo()` which returns an `UpgraderVersionInfo`. The plugin queries `GET /repos/{owner}/{repo}/releases/latest` and maps `tag_name` (the version) and `body` (release notes) to this struct. Registration uses `UpgraderStoreController(onWindows: () => GitHubReleaseStore(...))`.
- **Version picker enhances rollback:** Rollback is just the version picker used to select an older version — same code path, no separate feature needed.
- **IPC mechanism:** Flutter app must signal the manager to open its version picker. Simplest approach is a named socket, a local HTTP endpoint, or a CLI flag (`centroidx-manager --show-version-picker`). CLI flag launched via `Process.run` is lowest complexity.

---

## Flutter `upgrader` UpgraderStore Interface

**Confidence: MEDIUM** — interface shape confirmed from pub.dev documentation and community sources; exact method signatures not read from source.

The `upgrader` package (v11.x, currently at ^11.5.1 per the project's pubspec.yaml) exposes:

```dart
// Abstract base — must be subclassed
abstract class UpgraderStore {
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  });
}

// Controller that maps platform -> store implementation
class UpgraderStoreController {
  const UpgraderStoreController({
    UpgraderStore Function()? onAndroid,
    UpgraderStore Function()? oniOS,
    UpgraderStore Function()? onFuchsia,
    UpgraderStore Function()? onLinux,
    UpgraderStore Function()? onMacOS,
    UpgraderStore Function()? onWeb,
    UpgraderStore Function()? onWindows,
  });
}
```

**Custom GitHub Releases store pattern:**

```dart
class GitHubReleaseStore extends UpgraderStore {
  final String owner;
  final String repo;

  GitHubReleaseStore({required this.owner, required this.repo});

  @override
  Future<UpgraderVersionInfo> getVersionInfo({...}) async {
    // GET https://api.github.com/repos/{owner}/{repo}/releases/latest
    // Extract: tag_name -> appStoreVersion, body -> releaseNotes
    // Return UpgraderVersionInfo with those fields populated
  }
}

// Registration:
Upgrader(
  storeController: UpgraderStoreController(
    onWindows: () => GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi2'),
    onLinux:   () => GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi2'),
    onMacOS:   () => GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi2'),
  ),
)
```

The `UpgraderVersionInfo` struct contains: `appStoreVersion` (the version string from the release tag), `releaseNotes`, `appStoreListingURL`, and `minAppVersion`. The store only provides what version is available — the upgrader package handles the comparison to the installed version and the dialog display.

---

## GitHub Releases API Patterns

**Confidence: HIGH** — official GitHub REST API documentation.

Key endpoints for the manager's version-check logic:

| Endpoint | Use Case | Notes |
|----------|----------|-------|
| `GET /repos/{owner}/{repo}/releases/latest` | Check if update is available | Returns single release object; `tag_name` is the version; `assets[]` contains download URLs |
| `GET /repos/{owner}/{repo}/releases` | Version picker / rollback list | Paginated; `?per_page=30` is practical; filter `prerelease: false` for stable-only |
| `GET /repos/{owner}/{repo}/releases/tags/{tag}` | Install a specific version | Used by rollback when user selects a version from the list |

**Asset fields used by the manager:**

```json
{
  "name": "centroidx-manager-windows-amd64.exe",
  "browser_download_url": "https://github.com/...",
  "size": 12345678,
  "digest": "sha256:abc123..."
}
```

**Asset naming convention** — manager must select the right asset per platform:

- Windows: `*-windows-amd64.msix` or `*-windows-amd64.exe`
- Linux: `*-linux-amd64.deb` or `*-linux-amd64.AppImage`
- macOS: `*-darwin-amd64.dmg`

**Version comparison:** CentroidX uses `YYYY.MM.DD+buildNumber` format. Semantic version comparison by splitting on `.` works; the `+` build number suffix must be stripped for comparison. The `version` Go package or a simple string comparison on the date prefix is sufficient.

---

## Certificate Trust: Platform Specifics

**Confidence: HIGH** — confirmed by Microsoft official docs and community sources.

| Platform | Requirement | Manager Action | Elevation |
|----------|-------------|----------------|-----------|
| Windows | Certificate must be in `LocalMachine\TrustedPeople` for MSIX sideloading; subject must match `Publisher` in manifest | Run `Import-PfxCertificate -CertStoreLocation Cert:\LocalMachine\TrustedPeople` | Required (UAC prompt) |
| Linux | No certificate trust for deb/AppImage installation; no signing required for internal distribution | None | Not required |
| macOS | Requires Developer ID certificate + notarization for Gatekeeper bypass; self-signed will be blocked by default | Either: (a) distribute via Developer ID (Apple paid program), or (b) require users to `xattr -d com.apple.quarantine` | (b) requires manual user step; (a) is the correct long-term path |

**macOS note (MEDIUM confidence):** For internal/known users, instructing them to right-click-Open on first launch bypasses Gatekeeper for non-notarized binaries. The manager cannot automate Gatekeeper bypass; notarization requires Apple Developer Program membership (~$99/year). This is a known constraint.

---

## Integration Testing Standard Patterns

**Confidence: MEDIUM** — industry pattern survey; specific Go+Fyne test tooling not extensively researched.

Standard integration test patterns for updater systems:

| Test Scenario | Approach | Notes |
|---------------|----------|-------|
| Version check returns "update available" | Mock HTTP server or real GitHub Releases with a known test tag | Use `net/http/httptest` in Go for mock; real API for integration |
| Version check returns "up to date" | Same mock, return current installed version | |
| Download + checksum verification | Serve a known file from mock server with matching SHA256 | Verify that bad checksum aborts installation |
| First-time install (happy path) | Staging environment; clean VM or container; real MSIX with test cert | CI matrix with Windows/Linux/macOS runners |
| Rollback to previous version | Install v1, update to v2, roll back to v1; verify running version | Requires two real GitHub Release tags in test repo |
| Certificate installation (Windows) | Requires elevated CI runner or mocked PowerShell cmdlet | Hard to automate fully; smoke test in CI, manual validation for cert trust |
| Process relaunch after update | Verify the manager relaunches the app process with new binary | Check process name / version string after relaunch |

**Recommended test structure for Go:**

- **Unit tests:** GitHub API parsing, version comparison, asset name matching, checksum verification — all testable without network or filesystem
- **Integration tests (with mock HTTP):** Full download-verify-install pipeline against `httptest.Server`
- **E2E tests (CI):** Against a dedicated `test-releases` GitHub repo or pre-tagged releases; run in matrix on Windows/Linux/macOS GitHub Actions runners

---

## MVP Definition

### Launch With (v1)

Minimum set to deliver the stated core value: "seamless one-click update experience, no Store dependency."

- [ ] **Custom Flutter UpgraderStore plugin** — without this, the Flutter app cannot detect updates from GitHub Releases; everything else depends on it
- [ ] **Update available dialog in Flutter app** — the user-facing entry point; triggers manager launch
- [ ] **Manager: download asset with progress** — core mechanical function; must show progress
- [ ] **Manager: SHA256 integrity verification** — non-optional security requirement
- [ ] **Manager: platform install step** — Windows MSIX install, Linux deb install, macOS dmg install
- [ ] **Manager: relaunch app after install** — completes the one-click update loop
- [ ] **Manager: certificate trust installation (Windows)** — without this, MSIX sideloading fails on new machines
- [ ] **Manager: first-time install flow** — the distribution mechanism for new users
- [ ] **GitHub Releases CI pipeline** — creates the releases the manager reads; must exist before manager can be tested end-to-end
- [ ] **Integration tests: update happy path** — required by PROJECT.md; validates the above

### Add After Validation (v1.x)

- [ ] **Version picker / rollback UI** — add once v1 update flow is proven stable; rollback is high-value for industrial users
- [ ] **Settings deep-link from Flutter app** — add alongside version picker; depends on it
- [ ] **Release notes display in update dialog** — low effort, meaningful UX improvement; add in v1.1
- [ ] **Manager self-update** — manager needs updating too; add once the update pipeline is stable

### Future Consideration (v2+)

- [ ] **macOS notarization** — requires Apple Developer Program; defer until macOS deployment is a real priority
- [ ] **Update deferral / scheduling** — "install at midnight" style; defer until users request it
- [ ] **Multi-architecture support (arm64)** — defer until there is an arm64 deployment target

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Custom Flutter UpgraderStore (GitHub) | HIGH | MEDIUM | P1 |
| Asset download with progress | HIGH | LOW | P1 |
| SHA256 verification | HIGH | LOW | P1 |
| Platform install step (MSIX/deb/dmg) | HIGH | HIGH | P1 |
| App relaunch after install | HIGH | MEDIUM | P1 |
| First-time install flow | HIGH | MEDIUM | P1 |
| Certificate trust (Windows) | HIGH | HIGH | P1 |
| Update available dialog in Flutter | HIGH | LOW | P1 |
| GitHub Releases CI pipeline | HIGH | MEDIUM | P1 |
| Integration tests (happy path) | HIGH | MEDIUM | P1 |
| Version picker / rollback | HIGH | MEDIUM | P2 |
| Release notes in dialog | MEDIUM | LOW | P2 |
| Settings deep-link to version picker | MEDIUM | LOW | P2 |
| Manager self-update | MEDIUM | MEDIUM | P2 |
| macOS notarization | LOW (internal) | HIGH | P3 |
| Update scheduling / deferral | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

| Feature | Sparkle (macOS) | electron-updater | WinSparkle | centroidx-manager |
|---------|-----------------|------------------|------------|-------------------|
| Update detection | Appcast XML (RSS) | GitHub/S3/generic HTTP | Appcast XML | GitHub Releases REST API |
| User prompt | Yes (dialog with release notes) | Optional (can be silent) | Yes (dialog) | Yes — mandatory |
| Silent mode | Optional | Default | Optional | No — prohibited |
| Download progress | Yes | Yes (events) | Yes | Yes (Fyne progress bar) |
| Delta updates | No | No (by default) | No | No |
| Rollback | No | Via `allowDowngrade` flag | No | Yes (version picker) |
| Release notes | Yes (HTML in dialog) | Yes | Yes | Yes (GitHub Release body) |
| Checksum verification | Yes (EdDSA signature) | Yes | Yes | Yes (SHA256) |
| Certificate handling | macOS code signing | N/A (web context) | Windows authenticode | Self-signed + auto-trust |
| Channel selection | Yes (appcast filters) | Yes (channels config) | No | No (deferred) |
| First-time install | No (separate installer) | No (separate installer) | No | Yes — primary use case |
| Cross-platform | macOS only | Cross-platform (Electron) | Windows only | Windows + Linux + macOS |

---

## Sources

- [Sparkle framework documentation](https://sparkle-project.org/documentation/) — appcast format, critical updates, channel selection (HIGH confidence)
- [WinSparkle GitHub](https://github.com/vslavik/winsparkle) — Windows Sparkle port, appcast feeds (HIGH confidence)
- [electron-updater auto-update docs](https://www.electron.build/auto-update.html) — events, progress, allowDowngrade (HIGH confidence)
- [upgrader Flutter package — pub.dev](https://pub.dev/packages/upgrader) — UpgraderStore interface, UpgraderStoreController (MEDIUM confidence — interface shape inferred from docs, not source)
- [larryaasen/upgrader GitHub](https://github.com/larryaasen/upgrader) — source reference (MEDIUM confidence)
- [fynelabs/selfupdate](https://github.com/fynelabs/selfupdate) — Go self-update with Fyne integration, scheduling, ed25519 signing (MEDIUM confidence)
- [creativeprojects/go-selfupdate](https://github.com/creativeprojects/go-selfupdate) — GitHub-native Go self-update library (MEDIUM confidence)
- [GitHub REST API: Release assets](https://docs.github.com/en/rest/releases/assets) — asset fields, download URLs, digest (HIGH confidence)
- [Microsoft: Create certificate for MSIX package signing](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing) — PowerShell cert trust workflow (HIGH confidence)
- [Advanced Installer: Install test certificate from MSIX](https://www.advancedinstaller.com/install-test-certificate-from-msix.html) — LocalMachine\TrustedPeople import (MEDIUM confidence)
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Gatekeeper requirements (HIGH confidence)
- [AppImage self-update documentation](https://docs.appimage.org/packaging-guide/optional/updates.html) — Linux update UX patterns including consent requirement (MEDIUM confidence)

---

*Feature research for: centroidx-manager — cross-platform desktop app manager / auto-updater*
*Researched: 2026-03-23*
