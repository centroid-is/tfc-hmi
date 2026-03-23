# Stack Research

**Domain:** Cross-platform desktop application manager/updater (Go + Fyne GUI)
**Researched:** 2026-03-23
**Confidence:** MEDIUM-HIGH (verified Fyne/Go versions via official sources; some platform-specific patterns verified through docs + community; CGO CI patterns require validation)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Go | 1.26.1 | Primary language | Current stable (Feb 2026); Green Tea GC enabled by default; 30% lower CGO overhead vs 1.25 which matters for Fyne's heavy CGO use |
| fyne.io/fyne/v2 | v2.7.3 | GUI framework | Only mature cross-platform pure-Go-API GUI toolkit that compiles to single binary; system tray, dialogs, progress bars all built in; no webview dependency |
| fyne.io/tools | v1.7.0+ | Fyne CLI (`fyne package`) | Packaging tool for .exe/.app/.appimage output; required for platform-specific bundling |
| github.com/google/go-github/v84 | v84.0.0 | GitHub Releases API | Official Go client; supports Releases API, asset download, version listing; maintained by Google |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| golang.org/x/sys | latest | Windows API calls (UAC elevation, cert store, ShellExecute) | Required for Windows-specific operations: `runas` verb for admin elevation, `CertAddCertificateContextToStore` for cert import |
| github.com/creativeprojects/go-selfupdate | v1.x | Manager self-update (update the updater itself) | Use if you want the manager binary to self-update from GitHub Releases; supports GitHub as source provider |
| fyne.io/systray | latest | System tray icon/menu | Already bundled in fyne v2.2+; use `driver/desktop.App` interface from main Fyne package — do NOT add systray as a separate dep unless you need it standalone |
| net/http (stdlib) | — | Downloading release artifacts (MSIX/deb/dmg) | Use stdlib with a custom `io.Reader` wrapper for progress tracking; avoids extra dependencies |
| fyne.io/fyne/v2/dialog | (part of fyne) | Progress dialogs during download/install | Use `dialog.NewCustomWithoutButtons()` + `widget.NewProgressBar()` — `dialog.NewProgress` is deprecated |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| fyne-cross v1.6.1 | Cross-compile Fyne apps using Docker | Docker-based; uses `fyneio/fyne-cross` images with MinGW (Windows) and macOS SDK; primary cross-compile path |
| GoReleaser v2.14 | Release automation and artifact publishing | Handles multi-platform binary releases to GitHub Releases; CGO cross-compilation requires per-platform native runners or goreleaser-cross Docker image |
| `fyne install` (fyne.io/tools) | Local dev install of packaged app | Use during development to test packaging |
| signtool.exe (Windows SDK) | Sign MSIX packages | Bundled in Windows SDK; required for all MSIX regardless of certificate type |
| Microsoft Trusted Signing | MSIX/EXE signing service | $9.99/month (Basic tier); integrates with signtool and GitHub Actions; alternative to buying OV/EV cert |

## Installation

```bash
# Initialize Go module (run inside tools/centroidx-manager/)
go mod init github.com/centroid/centroidx-manager

# Core GUI framework
go get fyne.io/fyne/v2@v2.7.3

# GitHub API client (for releases listing + asset download URLs)
go get github.com/google/go-github/v84

# Windows/cross-platform syscalls
go get golang.org/x/sys

# Dev tool: Fyne CLI (install globally)
go install fyne.io/tools/cmd/fyne@latest

# Dev tool: fyne-cross (requires Docker)
go install github.com/fyne-io/fyne-cross@latest
```

## Platform-Specific Approach by Operation

### MSIX Installation (Windows)

**Approach:** `os/exec` calling PowerShell with `Add-AppxPackage`.

```go
// Windows-only build tag file: install_windows.go
cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive",
    "-Command", "Add-AppxPackage", "-Path", msixPath)
```

**Signing requirement:** ALL MSIX packages must be signed. For self-signed cert:
1. Create cert: `New-SelfSignedCertificate` (PowerShell) or `makecert.exe`
2. Sign MSIX: `signtool sign /fd SHA256 /a /f cert.pfx /p password app.msix`
3. Import cert on target: Trusted People + Trusted Root stores (requires admin)

