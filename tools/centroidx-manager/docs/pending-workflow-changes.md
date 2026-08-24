# Manager build: two workflow changes to apply from a machine with workflow scope

Written 2026-08-24. The Go-side fixes for the failed station install landed in
59300482; these two finish the job but live in `.github/workflows/`, which the
token on the plant PC cannot push.

## 1. No console window (the "PowerShell window" operators see)

The manager is built as a console binary, so launching it opens a console and
every log line lands there. Build it as a GUI app:

In `.github/workflows/build-manager.yml` (the `go build` step) and
`.github/workflows/windows.yml` (the "Build centroidx-manager for Windows"
step), change:

    go build -o centroidx-manager_windows_amd64.exe .

to:

    go build -ldflags="-H windowsgui" -o centroidx-manager_windows_amd64.exe .

Windows builds only — keep the Linux/macOS matrix entries as they are.

## 2. Sign the manager exe so Windows names the publisher

Today the exe is unsigned and every elevation prompt it raises says
**Unknown**. Signing it with the *sideload* certificate would not fix that:
that certificate's subject is `CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB`,
because an MSIX publisher has to equal the signing subject exactly
(`centroid-hmi/pubspec.yaml`), so the prompt would read out the GUID instead.
Changing the package publisher to a name would change the package identity and
every station would have to uninstall before it could update -- too much for a
label.

So: a second certificate, used for our executables only, whose subject can say
Centroid.

### 2a. Mint it once (not in CI)

    cd tfc-hmi
    .\scripts\generate-codesign-cert.ps1 -Password (Read-Host -AsSecureString)

That writes `centroidx-codesign.pfx`, `centroidx-codesign.cer`, and a base64
copy of the PFX. Store the PFX somewhere safe: signing later builds with a
*different* certificate puts every station back to Unknown until it trusts the
new one. Then add two repository secrets:

    CODESIGN_CERT_PFX_BASE64   contents of centroidx-codesign.pfx.base64.txt
    CODESIGN_CERT_PASSWORD     the password used above

### 2b. Sign, in `build-manager.yml` and `windows.yml`

After the Windows `go build` step:

    - name: Sign the manager executable
      shell: powershell
      run: |
        $bytes = [Convert]::FromBase64String("${{ secrets.CODESIGN_CERT_PFX_BASE64 }}")
        [IO.File]::WriteAllBytes("$env:RUNNER_TEMP/codesign.pfx", $bytes)
        & "C:\Program Files (x86)\Windows Kitsin.0.22621.0d\signtool.exe" sign `
          /f "$env:RUNNER_TEMP/codesign.pfx" /p "${{ secrets.CODESIGN_CERT_PASSWORD }}" `
          /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
          centroidx-manager_windows_amd64.exe
        Remove-Item "$env:RUNNER_TEMP/codesign.pfx"

The timestamp matters: without it every signature stops verifying the day the
certificate expires, including on builds already installed.

### 2c. Publish the public half as a release asset

Upload `centroidx-codesign.cer` next to the MSIX and `centroidx-sideload.cer`,
**named so it contains `codesign`** -- that substring is how the manager tells
the two certificates apart (`downloadCodesignAsset` in
`internal/update/engine.go`).

The manager side is already in place: during an install it imports that asset
into `Cert:\LocalMachine\Root` in the same elevated step it already uses for
the package certificate, so the operator is asked once. From then on the
prompt reads **Centroid** instead of **Unknown**.

## 3. The real fix, when it is worth paying for

Everything above is self-signed: the name only appears on stations that have
imported our root, and SmartScreen still warns the first time a build is
downloaded anywhere else. A code-signing certificate from a public CA (OV, or
EV for immediate SmartScreen reputation) removes both, with no root imports
and no trust step at all -- 2a and 2c disappear, 2b just uses the purchased
PFX. If CentroidX is ever handed to a customer who installs it themselves,
that is the version to buy.
