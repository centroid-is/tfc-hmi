# Architecture Research

**Domain:** Cross-platform desktop app manager/updater (Go + Fyne, MSIX sideloading, GitHub Releases)
**Researched:** 2026-03-23
**Confidence:** HIGH (process lifecycle, IPC, CI/CD) | MEDIUM (MSIX embedding, self-update)

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER MACHINE                                 │
│                                                                      │
│  ┌─────────────────────────┐     ┌─────────────────────────────┐    │
│  │   Flutter App (centroidx)│     │  centroidx-manager (Go/Fyne) │   │
│  │                         │     │                              │    │
│  │  UpgradeAlert widget     │─────│  Update Engine               │    │
│  │  custom UpgraderStore    │ IPC │  Version Checker             │    │
│  │  (GitHub Releases impl)  │     │  Installer (per-platform)    │    │
│  │                         │     │  Certificate Truster (Win)   │    │
│  └─────────────────────────┘     │  GUI (Fyne)                  │    │
│                                  └──────────────────────────────┘    │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Version Store (~/.centroidx/versions/ or %APPDATA%)         │    │
│  │  versions.json  |  previous/  (rollback copy)                │    │
│  └──────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                              │
                    HTTPS (GitHub API)
                              │
┌─────────────────────────────────────────────────────────────────────┐
│                     GitHub (centroid-is/tfc-hmi2)                    │
│                                                                      │
│  Releases:  v2026.3.6                                                │
│    centroidx-windows-amd64.msix                                      │
│    centroidx-linux-amd64.deb                                         │
│    centroidx-linux-amd64.AppImage                                    │
│    centroidx-macos-amd64.dmg                                         │
│    centroidx-macos-arm64.dmg                                         │
│    centroidx-manager-windows-amd64.exe  (manager self-update)        │
│    centroidx-manager-linux-amd64                                     │
│    centroidx-manager-macos-amd64                                     │
│    centroidx-manager-macos-arm64                                     │
│    SHA256SUMS.txt                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| Flutter `UpgraderStore` (custom) | Check GitHub Releases API for new version; return version metadata to `upgrader` package; delegate install to manager | Dart package in `packages/centroidx_upgrader/` implementing `UpgraderStore` interface |
| Flutter `upgrader` widget | Show update prompt to user; call `onUpdate` callback on confirm | Existing `upgrader: ^11.5.1` package — not replaced, only the store backend changes |
| Flutter→Manager IPC launcher | Spawn manager process with args (`--update --version=X --wait-pid=Y`); detach; exit self | `dart:io Process.start(mode: ProcessStartMode.detached)` — no stdin/stdout connection |
| centroidx-manager: CLI entrypoint | Parse args; route to GUI mode vs headless update mode vs version list mode | `main.go` — arg parsing determines launch mode |
| centroidx-manager: Update Engine | Download asset from GitHub; verify SHA256; invoke platform installer; wait for PID; relaunch app | `internal/update/` — platform-agnostic core |
| centroidx-manager: Platform Installer | Windows: `Add-AppxPackage` via PowerShell; Linux deb: `dpkg -i`; Linux AppImage: `chmod + mv`; macOS: `hdiutil + cp` | `internal/platform/` — one file per platform, build tags |
| centroidx-manager: Certificate Trust | Windows only: `Import-Certificate` to `LocalMachine\TrustedPeople`; re-launch with elevation if needed | `internal/platform/windows_cert.go` |
| centroidx-manager: Version Store | Read/write `versions.json`; record installed versions and asset paths for rollback | `internal/versions/` |
| centroidx-manager: GUI (Fyne) | Progress bar during download; confirm dialog; version picker for rollback; elevation prompt explanation | `internal/ui/` — Fyne widgets |
| centroidx-manager: GitHub Client | REST calls to `/releases`; asset download with token auth; rate limit handling; checksum verification | `internal/github/` |

---

## Recommended Project Structure