**MSIX sideload enablement:** Target machines need "Sideload apps" enabled (Settings > Developer Mode or Group Policy). For internal/known machines, this is acceptable.

### Self-Signed Certificate Trust (Windows)

**Approach:** Combination of PowerShell and `golang.org/x/sys/windows` for admin elevation.

Two-step process:
1. Check if running as admin; if not, re-launch with UAC elevation using `ShellExecute` with `runas` verb via `golang.org/x/sys/windows`
2. Import cert using PowerShell: `Import-Certificate -FilePath cert.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople` (requires elevated process)

```go
// golang.org/x/sys/windows provides ShellExecute for UAC elevation
// Pattern: detect non-admin → re-exec self with runas verb → perform cert import
```

**Note:** Importing to `LocalMachine\Root` (Trusted Root CA) requires admin AND triggers a Windows security dialog even from elevated process. Use `LocalMachine\TrustedPeople` for the signing cert instead — this is sufficient for MSIX sideloading and avoids the extra security prompt.

### Linux Package Installation (.deb)

**Approach:** `os/exec` calling system tools. No Go library needed; shell out to `apt` or `dpkg`.

```bash
# Preferred: apt handles dependencies automatically
sudo apt install -y ./package.deb

# Fallback: dpkg (then fix deps)
sudo dpkg -i package.deb && sudo apt-get install -f -y
```

**Elevation on Linux:** Use `pkexec` (polkit GUI prompt) or `sudo` — `pkexec` is preferred for GUI apps since it shows a graphical password dialog.

```go
cmd := exec.Command("pkexec", "apt", "install", "-y", debPath)
```

**AppImage approach (alternative to .deb):** Download AppImage, `chmod +x`, move to `~/.local/bin/` or `/opt/`. No root required for AppImage unless installing system-wide. For this project, `.deb` is recommended as it integrates with system package management.

### macOS DMG/pkg Installation

**Approach:** `os/exec` calling `hdiutil` + `installer` or `cp`.

```bash
# Step 1: Mount DMG
hdiutil attach app.dmg -nobrowse -quiet

# Step 2a: If .app bundle — copy to /Applications
cp -R /Volumes/AppName/AppName.app /Applications/

# Step 2b: If .pkg inside DMG — use installer
sudo installer -pkg /Volumes/AppName/AppName.pkg -target /

# Step 3: Unmount
hdiutil detach /Volumes/AppName
```

**Elevation on macOS:** Use `osascript` with AppleScript `do shell script ... with administrator privileges` for GUI password prompt, or embed as a privileged helper using SMJobBless (complex but proper).

**Code signing + notarization on macOS:** Required for Gatekeeper to allow installation without "unknown developer" warning. For self-signed/internal distribution:
- Option A: Users right-click > Open to bypass Gatekeeper (acceptable for known internal users)
- Option B: Use `codesign --deep --force --sign -` (ad-hoc signing) to suppress some warnings
- Option C: Apple Developer Program ($99/year) for notarization — recommended before any broader distribution

### Manager Self-Update

