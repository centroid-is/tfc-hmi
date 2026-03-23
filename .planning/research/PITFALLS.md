# Pitfalls Research

**Domain:** Cross-platform desktop app manager/updater (Go + Fyne, MSIX sideloading, GitHub Releases)
**Researched:** 2026-03-23
**Confidence:** HIGH (Windows/MSIX) | MEDIUM (macOS Gatekeeper, Fyne cross-compile) | HIGH (GitHub API)

---

## Critical Pitfalls

### Pitfall 1: MSIX Publisher CN Must Exactly Match the Signing Certificate Subject

**What goes wrong:**
The `Publisher` field in the MSIX `AppxManifest.xml` must exactly match the `Subject` field of the signing certificate. If you generate a new self-signed cert (or change the CN), even one character difference causes Windows to refuse installation with a cryptic error: "Certificate doesn't match publisher." More critically, Windows identifies the installed package by `PackageFamilyName = PackageName + Publisher hash`. A publisher mismatch means Windows treats the new package as a *different application*, not an upgrade — both versions install side-by-side rather than upgrading.

**Why it happens:**
The current Flutter MSIX config has `publisher: CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB` (the Store publisher ID). When switching `store: false`, teams often generate a new self-signed cert with a different subject, forgetting the manifest must be updated in lockstep.

**How to avoid:**
- Generate the self-signed certificate first. Record the exact Subject string.
- Set `publisher` in `pubspec.yaml` MSIX config to that exact string before building.
- Keep the certificate Subject (CN) stable for the lifetime of the product — it becomes the identity anchor.
- Store the cert `.pfx` and its password in CI secrets, not regenerated per build.
- When migrating from Store to sideload, the first sideloaded package will be a fresh install, not an upgrade of the Store version. Communicate this to users.

**Warning signs:**
- "Certificate doesn't match publisher" error during `Add-AppxPackage`
- After update, two app entries appear in Apps & Features
- Build log shows publisher string differs between cert and manifest

**Phase to address:** Phase 1 (Foundation / Certificate infrastructure) — get this right before any packaging work.

---

### Pitfall 2: Self-Signed Certificate NOT in LocalMachine\TrustedPeople (vs. CurrentUser)

**What goes wrong:**
MSIX installation requires the signing certificate in the **Local Machine** `TrustedPeople` store, not the Current User store. Installing into the user store causes a confusing install failure even though the cert appears trusted in certmgr. Elevated (`-Scope LocalMachine`) import requires admin rights, and calling `Import-Certificate` without admin silently writes to the user store.

**Why it happens:**
Standard PowerShell `Import-Certificate` defaults to `CurrentUser` unless explicitly told otherwise. Developers test on their own machine (already have admin rights and may have previously imported to LocalMachine), then ship code that imports to the wrong store for other users.

**How to avoid:**
```powershell
# Correct: must specify LocalMachine and require elevation
Import-Certificate -FilePath cert.crt -CertStoreLocation Cert:\LocalMachine\TrustedPeople
```
- The manager must detect it is *not* running elevated, re-launch itself with `runas` verb requesting elevation, then import.
- Test the certificate import path on a clean machine (no existing cert) with a non-admin user account.

**Warning signs:**
- Install works for developer but fails for users on clean machines
- `certmgr.msc` shows cert under "Current User > Trusted People" but not under "Local Computer > Trusted People"
- Error: "The root certificate of the signature is not trusted"

**Phase to address:** Phase 1 (Certificate trust automation) — the entire update flow depends on this.

---

### Pitfall 3: Windows File Locking Prevents Replacing the Running Manager Binary

**What goes wrong:**
On Windows, you cannot write to or delete a running `.exe` file. If the manager tries to update itself (self-update), `os.Rename` / file write to its own path will fail with `Access is denied`. Unlike Linux (where you can unlink an open file), Windows holds an exclusive lock on executing images.

**Why it happens:**
The manager is both the updater and a candidate for self-update. Naive self-update code that writes the new binary directly to `os.Executable()` path will crash at runtime on Windows.

**How to avoid:**
- Use the rename trick: rename the current exe to `centroidx-manager.old`, write the new binary to the original name, then schedule deletion of `.old` on next launch (or use a helper).
- `minio/selfupdate` implements this pattern correctly: it handles the `.old` file remnant that can never be deleted while the process is running — accept that `.old` file will persist until next launch.
- The manager updating the Flutter app (not itself) is simpler — the app is not running during update. Focus complexity on app-update, not self-update.
- For the manager's own updates: the simplest approach is to have the Flutter app launch a new manager version, not the old one updating itself.

