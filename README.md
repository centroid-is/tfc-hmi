# CentroidX

Industrial HMI (Human-Machine Interface) for monitoring and controlling automation systems via OPC-UA and MQTT.

## Install

Download the **CentroidX Version Manager** for your platform — it handles installation, updates, and rollback:

| Platform | Download |
|----------|----------|
| :apple: **macOS** (Apple Silicon) | [`centroidx-manager_darwin_arm64.dmg`](https://github.com/centroid-is/tfc-hmi/releases/latest/download/centroidx-manager_darwin_arm64.dmg) |
| :window: **Windows** (x64) | [`centroidx-manager_windows_amd64.exe`](https://github.com/centroid-is/tfc-hmi/releases/latest/download/centroidx-manager_windows_amd64.exe) |
| :penguin: **Linux** (x64) | [`centroidx-manager_linux_amd64`](https://github.com/centroid-is/tfc-hmi/releases/latest/download/centroidx-manager_linux_amd64) |

Run the manager and it will download and install the latest CentroidX release.

> macOS and Windows binaries are signed and notarized — no Gatekeeper warnings.

### Latest `main` build

Unpackaged builds straight from the tip of `main`, rebuilt on every merge. No installer and no version manager — download, unpack, run.

| Platform | Download | Notes |
|----------|----------|-------|
| :apple: **macOS** (Apple Silicon) | [`centroidx_darwin_arm64.dmg`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/centroidx_darwin_arm64.dmg) | Signed and notarized |
| :window: **Windows** (x64) | [`centroidx_windows_x64.zip`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/centroidx_windows_x64.zip) | Portable `centroidx.exe` + libs, no MSIX |
| :penguin: **Linux** (x64) | [`centroidx_linux_x64.tar.gz`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/centroidx_linux_x64.tar.gz) | Needs GTK 3 and libsecret installed |

Checksums: [`SHA256SUMS.txt`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/SHA256SUMS.txt) · All assets: [`main-latest` prerelease](https://github.com/centroid-is/tfc-hmi/releases/tag/main-latest)

> These are development builds with no release testing, replaced on every merge to `main`. They do not auto-update — use the version manager above for production.

## Development

### Prerequisites

- Flutter SDK (stable channel)
- Dart SDK
- For NixOS: install the `mkhl.direnv` VSCode extension and run `direnv allow`

### Code generation

```sh
flutter pub run build_runner build
```

### Run

```sh
cd centroid-hmi
flutter run -d macos
```
