# Release changes to apply from a machine with workflow scope

Written 2026-08-24. The Go and Dart sides are on main; the steps below live in
`.github/workflows/`, which the token on the plant PC cannot push, or need
secrets that PC does not hold.

The goal: approval prompts say **Centroid** instead of **Unknown publisher**.

## Why anything has to change

Windows names a publisher only when the thing being approved is signed and the
signature chains to a trusted root. Two things were in the way:

- the manager exe was not signed at all, and
- our certificate's subject was `CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB`,
  because an MSIX publisher must equal the signing subject exactly. Signing
  with it would only have made the prompt read out the GUID.

So the publisher is now a name. `centroid-hmi/pubspec.yaml` says:

    publisher: CN=Centroid, O=Centroid ehf., C=IS

That changes the package identity, which Windows treats as a different package
sharing a name. Stations cannot upgrade across it -- the old one is removed and
the new one installed. The manager already does exactly that (it is the
0x80073CF3 path it has had for a while) and now saves the station's data across
the removal, because the package container holds the key mappings, the page
layout and the update channel, and `Remove-AppxPackage` deletes it.

## 1. Mint the certificate (once, not in CI)

    cd tfc-hmi
    # elevated PowerShell
    .\scripts\generate-cert.ps1

It now mints `CN=Centroid, O=Centroid ehf., C=IS` and refuses to continue if
the subject does not come out exactly that. Replace the two existing secrets
with the new PFX:

    MSIX_CERT_PFX_BASE64   the base64 the script prints
    MSIX_CERT_PASSWORD     the password entered

Keep the PFX. Signing a later release with a *different* certificate puts every
station back to Unknown until it trusts the new one.

## 2. `windows.yml`: the exported-certificate assertion

Line ~135 checks the subject of the certificate it publishes. Change:

    $expected = "CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB"

to:

    $expected = "CN=Centroid, O=Centroid ehf., C=IS"

Without this the release job fails -- by design: it is the assertion that keeps
us from publishing a certificate nobody can install with.

## 3. Sign the manager exe

`build-manager.yml` (line ~108) and `windows.yml` (line ~58) build it unsigned.
After the Windows build step, with the same secret that signs the MSIX:

    - name: Sign the manager executable
      shell: powershell
      run: |
        $bytes = [Convert]::FromBase64String("${{ secrets.MSIX_CERT_PFX_BASE64 }}")
        [IO.File]::WriteAllBytes("$env:RUNNER_TEMP/signing.pfx", $bytes)
        & "C:\Program Files (x86)\Windows Kitsin.0.22621.0d\signtool.exe" sign `
          /f "$env:RUNNER_TEMP/signing.pfx" /p "${{ secrets.MSIX_CERT_PASSWORD }}" `
          /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
          centroidx-manager_windows_amd64.exe
        Remove-Item "$env:RUNNER_TEMP/signing.pfx"

Windows builds only -- keep the Linux/macOS matrix entries as they are. The
timestamp matters: without it, every signature stops verifying the day the
certificate expires, including on builds already installed.

## 4. Nothing to do for the trust step

The manager imports the published certificate into `LocalMachine\TrustedPeople`
*and* `LocalMachine\Root` in a single elevated run, so the operator approves
once and every prompt after that names Centroid.
`scripts\install-cert.ps1` does the same for a station set up by hand.

## 5. Rolling it out

Every station has to be told to update once through the manager. It will:

1. fail the install with 0x80073CF3 (different publisher),
2. save `Packages\<old family>\LocalCache\Roaming`,
3. remove the old package,
4. install the new one,
5. copy the saved data into the new container.

Worth watching the first one rather than sending it to twenty at once. The
station keeps its key mappings and layout; a station that somehow loses them
still has whatever the server holds.

## 6. The real fix, when it is worth paying for

Everything above is self-signed: the name appears on stations that trusted our
root, and SmartScreen still warns the first time a build is downloaded
elsewhere. A code-signing certificate from a public CA (OV, or EV for immediate
SmartScreen reputation) removes both, and the Root import disappears with it.
If CentroidX is ever handed to a customer who installs it themselves, that is
the version to buy.
