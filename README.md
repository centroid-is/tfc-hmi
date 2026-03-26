# CentroidX

Industrial HMI (Human-Machine Interface) for monitoring and controlling automation systems via OPC-UA and MQTT.

## Install

Download the **CentroidX Version Manager** for your platform — it handles installation, updates, and rollback:

| Platform | Download |
|----------|----------|
| :apple: **macOS** (Apple Silicon) | [`centroidx-manager_darwin_arm64`](https://github.com/centroid-is/tfc-hmi/releases/latest/download/centroidx-manager_darwin_arm64) |
| :window: **Windows** (x64) | [`centroidx-manager_windows_amd64.exe`](https://github.com/centroid-is/tfc-hmi/releases/latest/download/centroidx-manager_windows_amd64.exe) |
| :penguin: **Linux** (x64) | [`centroidx-manager_linux_amd64`](https://github.com/centroid-is/tfc-hmi/releases/latest/download/centroidx-manager_linux_amd64) |

Run the manager and it will download and install the latest CentroidX release.

> macOS and Windows binaries are signed and notarized — no Gatekeeper warnings.

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
