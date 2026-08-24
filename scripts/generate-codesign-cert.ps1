# generate-codesign-cert.ps1
#
# Mints the code-signing certificate that makes Windows say "Centroid" instead
# of "Unknown publisher" on the manager's elevation prompt.
#
# WHY A SECOND CERTIFICATE
#   The MSIX is signed by centroidx-sideload.pfx, whose subject has to equal
#   the package publisher exactly (CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB in
#   centroid-hmi/pubspec.yaml). That GUID is what a UAC dialog would show.
#   Changing it would change the package identity, which means every installed
#   station has to uninstall before it can update -- not worth it for a label.
#   So: keep the sideload certificate for the package, add this one for our
#   executables, whose subject can read like a company.
#
# WHAT WINDOWS NEEDS TO SHOW THE NAME
#   1. the executable is signed with this certificate           (CI, see below)
#   2. the certificate chains to a root the machine trusts      (imported once,
#      by the manager's elevated setup step, or by GPO/Intune)
#   Until (2), Windows still says "Unknown publisher" -- self-signed is
#   self-signed. A certificate from a public CA skips (2) entirely and also
#   settles SmartScreen; this script is the free option, not the best one.
#
# DO NOT RUN THIS IN CI. It mints a NEW certificate every time; signing with a
# different certificate than the one stations trust puts you back to Unknown.
# Run it once, store the outputs as secrets, keep the PFX somewhere safe.
#
# USAGE (elevated PowerShell not required):
#   .\generate-codesign-cert.ps1 -Password (Read-Host -AsSecureString)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Subject = "CN=Centroid, O=Centroid ehf., C=IS",

    [Parameter(Mandatory = $false)]
    [string]$OutDir = ".",

    [Parameter(Mandatory = $true)]
    [System.Security.SecureString]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pfxPath = Join-Path $OutDir "centroidx-codesign.pfx"
$cerPath = Join-Path $OutDir "centroidx-codesign.cer"

Write-Host "Subject:  $Subject"
Write-Host "Validity: 10 years from today"
Write-Host "Output:   $pfxPath, $cerPath"
Write-Host ""

# CodeSigningCert type, not Custom: Windows checks the EKU before it will show
# a publisher name for a signature.
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -KeyUsage DigitalSignature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(10)

Write-Host "Created:"
Write-Host "  Subject:    $($cert.Subject)"
Write-Host "  Thumbprint: $($cert.Thumbprint)"
Write-Host "  NotAfter:   $($cert.NotAfter)"

Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $Password | Out-Null
Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null

# The private key stays in the PFX; nothing needs it in the user store.
Remove-Item ("Cert:\CurrentUser\My\" + $cert.Thumbprint) -Force

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))
$b64Path = Join-Path $OutDir "centroidx-codesign.pfx.base64.txt"
Set-Content -LiteralPath $b64Path -Value $b64 -Encoding ascii

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. GitHub secrets (Settings -> Secrets and variables -> Actions):"
Write-Host "       CODESIGN_CERT_PFX_BASE64  = contents of $b64Path"
Write-Host "       CODESIGN_CERT_PASSWORD    = the password you just entered"
Write-Host "  2. Apply the signing step in"
Write-Host "       tools/centroidx-manager/docs/pending-workflow-changes.md"
Write-Host "  3. Publish $cerPath as a release asset named centroidx-codesign.cer"
Write-Host "       (the manager imports it into the machine's trusted roots"
Write-Host "        during the same approval it already asks for)"
Write-Host "  4. Keep $pfxPath somewhere safe. Losing it means a new"
Write-Host "     certificate, and every station is back to Unknown publisher"
Write-Host "     until it trusts the new one."