```
tools/centroidx-manager/
├── main.go                     # CLI entrypoint: arg parsing, mode routing
├── go.mod
├── go.sum
├── internal/
│   ├── github/
│   │   ├── client.go           # GitHub Releases API: list, latest, asset URLs
│   │   ├── download.go         # Asset download with progress, auth, redirect follow
│   │   └── checksum.go         # SHA256 verification against SHA256SUMS.txt
│   ├── update/
│   │   ├── engine.go           # Orchestrates: check → download → verify → install → relaunch
│   │   ├── version.go          # YYYY.MM.DD+build parsing, comparison (Masterminds/semver)
│   │   └── process.go          # Wait for PID to exit; spawn new process after install
│   ├── platform/
│   │   ├── installer.go        # Interface: Install(assetPath string) error
│   │   ├── windows.go          # Add-AppxPackage via PowerShell; build tag: //go:build windows
│   │   ├── windows_cert.go     # Import-Certificate; UAC re-launch; build tag: //go:build windows
│   │   ├── linux.go            # dpkg -i or chmod+exec AppImage; build tag: //go:build linux
│   │   └── macos.go            # hdiutil attach, cp -r .app, xattr strip; build tag: //go:build darwin
│   ├── versions/
│   │   ├── store.go            # Read/write versions.json in %APPDATA%/centroidx/ or ~/.centroidx/
│   │   └── rollback.go         # Copy previous package asset to versions dir before install
│   └── ui/
│       ├── app.go              # Fyne app init, window management
│       ├── progress.go         # Download progress dialog
│       ├── version_picker.go   # List installed + available versions for rollback UI
│       └── elevation.go        # Explain why UAC prompt appears before triggering
├── cmd/
│   └── selfupdatectl/          # Optional: helper for CI key management (future)
└── testdata/
    └── mock_releases.json      # Fixture for unit tests without hitting GitHub API

packages/centroidx_upgrader/   # Flutter Dart package (custom UpgraderStore)
├── pubspec.yaml
├── lib/
│   ├── centroidx_upgrader.dart # Public API
│   ├── src/
│   │   ├── github_store.dart   # UpgraderStore implementation: queries GitHub Releases
│   │   └── manager_launcher.dart # Launches centroidx-manager via Process.start detached
└── test/
    └── github_store_test.dart
```

### Structure Rationale

- **`internal/platform/`:** Build-tag-isolated platform code. Go's `//go:build` tags ensure Windows-only code (PowerShell, MSIX) never compiles into Linux or macOS binaries. No `runtime.GOOS` switches in hot paths.
- **`internal/github/`:** Isolated from the update engine. Can be unit tested with mock HTTP server. Rate limit handling, token injection, and redirect-follow logic all live here.
- **`internal/versions/`:** Rollback state is separated from the install action. The store writes a record before install begins — if install fails, the record is not yet committed.
- **`packages/centroidx_upgrader/`:** A separate Dart package (not a plugin, no native code) placed in the monorepo `packages/` directory alongside existing `packages/jbtm` and `packages/tfc_dart`. Follows existing monorepo conventions.
- **`internal/ui/`:** All Fyne UI separated from engine logic. The engine takes a progress callback (`func(downloaded, total int64)`), not a direct UI reference.

---

## Architectural Patterns

### Pattern 1: Detached Process Handoff (Flutter → Manager)

**What:** Flutter discovers an update, prompts the user, then spawns the manager as a fully detached process and exits. The manager continues independently.

**When to use:** Any time the updater must replace the running application. The application cannot update itself — it must exit before the installer runs.

**Trade-offs:**
- Pro: Clean separation; manager has no parent process dependency
- Pro: Works across all three platforms identically
- Con: No way to get exit code from detached process (Dart limitation: `StateError` thrown if you access `exitCode` on detached process)
- Con: Flutter cannot know if the manager succeeded — design for "fire and forget"

**Implementation:**
```dart
// In manager_launcher.dart
Future<void> launchManagerForUpdate({
  required String managerPath,
  required String version,
  required int flutterPid,
}) async {
  await Process.start(
    managerPath,
    ['--update', '--version=$version', '--wait-pid=$flutterPid'],
    mode: ProcessStartMode.detached,
    // No stdin/stdout — detached mode prohibits it
  );
  // Flutter exits immediately after this
  exit(0);
}
```

---

### Pattern 2: PID-Gated Installation (Manager waits for app exit)

**What:** The manager receives `--wait-pid=<pid>` on the command line. Before invoking the platform installer, it polls for the PID to no longer exist.

**When to use:** Required on Windows where `Add-AppxPackage` fails with "package is in use" if any process from the MSIX package family is running.

