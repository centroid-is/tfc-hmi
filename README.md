# CentroidX

Industrial HMI (Human-Machine Interface) for monitoring and controlling automation systems via OPC-UA and MQTT.

## Install

Download the latest release for your platform from the
[GitHub Releases page](https://github.com/centroid-is/tfc-hmi/releases/latest):

| Platform | Artifact |
|----------|----------|
| :apple: **macOS** (Apple Silicon) | `centroidx_darwin_arm64.dmg` |
| :window: **Windows** (x64) | `*.msix` (sideload-signed) |

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
