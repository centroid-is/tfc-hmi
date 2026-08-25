# Handoff: stamp main builds with their own MSIX version

**Status:** ready to apply, blocked only on a token with `workflow` scope.
**Written:** 2026-08-25, from the plant PC (SVN-NES-OT-CL02).

## Why this exists

`tag.yml` rewrites `msix_version` from the tag and commits it. Nothing else
does, so every build from `main` carries **the last stable release's version**.
Two things follow, both hit on the test station today:

1. Installing one main build over another fails with `0x80073CFB`
   ("already installed"). Windows keys a package by identity -- name,
   publisher, version, architecture -- and never by content, so two different
   builds stamped `2026.8.23.1` are the same package to deployment.
2. The version manager reports a main build as the **stable** channel. It reads
   `Get-AppxPackage`, which says `2026.8.23.1`, and that is genuinely the
   stable release's version.

Neither is fixable in the manager: the version really is wrong.

## The change

One step in `.github/workflows/windows.yml`, immediately before
**"Build MSIX (sideload, signed)"**:

```yaml
      - name: Stamp an unstable package version
        if: inputs.ref == ''
        working-directory: centroid-hmi
        shell: bash
        run: |
          MSIX_VERSION="0.$(date -u +%Y).$(date -u +%-m).${{ github.run_number }}"
          sed -i "s/^  msix_version: .*/  msix_version: $MSIX_VERSION/" pubspec.yaml
          echo "stamped msix_version: $MSIX_VERSION"
```

`0.year.month.run_number`, e.g. `0.2026.8.512`.

- the leading zero reads as unstable and sorts **below every stable `2026.x`**,
  so a stable release is always an upgrade from a main build
- `run_number` is monotonic, so main builds order correctly within a month and
  across months and years
- an MSIX version field caps at 65535; the run number reaching that is years away

**`if: inputs.ref == ''` is load-bearing.** `tag.yml` calls this workflow with a
ref and has already committed the tag's version into `pubspec.yaml`; a stable
build must not be restamped. PR and `workflow_dispatch` builds have no ref and
are stamped, which is right -- an MSIX built from a PR should not claim a
release's version either.

**Do not commit the stamp back to main.** `tag.yml` commits its version
deliberately; a prerelease stamp is per-build only.

## Applying it

Ready as a patch (`stamp-unstable-msix-version.patch`, delivered in the session
this branch came from), or just paste the step:

```
git fetch origin
git checkout -b ci/stamp-unstable-version origin/main
git am stamp-unstable-msix-version.patch     # or edit windows.yml by hand
git push -u origin ci/stamp-unstable-version
```

Neither `git push` nor the GitHub Contents API accepts workflow files from the
plant PC's token -- both answer *"refusing to allow a Personal Access Token to
create or update workflow `.github/workflows/windows.yml` without `workflow`
scope"*. That is the only reason this is a handoff rather than a merged change.

## Verifying after it lands

1. The build log shows `stamped msix_version: 0.2026.8.<run>`.
2. `main-latest`'s MSIX carries that version:
   ```powershell
   # after downloading centroidx_windows_amd64.msix
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $z=[IO.Compression.ZipFile]::OpenRead("centroidx_windows_amd64.msix")
   $e=$z.Entries | ? FullName -eq 'AppxManifest.xml'
   ([xml](New-Object IO.StreamReader($e.Open())).ReadToEnd()).Package.Identity.Version
   ```
3. Installing a main build over an older main build succeeds with no uninstall.
4. The manager stops calling a main build "stable".

## What is already done (no action needed)

- **Windows launch crash** (`2da6a0ac`): the app died on every launch without a
  console -- shortcut, Start menu, MSIX tile. The runner called
  `FlutterDesktopResyncOutputStreams()` unconditionally; it reopens `CONOUT$`
  and aborts when there is no console. Now guarded.
- **Empty logs** (#337): on those same launches `hmi.log` was 0 bytes. The
  runner claimed `CENTROID_LOG_REDIRECTED` even when it could not carry Dart's
  output, so the Dart writer stood down and nobody wrote. Now 1.4 MB per run.
- **Publisher** (`5d56e8a4`): MSIX and manager are signed
  `CN=Centroid, O=Centroid ehf., C=IS`. Approval prompts name Centroid once the
  station trusts the certificate, which the manager does in one elevated step
  covering both `TrustedPeople` and `Root`.
- **Refusal messages** (`c24cd69d`): the manager reads the version inside the
  `.msix` and, when Windows would refuse it, says which versions are involved
  and that an uninstall is needed -- instead of an HRESULT. Covers same-version,
  downgrade and rollback.
- **Uninstall keeps the station's configuration** (`453f69c6`, `f6f6fd16`):
  `Remove-AppxPackage` takes the package's data container, which is where key
  mappings, the page layout and the update channel live. Uninstall now puts it
  aside and the next install restores it, with a **Keep settings** checkbox
  (checked by default) for when the settings really should go.

## Known gap, not blocking

On a console-less launch the runner's own C++ line (`[startup] logging to ...`)
still does not reach `hmi.log`; the Dart side does. Measured with both access
masks, so it predates the logging fix.