**Trade-offs:**
- Pro: Eliminates race condition between Flutter exit and MSIX install
- Pro: Platform-agnostic (PID polling works on all three OSes)
- Con: If the Flutter process tree hangs, the manager must eventually force-kill it (with user's implicit consent from the update confirmation)

**Implementation:**
```go
// internal/update/process.go
func WaitForPIDExit(pid int, timeout time.Duration) error {
    deadline := time.Now().Add(timeout)
    for time.Now().Before(deadline) {
        process, err := os.FindProcess(pid)
        if err != nil {
            return nil // Process doesn't exist — on Unix, FindProcess never errors
        }
        // On Windows, SendSignal(0) errors when process is gone
        err = process.Signal(syscall.Signal(0))
        if err != nil {
            return nil // Process exited
        }
        time.Sleep(200 * time.Millisecond)
    }
    // Timeout: force kill
    process, _ := os.FindProcess(pid)
    return process.Kill()
}
```

---

### Pattern 3: Pre-Install Rollback Snapshot

**What:** Before overwriting the installed app, the manager saves the current package file (or a reference to it) in the version store. On failure, it can restore.

**When to use:** Any install that replaces a running application. Full rollback requires keeping at minimum one previous version asset on disk.

**Trade-offs:**
- Pro: One-click rollback from the manager's version picker UI
- Pro: Recovery path if new version is broken
- Con: Disk space: one extra MSIX/deb/dmg on disk (typically 50-200MB)
- Con: On Windows, MSIX rollback is not `os.Rename` — it requires `Add-AppxPackage` with the old file, meaning the user goes through a second install cycle

**Version store structure:**
```json
// ~/.centroidx/versions.json
{
  "current": "2026.3.6",
  "history": [
    {
      "version": "2026.3.6",
      "installed_at": "2026-03-23T10:00:00Z",
      "asset_path": "~/.centroidx/packages/centroidx-2026.3.6-windows-amd64.msix"
    },
    {
      "version": "2026.2.14",
      "installed_at": "2026-02-15T09:00:00Z",
      "asset_path": "~/.centroidx/packages/centroidx-2026.2.14-windows-amd64.msix"
    }
  ]
}
```

---

### Pattern 4: Build-Tag Platform Isolation (Go)

**What:** Platform-specific code lives in files with `//go:build windows` (or `linux`, `darwin`) at the top. A common `Installer` interface in `installer.go` is implemented in each platform file.

**When to use:** Any code that calls OS-specific APIs: PowerShell, dpkg, hdiutil, xattr, Import-Certificate, UAC elevation.

**Trade-offs:**
- Pro: No `runtime.GOOS` switch statements; compiler enforces completeness
- Pro: Each platform file is independently testable
- Con: Interface must be stable before splitting; refactoring interface after the fact means touching all platform files simultaneously

**Implementation:**
```go
// internal/platform/installer.go
type Installer interface {
    Install(assetPath string) error
    TrustCertificate(certPath string) error // no-op on Linux/macOS
    LaunchApp(appPath string) error
}

// internal/platform/windows.go  (//go:build windows at top)
type WindowsInstaller struct{}
func (w WindowsInstaller) Install(assetPath string) error {
    // invoke PowerShell Add-AppxPackage -ForceApplicationShutdown
}
```

---

### Pattern 5: Manager Bundled in MSIX via VFS/Custom Install

**What:** The centroidx-manager.exe is included as a file inside the MSIX package. On first launch (or via a Custom Install declaration), the app copies it to `%APPDATA%\centroidx\manager\centroidx-manager.exe` — outside the MSIX VirtualFileSystem — so it can be launched independently and can update itself.

**When to use:** Required because MSIX installs to `C:\Program Files\WindowsApps\` which is read-only and locked to the package. External processes launched from there face path and permission constraints.

**Trade-offs:**
- Pro: Manager travels with the app; users always have a manager if they have the app
- Pro: The Flutter app knows the exact manager path at runtime
- Con: Extraction logic runs on first launch — must be idempotent
- Con: Manager in `%APPDATA%` can be deleted by user; app must re-extract if missing

**Extraction pattern:**
```dart
// In centroidx_upgrader/src/manager_launcher.dart
String resolveManagerPath() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']!;
    return '$appData\\centroidx\\manager\\centroidx-manager.exe';
  } else if (Platform.isLinux) {
    final home = Platform.environment['HOME']!;
    return '$home/.centroidx/manager/centroidx-manager';
  } else { // macOS
    final home = Platform.environment['HOME']!;
    return '$home/.centroidx/manager/centroidx-manager';
  }
}
```

The Flutter app ships a `bundled_manager` asset (binary embedded via `flutter pub run flutter_assets`) and extracts it on startup if not present at the target path.

---

## Data Flow

### Update Flow (Happy Path)

```
Flutter app startup
    │
    ▼