**Warning signs:**
- `os.Rename` errors on Windows during update
- Leftover `.old` files in installation directory
- Update appears to succeed but the old binary is still running

**Phase to address:** Phase 2 (Update engine core) — design the update flow before writing any file-replacement code.

---

### Pitfall 4: macOS Sequoia 15.1+ Completely Blocks Unsigned/Unnotarized Apps

**What goes wrong:**
macOS 15.1 (released late 2024) removed the last easy Gatekeeper bypass. Previously, right-click → Open would allow unsigned apps. Sequoia removed this contextual menu option and 15.1 disabled it entirely. Users on macOS 15.1+ will get a blocking dialog with no "Open Anyway" option visible at the app level — they must find it in System Settings → Privacy & Security.

If the `.dmg` or extracted `.app` carries the `com.apple.quarantine` extended attribute (set automatically on anything downloaded from the internet), Gatekeeper will block it unless the app is either:
1. Notarized (requires Apple Developer ID, $99/year)
2. The quarantine xattr is removed manually/programmatically

**Why it happens:**
Teams assume "self-signed + tell users to right-click Open" is a permanent workaround. Apple closed this in Sequoia.

**How to avoid:**
- For internal/known users on controlled machines: the manager can programmatically strip quarantine with `xattr -r -d com.apple.quarantine /Applications/AppName.app` before launching. This is the sanctioned workaround and does not require elevated privileges on macOS.
- The manager itself must also strip its own quarantine on first run.
- Distribute the manager `.dmg` via direct download from GitHub Releases (not email attachment, which doesn't quarantine). The quarantine bit is set by browser download — explicitly document the strip step in install instructions.
- For production scale: budget for Apple Developer ID notarization. At $99/year for a known user base, it is worth it.

**Warning signs:**
- "Apple cannot check this app for malicious software" blocking dialog
- App works on developer machine (already trusted) but not on clean machine
- macOS version is 15.1+

**Phase to address:** Phase 3 (macOS packaging) — cannot be deferred to polish.

---

### Pitfall 5: Fyne Requires CGO — Cross-Compilation Needs Platform-Specific C Toolchains

**What goes wrong:**
Fyne uses CGO for native graphics. `CGO_ENABLED=0` builds do not work. Cross-compiling for Windows from Linux/macOS (or vice versa) requires installing the C cross-compiler for the target platform. This is a CI/CD complexity multiplier: a standard `go build` in GitHub Actions will not produce Windows binaries on an Ubuntu runner without MinGW, and will not produce macOS binaries on any non-macOS runner without the macOS SDK (which requires a macOS runner or Docker with the SDK extracted from Xcode).

**Why it happens:**
Go's standard toolchain supports cross-compilation with `GOOS`/`GOARCH` but only for pure Go code. CGO cross-compilation is not a first-class Go feature and requires manual toolchain setup.

**How to avoid:**
- Use `fyne-cross` Docker images for cross-compilation — they include MinGW (Windows), macOS SDK, and Linux toolchains pre-configured.
- Alternatively: use matrix strategy in GitHub Actions with native runners (ubuntu, windows, macos) — each runner builds for its own platform. This avoids Docker dependency and is simpler to debug. Given GitHub provides all three runner types, this is the recommended approach for this project.
- Zig as a C cross-compiler is an alternative to Docker-based cross-compilation.
- Do NOT use `fyne-cross` with Docker Desktop + virtioFS (known bug as of 2024) — use standard virtualization or native runners instead.

**Warning signs:**
- `CGO_ENABLED=0` in build scripts (Fyne will silently produce a broken binary or fail to link)
- Build pipeline has only one OS runner but builds for all three targets
- `cgo: C compiler "gcc" not found` in CI logs

**Phase to address:** Phase 1 (CI/CD setup) — the build pipeline must be correct before any feature work.

---

### Pitfall 6: MSIX Package Requires `store: false` But Flutter pubspec Default Is Store Mode

**What goes wrong:**
The current Flutter app uses `store: true` in its MSIX config, which tells the build tooling to omit the certificate reference and format the package for Microsoft Store submission. Switching to `store: false` changes the signing requirements, the packaging output (`.msix` vs `.msixupload`), and enables sideloading. If `store: false` is not set before attempting sideload installation, the `.msix` will be packaged incorrectly and installation will fail or refuse to run without Store infrastructure.

**Why it happens:**
The default/existing config targets the Store path. The transition to sideloading requires an explicit config change that is easy to miss in the `pubspec.yaml`.

**How to avoid:**
- Set `store: false` in `pubspec.yaml` MSIX config as the first step.
- Verify the built `.msix` can be installed via `Add-AppxPackage` on a fresh VM before any other work.
- The manager needs to invoke PowerShell's `Add-AppxPackage` with the sideloaded `.msix`, not an MSIX bundle designed for Store.

**Warning signs:**
- `Add-AppxPackage` fails with "The package cannot be installed because it is a store package"
- Build output is `.msixupload` rather than `.msix`
- The installed app does not appear in Apps & Features after `Add-AppxPackage`

**Phase to address:** Phase 1 (Flutter MSIX config migration).

---

### Pitfall 7: GitHub Releases Unauthenticated Rate Limit Is 60 Requests/Hour (Per IP)

**What goes wrong:**
The GitHub REST API returns 60 requests/hour for unauthenticated requests per IP. For a developer running integration tests repeatedly, this limit is hit within minutes. In CI, multiple parallel jobs on the same GitHub-hosted runner network share IP blocks and can collectively exhaust this limit. The error returns HTTP 403 with `X-RateLimit-Remaining: 0` — easy to misread as a permissions error.

**Why it happens:**
Teams assume unauthenticated access is "free" and don't add tokens to the manager's config for release checking. The limit seems generous until tests run.

**How to avoid:**
- The manager must accept a GitHub token (env var or config file) for API calls.
- For public repos, a read-only token with no permissions (`public_repo` scope is not even needed for public release listing) still gives 5,000 requests/hour.
- In integration tests, always use `GITHUB_TOKEN` from CI secrets.
- Cache the latest release check response for at least 5 minutes — do not re-check on every Flutter app startup.
- For private repos: a `repo` scoped token is required even for release asset downloads. Asset download URLs from the Releases API redirect through authenticated CDN, so the token must be passed on the redirect too.

**Warning signs:**
- HTTP 403 from `api.github.com` in logs (not a permissions issue if you see `X-RateLimit-Remaining: 0`)
- Integration tests pass locally but fail in CI
- Rate limit hit during development iteration

**Phase to address:** Phase 2 (GitHub Releases integration) — token auth must be a first-class design decision.

---

### Pitfall 8: Version Format YYYY.MM.DD+buildNumber Is Not Standard SemVer

**What goes wrong:**
The project uses `2026.3.6+1` (Flutter/Dart pubspec format with `+buildNumber`). Standard SemVer treats `+` as build metadata (ignored in comparisons). Go's `golang.org/x/mod/semver` requires a leading `v` and does not parse this format. `Masterminds/semver` will attempt to coerce it but may fail on the `.+` separator. String comparison (`"2026.3.6" < "2026.10.1"`) fails because `"3"` > `"10"` lexicographically.

**Why it happens:**
Dart/Flutter uses a hybrid CalVer+build format. Go libraries for version comparison expect SemVer or require explicit coercion. Naive string comparison works until month numbers exceed single digits.

**How to avoid:**
- Strip the `+buildNumber` suffix before comparison (it is metadata, not part of the version).
- Use `Masterminds/semver/v3` with `NewVersion` (not `StrictNewVersion`) which handles CalVer coercion.
- Parse `YYYY.MM.DD` as `major.minor.patch` after stripping build metadata.
- Test with versions crossing month boundaries: `2026.9.30` vs `2026.10.1` must compare correctly.
- Write unit tests for version comparison before wiring it to the update check.

**Warning signs:**
- Tests with single-digit months pass but double-digit months fail
- Version `2026.10.1` appears "older" than `2026.9.1`
- Build number suffix causes parse errors in version library

**Phase to address:** Phase 2 (Version management) — write tests for this before any comparison logic ships.

---

### Pitfall 9: Race Condition Between Flutter App Exit and Manager Start

**What goes wrong:**
The update flow is: Flutter app receives update notification → user confirms → Flutter app calls manager → Flutter app exits → manager downloads + installs → manager relaunches Flutter app. If the manager launches the new Flutter app before the old instance has fully exited, two instances can run simultaneously — especially on Windows where MSIX prevents installing over a running app. Additionally, if the manager tries to run `Add-AppxPackage` while Flutter's processes are still alive, MSIX will error with "The package is in use."

**Why it happens:**
IPC between Flutter and the manager is typically "fire and forget" — Flutter spawns the manager and exits. There is no guarantee the Flutter process tree (including GPU sub-processes) has fully exited before MSIX runs.

**How to avoid:**
- Manager should wait for the Flutter process PID to exit before starting installation. Pass the Flutter process PID to the manager as a command-line argument: `centroidx-manager --update --wait-pid=12345`.
- Use a timeout: if PID is not dead within 10 seconds, force-kill it (with user's prior confirmation embedded in the "yes, update" action).
- After installation, add a 1-2 second delay before relaunching the app to allow the MSIX framework to settle.
- Test this explicitly: mock a slow-exit Flutter app in integration tests.

**Warning signs:**
- "The package is in use" error from `Add-AppxPackage` in logs
- Two instances of the Flutter app visible in Task Manager post-update
- Update works sometimes but fails intermittently (timing-dependent)

**Phase to address:** Phase 2 (Update orchestration) — the process handoff protocol is architectural, not a detail.

---

### Pitfall 10: Timestamping Omitted from Self-Signed Certificate — Package Becomes Uninstallable After Cert Expires

**What goes wrong:**
Self-signed certificates have a validity period (typically 1-3 years). Without timestamping applied at signing time, when the certificate expires, **existing installed packages can no longer be updated** — Windows refuses to update a package signed with an expired cert. With proper RFC 3161 timestamping, the signature is "frozen in time" — the package remains valid because the timestamp proves it was signed when the cert was valid.

**Why it happens:**
Timestamping requires a public TSA (Timestamp Authority) endpoint. The `signtool.exe` `/tr` flag is optional and easy to forget. Self-signed certs often lack timestamping entirely because TSAs are designed for CA-issued certs.

**How to avoid:**
- Use a public free TSA: `http://timestamp.digicert.com` or `http://timestamp.sectigo.com` — these work with self-signed certs too.
- In CI signing commands:
  ```cmd
  signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f cert.pfx /p password app.msix
  ```
- If the cert is going to be used for 2+ years, set a 5-year validity — within reason, for internal use, longer is better.
- Test cert expiry behavior: create a test cert with a 1-day validity and verify the update flow after it expires.

**Warning signs:**
- Signing command does not include `/tr` flag
- Update flow fails on machines where the cert has expired
- No timestamped signature visible in `signtool verify` output

**Phase to address:** Phase 1 (Certificate infrastructure) — once a package is deployed without timestamping, recovery requires reinstalling from scratch.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode GitHub repo owner/name in binary | No config needed | Must rebuild to change repo | Never — use build-time `ldflags` injection instead |
| Skip certificate pinning on GitHub asset download | Simpler code | MITM vulnerability on enterprise networks with SSL inspection proxies | Never for production |
| Use string comparison for YYYY.MM.DD versions | Quick to write | Breaks when month > 9 | Never — use a version library from day 1 |
| Unauthenticated GitHub API calls | No token management | Rate limited at 60 req/hour | Never — always accept a token even if optional |
| Single `main` package for all platforms | Faster to prototype | Platform-specific code becomes spaghetti | MVP only, refactor before Phase 2 |
| Hardcode PowerShell path `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` | Works on most machines | Breaks on ARM64 Windows or custom installs | Use `exec.LookPath("powershell")` instead |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| GitHub Releases API | Use `GET /releases/latest` which skips pre-releases | Also query `/releases` and filter by semver if pre-releases should be installable |
| GitHub asset download | Download redirect URL directly without token | GitHub asset URLs redirect — must follow redirect with same auth header |
| MSIX `Add-AppxPackage` | Call without `-ForceApplicationShutdown` flag | Add `-ForceApplicationShutdown` to handle edge cases where app didn't fully exit |
| macOS `xattr` removal | Run as user without checking if quarantine bit exists | Check first: `xattr -l /path/app | grep quarantine`; only strip if present |
| Linux `dpkg -i` | Assume `dpkg` is always available | AppImage path requires `chmod +x` and no package manager; deb path requires `dpkg` — branch logic for both |
| Fyne `fyne package` | Produces non-redistributable binary without `fyne bundle` | Use `fyne package` for distribution builds — it handles resource embedding correctly |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Polling GitHub API on every app launch without caching | Rate limit hit after ~60 rapid launches across team | Cache last-check timestamp + result for 5 minutes | Day 1 if multiple devs share an IP |
| Downloading the full release asset before checking hash | Wasted bandwidth on corrupt/tampered download | Download to temp, verify checksum, then move to install path | Anytime network is unreliable |
| Blocking the Fyne UI goroutine during download | UI freezes, appears crashed | Run download in goroutine, report progress via `fyne.CurrentApp().SendNotification` or channel | Every download over ~1 second |
| Extracting entire archive to check version | Slow on large packages | Embed version string in asset filename or companion `.json` asset | Packages > 50MB |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Not verifying downloaded asset checksum against GitHub Releases manifest | Tampered update binary executed with system privileges | Publish SHA256 checksums as release assets; verify before install |
| Self-signed cert private key committed to repo or stored in plaintext | Cert can be extracted and used to sign malicious packages | Store `.pfx` in CI secrets only; never commit key material |
| Manager runs with admin rights for entire session | Privilege escalation surface area | Elevate only for the specific operations that need it (cert import, `Add-AppxPackage`); drop back after |
| Trust GitHub asset URLs without HTTPS verification | Susceptible to SSL stripping in captive portals | Go's `net/http` uses system TLS by default — ensure `InsecureSkipVerify: false` (the default) is never overridden |
| Pass GitHub token in command-line arguments | Token visible in `ps aux` / Task Manager | Pass token via environment variable or config file |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Manager opens full window for every update check | Intrusive; users kill it as "background noise" | Start minimized/tray-only; only surface UI when action is needed |
| No progress indicator during download | User sees frozen manager, assumes it crashed | Show download progress bar with bytes downloaded / total |
| Generic error message on install failure | User can't self-diagnose; support burden increases | Distinguish cert trust errors, space errors, permission errors — each gets a specific message |
| Manager exits without relaunching app on failure | User has no app and no clear recovery path | On failure: show error + "Retry" button + "Open previous version" option |
| Asking for admin elevation without explaining why | Users deny elevation, install fails silently | Show "Administrator permission required to install the security certificate" before triggering UAC |

---

## "Looks Done But Isn't" Checklist

- [ ] **Certificate trust:** Cert is in `LocalMachine\TrustedPeople` — NOT just CurrentUser. Verify on a clean machine.
- [ ] **MSIX publisher match:** `Publisher` in `AppxManifest.xml` exactly matches certificate Subject CN. Verify with `signtool verify /v /pa app.msix`.
- [ ] **Timestamp on signature:** `signtool verify` output shows a countersignature timestamp. Without it, the package expires with the cert.
- [ ] **Version comparison:** Tested with `2026.9.x` vs `2026.10.x` — double-digit months compare correctly.
- [ ] **PID handoff:** Manager waits for Flutter PID to exit before running `Add-AppxPackage`. Test with `sleep` injected into Flutter exit.
- [ ] **Rate limit handling:** Manager shows a user-facing error (not crash) when GitHub API returns 403 rate-limited.
- [ ] **Fyne builds on all three runners:** CI matrix produces binaries for Windows (`amd64`), Linux (`amd64`), macOS (`amd64` + `arm64`). All binaries are smoke-tested (launch and display a window).
- [ ] **macOS quarantine strip:** Manager removes `com.apple.quarantine` from the downloaded `.dmg` contents before launching.
- [ ] **Linux AppImage executable bit:** Manager calls `chmod +x` on the AppImage after download before attempting to run it.
- [ ] **GitHub token absent:** App starts and gracefully degrades (skips update check with a logged warning) when no token is configured — does not crash.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong publisher CN in deployed packages | HIGH | New cert with correct CN + new package = users must uninstall old app and reinstall fresh. No upgrade path exists. |
| Cert deployed without timestamp, now expired | HIGH | Generate new cert, re-sign, but existing users cannot auto-update — must manually reinstall via new standalone installer |
| Unauthenticated API calls hit rate limit in production | LOW | Add token via config update pushed to users via the already-working update mechanism |
| `store: true` packages in wild, now switching to `store: false` | MEDIUM | Ship one-time manual installer; old Store app and new sideloaded app coexist briefly (different PackageFamilyName) |
| Integration tests break due to GitHub rate limiting in CI | LOW | Add `GITHUB_TOKEN` to CI workflow secrets; update test harness to authenticate |
| macOS blocking unnotarized app on Sequoia 15.1+ | MEDIUM | Add `xattr` strip to manager's first-run logic; update install docs; evaluate Apple Developer ID |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Publisher CN / cert mismatch | Phase 1: Certificate Infrastructure | `signtool verify /v /pa app.msix` shows correct publisher; `Add-AppxPackage` works on clean VM |
| Cert not in LocalMachine store | Phase 1: Certificate Infrastructure | Test cert import as non-admin on clean machine; verify `Cert:\LocalMachine\TrustedPeople` |
| store: false Flutter config | Phase 1: Flutter MSIX migration | Sideload `.msix` via PowerShell on a machine without Dev Mode enabled |
| Missing timestamp on signature | Phase 1: Certificate Infrastructure | `signtool verify` output includes countersignature with timestamp |
| Fyne CGO cross-compile CI setup | Phase 1: CI/CD pipeline | All three platform binaries produced by CI; each launches successfully |
| Windows file locking self-update | Phase 2: Update engine core | Integration test: simulate manager updating itself; verify `.old` cleanup |
| PID race condition | Phase 2: Update orchestration | Integration test: inject `sleep` in Flutter exit; verify manager waits |
| GitHub API rate limiting | Phase 2: GitHub Releases integration | Unit test unauthenticated path returns graceful error; CI uses GITHUB_TOKEN |
| Version format YYYY.MM.DD parsing | Phase 2: Version management | Unit tests: 2026.9.x vs 2026.10.x comparison correct; build metadata stripped |
| macOS Sequoia Gatekeeper blocking | Phase 3: macOS packaging | Test on macOS 15.1+ clean machine without Developer Mode; quarantine strip works |
| Linux AppImage chmod | Phase 3: Linux packaging | Integration test: download AppImage to temp dir; chmod; launch succeeds |
| Linux deb vs AppImage branching | Phase 3: Linux packaging | Both install paths tested in CI on Ubuntu and Fedora containers |

---

## Sources

- [Create a certificate for package signing - MSIX | Microsoft Learn](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)
- [App package updates - MSIX | Microsoft Learn](https://learn.microsoft.com/en-us/windows/msix/app-package-updates)
- [Self-Signed Certificate in User Store Causes MSIX Installation Error | Microsoft Community Hub](https://techcommunity.microsoft.com/discussions/msix-discussions/self-signed-certificate-in-user-store-causes-msix-installation-error/4378090)
- [MSIX Code Signing Certificates Part 2 — For IT Pros](https://www.tmurgent.com/TmBlog/?p=2944)
- [What is PackageFamilyName in MSIX and why do I need to know?](https://www.tmurgent.com/TmBlog/?p=3270)
- [Package cannot automatically update when signing certificate has changed · microsoft/msix-packaging#365](https://github.com/microsoft/msix-packaging/issues/365)
- [Compiling for different platforms | Fyne Documentation](https://docs.fyne.io/started/cross-compiling/)
- [fyne-cross GitHub repository](https://github.com/fyne-io/fyne-cross)
- [Cannot build on Mac (arm) using vanilla Docker Desktop · fyne-io/fyne-cross#222](https://github.com/fyne-io/fyne-cross/issues/222)
- [minio/selfupdate — apply.go (Windows rename strategy)](https://github.com/minio/selfupdate/blob/master/apply.go)
- [cmd/go: copy/delete instead of rename on Windows · golang/go#21997](https://github.com/golang/go/issues/21997)
- [Auto restart after self-update — Go Forum](https://forum.golangbridge.org/t/auto-restart-after-self-update/34792)
- [Gatekeeper and runtime protection in macOS — Apple Support](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)
- [macOS 15.1 completely removes ability to launch unsigned applications — OSnews](https://www.osnews.com/story/141055/bug-or-intentional-macos-15-1-completely-removes-ability-to-launch-unsigned-applications/)
- [Notarizing macOS software before distribution | Apple Developer Documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Rate limits for the REST API — GitHub Docs](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
- [Updated rate limits for unauthenticated requests — GitHub Changelog (May 2025)](https://github.blog/changelog/2025-05-08-updated-rate-limits-for-unauthenticated-requests/)
- [Masterminds/semver — Go version comparison library](https://github.com/Masterminds/semver)
- [Code Signing Certificates Drop to 460 Days in 2026 — AppViewX](https://www.appviewx.com/blogs/460-day-code-signing-certificate-2026/)

---

*Pitfalls research for: centroidx-manager — cross-platform desktop app manager/updater*
*Researched: 2026-03-23*
