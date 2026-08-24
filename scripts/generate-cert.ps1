# generate-cert.ps1
#
# ONE-TIME SCRIPT — Run once locally in elevated PowerShell (Run as Administrator).
# Do NOT run this in CI. Do NOT regenerate the cert unless absolutely necessary.
#
# WARNING: Regenerating this certificate creates a new thumbprint. If the Publisher CN
# in pubspec.yaml (centroid-hmi/pubspec.yaml msix_config.publisher) is anchored to the
# old cert, users CANNOT upgrade from the previous package — they must uninstall and
# reinstall from scratch. The cert is the identity anchor for the entire product lifecycle.
#
# WHY THE SUBJECT IS A NAME AND NOT A GUID:
#   The MSIX publisher must equal this subject exactly, and Windows reads the
#   publisher out on every approval prompt an install or update raises. While it
#   was a GUID, those prompts said "Unknown publisher". A name makes them say
#   Centroid -- but only once the certificate is trusted as a ROOT on the
#   station, which scripts\install-cert.ps1 and the version manager both do.
#
#   The same certificate also signs centroidx-manager.exe. One certificate, two
#   stores: TrustedPeople so Windows accepts the package, Root so it names us.
#
# WHAT THIS SCRIPT DOES:
#   1. Creates a self-signed certificate with Publisher CN matching MSIX manifest
#   2. Exports the PFX (private key) — store securely, never commit to source control
#   3. Exports the CER (public key only) — distribute to target machines for trust
#   4. Removes the certificate from the user store (the PFX has the key now)
#   5. Prints the PFX as base64 for storage as a GitHub Actions secret
#   6. Prints instructions for storing secrets in CI
#
# REQUIRED SECRETS (store in GitHub repository secrets):
#   MSIX_CERT_PFX_BASE64  — base64-encoded content of centroidx-sideload.pfx
#   MSIX_CERT_PASSWORD    — the PFX password you enter when prompted

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExpectedSubject = "CN=Centroid, O=Centroid ehf., C=IS"
$FriendlyName    = "CentroidX Signing Certificate"
$PfxOutputPath   = "centroidx-sideload.pfx"
$CerOutputPath   = "centroidx-sideload.cer"

Write-Host ""
Write-Host "====================================================="
Write-Host "  CentroidX Sideload Certificate Generation"
Write-Host "====================================================="
Write-Host ""
Write-Host "Subject:      $ExpectedSubject"
Write-Host "Friendly Name: $FriendlyName"
Write-Host "Validity:     10 years from today"
Write-Host "EKU:          Code Signing (1.3.6.1.5.5.7.3.3)"
Write-Host ""

# Prompt for PFX password securely (never hardcode)
Write-Host "Enter a strong password for the PFX file."
Write-Host "Store this password as GitHub secret: MSIX_CERT_PASSWORD"
Write-Host ""
$Password = Read-Host -Prompt "PFX Password" -AsSecureString
$PasswordConfirm = Read-Host -Prompt "Confirm Password" -AsSecureString

# Compare passwords
$Pw1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
$Pw2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordConfirm))

if ($Pw1 -ne $Pw2) {
    Write-Error "Passwords do not match. Aborting."
    exit 1
}
if ($Pw1.Length -lt 8) {
    Write-Error "Password must be at least 8 characters. Aborting."
    exit 1
}
# Clear plaintext password from memory
$Pw1 = $null
$Pw2 = $null

Write-Host ""
Write-Host "Step 1: Creating self-signed certificate..."

$cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $ExpectedSubject `
    -KeyUsage DigitalSignature `
    -FriendlyName $FriendlyName `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
    -NotAfter (Get-Date).AddYears(10)

Write-Host "  Thumbprint: $($cert.Thumbprint)"
Write-Host "  Subject:    $($cert.Subject)"
Write-Host "  NotBefore:  $($cert.NotBefore)"
Write-Host "  NotAfter:   $($cert.NotAfter)"

# Verify the Subject matches exactly
if ($cert.Subject -ne $ExpectedSubject) {
    Write-Warning ""
    Write-Warning "!!! SUBJECT MISMATCH DETECTED !!!"
    Write-Warning "Expected: $ExpectedSubject"
    Write-Warning "Got:      $($cert.Subject)"
    Write-Warning ""
    Write-Warning "The certificate Subject does NOT match the Publisher CN in pubspec.yaml."
    Write-Warning "MSIX signing will fail or produce packages that cannot upgrade existing installs."
    Write-Warning "Delete this cert and investigate before proceeding."
    exit 1
}

Write-Host ""
Write-Host "  [OK] Subject matches expected Publisher CN."
Write-Host ""

Write-Host "Step 2: Exporting PFX (includes private key)..."
Export-PfxCertificate `
    -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
    -FilePath $PfxOutputPath `
    -Password $Password | Out-Null
Write-Host "  Exported: $PfxOutputPath"
Write-Host ""

Write-Host "Step 3: Exporting CER (public key only, for distribution)..."
Export-Certificate `
    -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
    -FilePath $CerOutputPath | Out-Null
Write-Host "  Exported: $CerOutputPath"
Write-Host ""

Write-Host "Step 4: Removing the certificate from the user store..."
# The PFX now holds the private key, and this is a RELEASE SIGNING key: leaving a
# second, exportable copy sitting in whoever ran this script's personal store is
# a copy nobody is tracking. The store entry is not needed by anything -- CI signs
# from the PFX secret, stations only ever see the CER.
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
if (Test-Path "Cert:\CurrentUser\My\$($cert.Thumbprint)") {
    Write-Warning "Could not remove the certificate from Cert:\CurrentUser\My."
    Write-Warning "Delete thumbprint $($cert.Thumbprint) by hand: the private key is still there."
} else {
    Write-Host "  Removed from Cert:\CurrentUser\My (the key lives in the PFX now)"
}
Write-Host ""

Write-Host "Step 5: Encoding PFX as base64 for GitHub secret..."
$pfxBytes  = [IO.File]::ReadAllBytes((Resolve-Path $PfxOutputPath))
$pfxBase64 = [Convert]::ToBase64String($pfxBytes)
Write-Host ""
Write-Host "====================================================="
Write-Host "  GITHUB SECRET: MSIX_CERT_PFX_BASE64"
Write-Host "====================================================="
Write-Host $pfxBase64
Write-Host ""
Write-Host "====================================================="
Write-Host "  GITHUB SECRET: MSIX_CERT_PASSWORD"
Write-Host "  (the password you just entered)"
Write-Host "====================================================="
Write-Host ""

Write-Host "====================================================="
Write-Host "  CERTIFICATE SUMMARY"
Write-Host "====================================================="
Write-Host "  Thumbprint:  $($cert.Thumbprint)"
Write-Host "  Subject:     $($cert.Subject)"
Write-Host "  NotAfter:    $($cert.NotAfter)"
Write-Host "  PFX file:    $PfxOutputPath"
Write-Host "  CER file:    $CerOutputPath"
Write-Host ""
Write-Host "  NEXT STEPS:"
Write-Host "  1. Add MSIX_CERT_PFX_BASE64 to GitHub repository secrets"
Write-Host "  2. Add MSIX_CERT_PASSWORD to GitHub repository secrets"
Write-Host "  3. Run scripts\install-cert.ps1 on each target machine"
Write-Host "     to trust this cert (required before MSIX can install)."
Write-Host "     Stations that install through the version manager get this"
Write-Host "     done for them during the approval it already asks for."
Write-Host "  4. NEVER commit $PfxOutputPath to source control"
Write-Host "     (it is already in .gitignore)"
Write-Host "  5. Store the PFX file in a secure location (password manager)"
Write-Host "====================================================="