UpgraderStore.getVersionInfo()
    │  → GET api.github.com/repos/centroid-is/tfc-hmi2/releases/latest
    │  ← {tag_name: "2026.4.1", assets: [...]}
    │
    ▼
upgrader widget: current < latest?
    │
    ├─ NO  → silent exit, no UI shown
    │
    └─ YES → show UpgradeAlert dialog to user
                 │
                 ├─ User declines → nothing
                 │
                 └─ User confirms → UpgraderStore.onUpdate()
                          │
                          ▼
                    Dart: extract manager if not present
                          │
                          ▼
                    Dart: Process.start(
                            manager,
                            ['--update', '--version=2026.4.1',
                             '--wait-pid=${pid}',
                             '--asset=centroidx-windows-amd64.msix'],
                            mode: detached
                          )
                          │
                          ▼
                    Dart: exit(0)   ← Flutter app is gone

                    [Manager process takes over]
                          │
                          ▼
                    Manager: WaitForPIDExit(flutterPid, 30s)
                          │
                          ▼
                    Manager: GET asset URL from GitHub Releases
                          │
                          ▼
                    Manager: Download to temp dir (with progress bar)
                          │
                          ▼
                    Manager: Verify SHA256 against SHA256SUMS.txt
                          │
                          ├─ FAIL → show error dialog, offer retry
                          │
                          └─ OK
                                 │
                                 ▼
                          Manager: Copy current package to
                                   ~/.centroidx/packages/ (rollback snapshot)
                                 │
                                 ▼
                          Manager: Platform installer
                            Windows: Add-AppxPackage (needs elevation if not admin)
                            Linux deb: sudo dpkg -i (needs elevation)
                            Linux AppImage: chmod +x, mv to target path
                            macOS: hdiutil attach, cp -r .app, xattr strip
                                 │
                                 ├─ FAIL → show error + "Retry" + "Restore previous"
                                 │
                                 └─ OK
                                         │
                                         ▼
                                  Manager: Update versions.json
                                         │
                                         ▼
                                  Manager: Sleep 1s (MSIX settle time)
                                         │
                                         ▼
                                  Manager: Launch new app
                                         │
                                         ▼
                                  Manager: Exit
```

### First-Time Install Flow (Standalone Manager)

```
User downloads centroidx-manager-windows-amd64.exe
    │
    ▼
Manager starts with no args → GUI mode
    │
    ▼
Manager: GET /releases (list all)
Manager: Show "Install CentroidX" screen with version picker
    │
    ▼
User selects version, clicks Install
    │
    ▼
Manager: Download platform asset + verify SHA256
    │
    ▼
Manager (Windows): Import-Certificate → TrustedPeople (LocalMachine)
    │  triggers UAC elevation if needed
    │
    ▼
Manager: Platform installer
    │
    ▼
Manager: Launch newly installed app
```

### Rollback Flow

```
User opens manager from Flutter app's Settings → "Manage versions"
    │  (Flutter runs: centroidx-manager --version-manager)
    │
    ▼
Manager: Read versions.json → show version list
    │
    ▼
User selects older version, clicks "Restore"
    │
    ▼
Manager: Platform installer with saved package from ~/.centroidx/packages/
    │
    ▼
Manager: Update versions.json current pointer
    │
    ▼