**Approach:** `github.com/creativeprojects/go-selfupdate` for the manager updating itself. This handles binary replacement on Windows (where you can't replace a running .exe — it downloads to temp and replaces on next launch via a helper script or on-exit hook).

**For updating the Flutter app (MSIX/deb/dmg):** Use `net/http` stdlib directly to download the artifact, then invoke the platform-specific installer commands above. Do NOT use go-selfupdate for this — it's designed for Go binary replacement only.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| fyne.io/fyne/v2 | Wails (webview-based) | If you need rich web-based UI; Wails uses OS webview so adds runtime dependency and is harder to bundle statically |
| fyne.io/fyne/v2 | gio (Gio) | If you need lower-level control and are comfortable with immediate mode UI; Gio has no CGO but smaller widget set |
| fyne.io/fyne/v2 | walk (Windows-only) | Never — defeats the cross-platform requirement |
| google/go-github/v84 | Raw net/http + JSON | If you want zero extra deps; GitHub API is simple enough — only 2-3 endpoints needed. Acceptable for simple projects. |
| fyne-cross (Docker) | Native CI matrix | If Docker is unavailable in CI; use 3 separate GitHub Actions runners (windows-latest, ubuntu-latest, macos-latest) each building natively — this is actually more reliable for MSIX/pkg packaging steps |
| Microsoft Trusted Signing ($10/mo) | Self-Signed only | For fully internal distribution to controlled machines, self-signed is sufficient; Trusted Signing needed if distributing to any machines you don't control |
| pkexec (Linux elevation) | sudo | If running in a non-desktop environment (headless); sudo works in terminal; pkexec gives GUI prompt |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `dialog.NewProgress` | Deprecated in Fyne v2; will be removed in future version | `dialog.NewCustomWithoutButtons()` + `widget.NewProgressBar()` |
| `fynelabs/selfupdate` | Only supports HTTP sources, not GitHub Releases directly; low activity (v0.1.0, 2022); no MSIX/deb/dmg support | `creativeprojects/go-selfupdate` for manager self-update; plain `net/http` for Flutter app artifact download |
| `rhysd/go-github-selfupdate` | Archived/unmaintained | `creativeprojects/go-selfupdate` |
| fyne-cross for MSIX packaging | MSIX packaging in release mode is "supported only on windows hosts" per fyne-cross docs | Native `windows-latest` runner in GitHub Actions for MSIX signing/packaging step |
| fyne-cross for macOS .app signing | macOS packaging in release mode is "supported only on darwin hosts" | Native `macos-latest` runner in GitHub Actions |
| `LocalMachine\Root` cert store | Triggers extra Windows security warning even from admin; overly broad trust | `LocalMachine\TrustedPeople` is sufficient for MSIX sideloading |
| goreleaser CGO cross-compile via Docker | Very complex setup for Fyne; fyne-cross already does this better with Fyne-specific Docker images | fyne-cross for cross-compile, native runners in CI for packaging/signing steps |
| AppImage for Linux | More complex to build than .deb; requires FUSE on target; no dependency management | .deb package — simpler, standard on Ubuntu/Debian targets |

## Stack Patterns by Variant

**For GitHub Actions CI (recommended pattern):**
- Use 3 separate native runners: `windows-latest`, `ubuntu-latest`, `macos-latest`
- Each runner builds its own platform binary natively (avoids fyne-cross Docker complexity in CI)
- fyne-cross is recommended for LOCAL cross-compilation during development only
- GoReleaser orchestrates artifact collection and GitHub Release creation after all 3 build jobs complete

**For Windows MSIX path:**
- `store: false` in Flutter MSIX config (already noted in PROJECT.md — currently `store: true`)
- Publisher CN must match the signing cert's Subject CN exactly
- Must install cert on target BEFORE installing MSIX, or use `Add-AppxPackage` with `-AllowUnsigned` flag if developer mode is enabled

**For Go module setup (monorepo subfolder):**
```
tools/centroidx-manager/
├── go.mod          # module github.com/centroid/centroidx-manager
├── go.sum
├── main.go
├── internal/
│   ├── updater/    # GitHub Releases fetching, version comparison
│   ├── installer/  # Platform-specific install logic (build tags)
│   └── certmgr/    # Certificate trust installation (Windows)
└── cmd/            # CLI entry point (if needed for headless/test mode)
```

Use Go build tags (`//go:build windows`) to isolate platform-specific code rather than runtime OS detection where possible.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| fyne.io/fyne/v2 v2.7.3 | Go 1.19+ | Works on Go 1.26; v2.6 alpha exists but not stable — stay on v2.7.3 |
| fyne.io/fyne/v2 v2.7.3 | fyne.io/tools v1.7.0+ | CLI tools are now a separate module from fyne v2.5+; install separately |
| google/go-github/v84 | Go 1.21+ | Uses native iterators introduced in v83+; requires Go 1.22+ for range-over-func; verify compatibility |
| golang.org/x/sys | matches Go version | Always use `go get golang.org/x/sys@latest` — it tracks Go releases closely |
| fyne-cross v1.6.1 | Go 1.19+, Docker required | Produces linux/windows/darwin binaries from any host with Docker |
| GoReleaser v2.14 | Go 1.21+ | v2 is current major; use `goreleaser/goreleaser-action@v6` in GitHub Actions |

## CGO Cross-Compilation Deep Dive

Fyne requires CGO because it uses OpenGL (via go-gl) and system font/rendering APIs. This is the most complex aspect of the build setup.

**Option A: Native CI runners (RECOMMENDED)**
Run one GitHub Actions job per platform, each on a native runner. The native runner already has the correct C compiler. No Docker needed. Most reliable approach, especially for packaging steps.

```yaml
strategy:
  matrix:
    include:
      - os: windows-latest
        goos: windows
      - os: ubuntu-latest
        goos: linux
      - os: macos-latest
        goos: darwin
```

**Option B: fyne-cross (local development)**
Uses Docker image `fyneio/fyne-cross` which bundles MinGW (for Windows) and a macOS SDK (for Darwin cross-compile from Linux). Good for local testing of all platforms from one machine.

```bash
fyne-cross windows -arch=amd64
fyne-cross linux -arch=amd64
fyne-cross darwin -arch=amd64   # requires macOS SDK in Docker image
```

**Option C: Zig as C compiler**
Zig can act as a drop-in C cross-compiler for CGO. Less mature for Fyne specifically but works for simpler CGO use cases. LOW confidence for Fyne compatibility.

**Linux CGO dependencies (CI):**
On `ubuntu-latest`, must install before building:
```bash
sudo apt-get install -y gcc libgl1-mesa-dev xorg-dev
```

**macOS CGO dependencies:** Xcode Command Line Tools required. Available on `macos-latest` by default.

**Windows CGO dependencies:** TDM-GCC or MinGW-w64 required. On `windows-latest`, use `winget install mingw` or Chocolatey: `choco install mingw`.

## Code Signing Summary

| Platform | Required? | Tool | Cheap Option |
|----------|-----------|------|--------------|
| Windows MSIX | YES — MSIX won't install unsigned | `signtool.exe` (Windows SDK) | Self-signed for internal; Microsoft Trusted Signing ($9.99/mo) for broader distribution |
| Windows EXE (standalone manager) | No — but SmartScreen will warn | `signtool.exe` | Same cert as MSIX; EV cert ($200-400/yr) for SmartScreen reputation bypass |
| macOS | No — but Gatekeeper blocks unknown | `codesign` + `notarytool` | Ad-hoc signing (`codesign -s -`) for internal; Apple Developer Program ($99/yr) for notarization |
| Linux | No | N/A | N/A |

## Sources

- [fyne-io/fyne releases](https://github.com/fyne-io/fyne/releases) — Confirmed v2.7.3 as latest stable (Feb 21, 2025); MEDIUM confidence (fetched directly)
- [fyne.io/tools pkg.go.dev](https://pkg.go.dev/fyne.io/tools) — Confirmed v1.7.0 published Oct 2025; MEDIUM confidence
- [fyne-cross GitHub](https://github.com/fyne-io/fyne-cross) — Confirmed v1.6.1 (Jan 2025), Docker-based, native host required for release mode packaging; MEDIUM confidence
- [Fyne cross-compiling docs](https://docs.fyne.io/started/cross-compiling/) — CGO requirements per platform; HIGH confidence (official docs)
- [google/go-github releases](https://github.com/google/go-github/releases) — Confirmed v84.0.0 (Feb 27, 2025) as latest; HIGH confidence
- [Go 1.26 release blog](https://go.dev/blog/go1.26) — Go 1.26.1 current stable as of Mar 2026; HIGH confidence
- [GoReleaser CGO docs](https://goreleaser.com/limitations/cgo/) — CGO limitation confirmed, Docker or native runners required; MEDIUM confidence
- [Microsoft Trusted Signing pricing](https://learn.microsoft.com/en-us/answers/questions/2283282/how-to-use-the-trusted-signing-to-code-sign-an-msi) — $9.99/mo Basic tier; MEDIUM confidence
- [Add-AppxPackage PowerShell docs](https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage) — PowerShell silent install pattern; HIGH confidence (official MS docs)
- [creativeprojects/go-selfupdate GitHub](https://github.com/creativeprojects/go-selfupdate) — Supports GitHub Releases, binary replacement; MEDIUM confidence
- go-darwin.dev/hdiutil — Go bindings for macOS hdiutil; LOW confidence (limited usage data)
- golang.org/x/sys/windows — ShellExecute/runas for UAC elevation; HIGH confidence (standard library extension)

---
*Stack research for: centroidx-manager — Go + Fyne cross-platform desktop updater/installer*
*Researched: 2026-03-23*
