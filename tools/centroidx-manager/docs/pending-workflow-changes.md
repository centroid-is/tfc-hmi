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

## 2. Sign the manager exe (SmartScreen "untrusted application")

The MSIX is signed; the manager exe is not, so SmartScreen flags it. After the
Windows build step, with the same PFX secret that signs the MSIX:

    - name: Sign the manager executable
      shell: powershell
      run: |
        $bytes = [Convert]::FromBase64String("${{ secrets.MSIX_CERT_PFX_BASE64 }}")
        [IO.File]::WriteAllBytes("$env:RUNNER_TEMP/sideload.pfx", $bytes)
        & "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe" sign `
          /f "$env:RUNNER_TEMP/sideload.pfx" /p "${{ secrets.MSIX_CERT_PASSWORD }}" `
          /fd SHA256 centroidx-manager_windows_amd64.exe
        Remove-Item "$env:RUNNER_TEMP/sideload.pfx"

(Self-signed, so SmartScreen still shows "unknown publisher" until the cert is
trusted — but no longer "unsigned", and once the sideload cert is in
TrustedPeople the prompt goes quiet. A public-CA code-signing cert is the full
fix, tracked separately.)