Manager: Launch restored version
```

---

## Component Boundaries (What Talks to What)

| Boundary | Direction | Protocol | Notes |
|----------|-----------|----------|-------|
| Flutter app → Manager | One-way | CLI args + detached process spawn | No return channel. Flutter passes `--version`, `--wait-pid`, `--asset`. Manager is autonomous after spawn. |
| Flutter app → GitHub Releases API | One-way request | HTTPS REST | Only for version check (metadata). No asset download in Flutter. |
| Manager → GitHub Releases API | Two-way | HTTPS REST | Version check + asset download + SHA256SUMS fetch. Must handle auth token + redirects. |
| Manager → Platform Installer | Subprocess call | `exec.Command` / `os/exec` | PowerShell on Windows, dpkg on Linux deb, direct file ops for AppImage and macOS. |
| Manager → Version Store | Read/write | Local filesystem JSON | `~/.centroidx/versions.json`. No network. Atomic write (write temp, rename). |
| Manager → Flutter app (post-install) | One-way | Process spawn | Manager launches new app executable after install completes. |
| CI → GitHub Releases | Push | `gh release create` / `softprops/action-gh-release` | Uploads all platform assets + SHA256SUMS.txt in one release. |

---

## CI/CD Architecture

### Build Pipeline (tag-triggered)

```
git push tag v2026.4.1
        │
        ▼
tag.yml: retag-pubspec job
  - Updates pubspec.yaml version
  - Commits back to main
  - Outputs: commit SHA
        │
        ├──────────────────────────────────────────────────────┐
        ▼                                                      ▼
build-manager.yml (new)                               existing build jobs
  matrix:                                               (MSIX, Docker)
    - os: ubuntu-latest (linux amd64)
    - os: windows-latest (windows amd64)
    - os: macos-latest (macos amd64 + arm64)
  steps:
    - go build -o centroidx-manager-{os}-{arch}
    - upload artifact
        │
        └──────────────────────────────────────────────────────┘
                                        │
                                        ▼
                             create-release.yml (new)
                               needs: [build-manager, windows-build, ...]
                               steps:
                                 - download all artifacts
                                 - generate SHA256SUMS.txt
                                 - gh release create v2026.4.1
                                     --attach centroidx-windows-amd64.msix
                                     --attach centroidx-manager-windows-amd64.exe
                                     --attach centroidx-manager-linux-amd64
                                     --attach centroidx-manager-macos-amd64
                                     --attach centroidx-manager-macos-arm64
                                     --attach SHA256SUMS.txt
```

**Key constraint:** macOS binaries MUST be built on `macos-latest` runner — Fyne requires CGO, and CGO cross-compilation from Linux requires fyne-cross Docker images (which adds complexity). Native runners are simpler.

### Asset Naming Convention

Following `creativeprojects/go-selfupdate` convention for potential future self-update library compatibility:

```
centroidx-manager_{goos}_{goarch}[.exe]
centroidx_{goos}_{goarch}.{pkg_ext}

Examples:
  centroidx-manager_windows_amd64.exe
  centroidx-manager_linux_amd64
  centroidx-manager_darwin_amd64
  centroidx-manager_darwin_arm64
  centroidx_windows_amd64.msix
  centroidx_linux_amd64.deb
  centroidx_linux_amd64.AppImage
  centroidx_darwin_amd64.dmg
  centroidx_darwin_arm64.dmg
  SHA256SUMS.txt
