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
| :apple: **macOS** (Apple Silicon) | [`centroidx_darwin_arm64.dmg`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/centroidx_darwin_arm64.dmg) | Developer ID signed; Gatekeeper may warn if the build was not notarized |
| :window: **Windows** (x64) | [`centroidx_windows_x64.zip`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/centroidx_windows_x64.zip) | Portable `centroidx.exe` + libs, no MSIX |
| :penguin: **Linux** (x64) | [`centroidx_linux_x64.tar.gz`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/centroidx_linux_x64.tar.gz) | Needs GTK 3 and libsecret installed |

Checksums: [`SHA256SUMS.txt`](https://github.com/centroid-is/tfc-hmi/releases/download/main-latest/SHA256SUMS.txt) · All assets: [`main-latest` prerelease](https://github.com/centroid-is/tfc-hmi/releases/tag/main-latest)

> These are development builds with no release testing, replaced on every merge to `main`. They do not auto-update — use the version manager above for production.

## Development

### Prerequisites

- Flutter SDK — the version in [`.flutter-version`](.flutter-version)
- Dart SDK
- For NixOS: install the `mkhl.direnv` VSCode extension and run `direnv allow`

`.flutter-version` is the single source for the Flutter version: every CI
workflow reads it through `.github/actions/setup-flutter`, so nothing hardcodes
a version any more.

Match it locally. The widget tests compare rendered PNGs byte for byte
(`test/**/goldens/`), and different Flutter versions rasterise the same drawing
slightly differently — antialiasing along an edge shifts by a pixel or two.
`test/helpers/golden_tolerance.dart` absorbs a hair of that drift, but a golden
regenerated on a different Flutter than CI's will eventually go red on an image
nobody touched. **Regenerate goldens on the pinned version:**

```sh
# the goldens CI verifies
flutter test --update-goldens
# plus the design-review ones, which carry @Tags(['golden']) and are skipped
# by default in dart_test.yaml
flutter test --update-goldens --run-skipped -t golden
```

Goldens compare only on macOS (`skip: !Platform.isMacOS`).

When a golden fails on CI, the comparator writes the expected/actual/diff PNGs
to a `failures/` directory next to the test; the `flutter-test` job uploads them
as a `golden-failures-<os>` artifact on the run.

### Code generation

```sh
flutter pub run build_runner build
```

### Run

```sh
cd centroid-hmi
flutter run -d macos
```