```

The `SHA256SUMS.txt` format:
```
abc123def...  centroidx-manager_windows_amd64.exe
def456abc...  centroidx_windows_amd64.msix
...
```

---

## Embedding Manager in MSIX Package

MSIX installs to `C:\Program Files\WindowsApps\` (read-only, locked). The manager cannot run from there as a standalone updater. The correct pattern:

1. Include `centroidx-manager_windows_amd64.exe` as a file inside the MSIX package (add to Flutter's `windows/` assets or via `pubspec.yaml` assets).
2. On Flutter app startup, check if `%APPDATA%\centroidx\manager\centroidx-manager.exe` exists.
3. If not, copy the bundled manager from the MSIX package path to `%APPDATA%\centroidx\manager\`.
4. The Flutter upgrader plugin always launches from the `%APPDATA%` path.

This is the standard pattern for MSIX sidecars: "install to VirtualFilesystem, extract to AppData on first run."

For Linux and macOS, the manager is distributed as a separate standalone binary and can also be included inside the `.deb` package as a post-install script that places it at `/usr/local/bin/centroidx-manager`.

---

## Scaling Considerations

This is an internal deployment system for a known user base. Scaling is not a concern. The relevant operational limits are:

| Concern | At current scale | Notes |
|---------|------------------|-------|
| GitHub API rate limit | 60 req/hr unauthenticated, 5000/hr authenticated | Always use authenticated token; cache result 5 min |
| Concurrent downloads | N/A — per-user client | Each user's manager downloads independently |
| Release asset storage | GitHub Releases: 2GB/asset, unlimited assets | Well within limits for app packages |
| Manager self-update complexity | Low risk | Manager updates are rare; same pipeline as app updates |

---

## Anti-Patterns

### Anti-Pattern 1: Flutter App Downloads the Update Asset

**What people do:** The Flutter app fetches the release asset URL, downloads it directly, saves to a temp path, then launches the manager with `--install-path=/tmp/centroidx.msix`.

**Why it's wrong:** Flutter's `dart:io` HTTP client will handle the download fine, but the app needs to stay running during a potentially multi-minute download, then still hand off to the manager for elevated install. This keeps Flutter alive longer, increasing the risk of MSIX "package in use" errors. It also duplicates download logic between Flutter and Go.

**Do this instead:** Flutter only checks version availability (lightweight API call). The manager handles all asset downloading. Flutter passes `--version=X --asset=centroidx-windows-amd64.msix` so the manager knows what to fetch.

---

### Anti-Pattern 2: Manager as a Windows Service

**What people do:** Install the manager as a background Windows service that periodically checks for updates and auto-installs.

**Why it's wrong:** Services run as SYSTEM or a service account — not the interactive user. UAC dialogs, user-visible progress UI (Fyne), and interactive confirmation cannot be shown from a service context. Additionally, the requirement is explicit user confirmation before any update.

**Do this instead:** Manager is an on-demand GUI process launched by the Flutter app. It runs in the user's session. No service needed.

---

### Anti-Pattern 3: Single Binary with Runtime `if runtime.GOOS == "windows"` Switches

**What people do:** Put all platform code in one file with `switch runtime.GOOS { case "windows": ... case "linux": ... }`.

**Why it's wrong:** All platform-specific imports (e.g., `golang.org/x/sys/windows`) are compiled into all platforms regardless. The binary size grows; platform-specific imports can cause build failures on cross-platform CI if the import is not build-tagged. Code is harder to test per-platform.

**Do this instead:** Use `//go:build windows` build tags and separate files per platform. The Go toolchain excludes the file entirely on non-matching platforms.

---

### Anti-Pattern 4: Synchronous Download on Fyne Main Thread

**What people do:** Call the download function directly from a Fyne button callback.

**Why it's wrong:** Fyne's UI runs on the main goroutine. Blocking the main goroutine freezes the window entirely — it appears crashed to the user for a multi-MB download.

**Do this instead:** Run the download in a goroutine. Report progress via a channel that the UI polls, or use `fyne.CurrentApp().SendNotification()` for completion. Fyne's `widget.ProgressBar` can be updated from any goroutine via `progressBar.SetValue(v)` which is thread-safe.

---

### Anti-Pattern 5: Storing GitHub Token in Compiled Binary

**What people do:** Hardcode `const githubToken = "ghp_xxx..."` in the Go source.

**Why it's wrong:** The token is extractable with `strings` command on the binary. Anyone with the binary can rate-limit or enumerate the repo with the token.

**Do this instead:** Accept token via env var `CENTROIDX_GITHUB_TOKEN` (read at startup) or a config file at `~/.centroidx/config.json`. For internal deployment, the Flutter app can pass the token to the manager as an argument or via a temp file (not stdin — detached process has no stdin).

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| GitHub Releases API | `GET /repos/{owner}/{repo}/releases/latest` and `/releases` | Authenticated with `Authorization: Bearer {token}`; follow redirects on asset download |
| GitHub asset CDN | Direct HTTPS download from asset URL in releases response | Asset URLs redirect — must follow with same auth header on redirect |

### Internal Boundaries

| Boundary | Communication | Constraint |
|----------|---------------|------------|
| Flutter upgrader plugin ↔ Manager | CLI args (one-shot); detached process | No bidirectional IPC. Flutter cannot query manager state post-launch. Design for "assume it worked." |
| Flutter upgrader plugin ↔ GitHub API | `http` Dart package | Read-only; only metadata (version string + asset names). No downloads in Flutter. |
| Manager ↔ Platform installer tools | `os/exec` subprocess | PowerShell (`powershell.exe`), `dpkg`, `hdiutil` — path resolved via `exec.LookPath`, not hardcoded. |
| Manager ↔ Version store | Local filesystem | Atomic write via temp file + rename. No concurrent writers (one manager runs at a time). |

---

## Suggested Build Order (Dependency Graph)

Phase dependencies flow strictly bottom-up:

```
1. FOUNDATION (no dependencies)
   ├── Go module + Fyne hello-world compiling on all 3 platforms
   ├── CI matrix: windows + linux + macos native runners producing binaries
   ├── Flutter pubspec.yaml: store: false, new publisher CN
   └── Self-signed cert + Import-Certificate trust flow (Windows)

2. CORE ENGINE (depends on: Foundation)
   ├── GitHub client: list releases, fetch metadata, download asset, verify SHA256
   ├── Version parser: YYYY.MM.DD+build → comparable, CalVer ordering
   ├── Platform installer interface + per-platform implementations
   ├── PID-wait logic (cross-platform)
   └── Version store (JSON read/write, rollback snapshot)

3. FLUTTER INTEGRATION (depends on: Core Engine binary exists)
   ├── Custom UpgraderStore Dart package (GitHub Releases backend)
   ├── Manager launcher in Dart (detached Process.start)
   ├── Manager embedding in MSIX + extraction on first launch
   └── Upgrade flow: Flutter detects → prompts → launches manager → exits

4. PLATFORM PACKAGING (depends on: Flutter Integration)
   ├── Windows: full MSIX sideload flow end-to-end
   ├── Linux: deb + AppImage install paths
   └── macOS: dmg install + quarantine strip

5. POLISH (depends on: Platform Packaging)
   ├── Rollback UI in manager (version picker, restore action)
   ├── Self-update of manager binary
   ├── Manager Settings entry point from Flutter app
   └── Integration tests: end-to-end update against real GitHub Releases
```

Each phase produces a testable artifact before the next begins. Do not start Flutter integration before the manager binary can download and install on all three platforms in headless tests.

---

## Sources

- [Firefox In-App Update Process — Mozilla Source Docs](https://firefox-source-docs.mozilla.org/toolkit/mozapps/update/docs/InAppUpdateProcess.html)
- [Electron autoUpdater — Official Docs](https://www.electronjs.org/docs/latest/tutorial/updates)
- [creativeprojects/go-selfupdate — GitHub](https://github.com/creativeprojects/go-selfupdate)
- [fynelabs/selfupdate — GitHub](https://github.com/fynelabs/selfupdate)
- [fynelabs/fyneselfupdate — GitHub](https://github.com/fynelabs/fyneselfupdate)
- [Process class — dart:io library — Dart API](https://api.flutter.dev/flutter/dart-io/Process-class.html)
- [Process.start detached mode — Dart API](https://api.flutter.dev/flutter/dart-io/Process/start.html)
- [upgrader — Flutter package](https://pub.dev/packages/upgrader)
- [larryaasen/upgrader — GitHub (UpgraderStore interface)](https://github.com/larryaasen/upgrader)
- [MSIX Package Files and VFS — Advanced Installer](https://www.advancedinstaller.com/hub/msix-packaging/package-files-and-vfs.html)
- [Package Deployment Install Locations — Advanced Installer](https://www.advancedinstaller.com/hub/msix-packaging/deployment-install-locations.html)
- [GitHub REST API: Releases — GitHub Docs](https://docs.github.com/en/rest/releases/releases)
- [GitHub REST API: Release Assets — GitHub Docs](https://docs.github.com/en/rest/releases/assets)
- [Automating Multi-Platform Releases with GitHub Actions](https://itsfuad.medium.com/automating-multi-platform-releases-with-github-actions-f74de82c76e2)
- [Import-Certificate — Windows PowerShell Admin Elevation](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)
- [Auto-Update Desktop Applications — Whatfix Engineering Blog](https://medium.com/whatfix-techblog/auto-update-desktop-applications-db8fd4cf4936)
- [Architecture of an Intelligent Application Update System — freeCodeCamp](https://www.freecodecamp.org/news/the-architecture-of-an-intelligent-application-update-system-3fc2f27a4a2/)

---

*Architecture research for: centroidx-manager — cross-platform desktop app manager/updater*
*Researched: 2026-03-23*
