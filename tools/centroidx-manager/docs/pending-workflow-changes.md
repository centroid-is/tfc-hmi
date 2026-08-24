# Release changes to apply from a machine with workflow scope

Written 2026-08-24. **Steps 1-3 are DONE (2026-08-24, from the mac):**

- The certificate was minted with openssl (the ps1's cmdlets are
  Windows-only): subject renders `CN=Centroid, O=Centroid ehf., C=IS` byte
  for byte, RSA 2048, 10 years, DigitalSignature + Code Signing EKU, CA:FALSE
  -- the same parameters generate-cert.ps1 asks Windows for. PFX, CER, key
  and password live in `~/centroidx-cert-2026-08-24/` on the mac; move them
  to the password manager.
- `MSIX_CERT_PFX_BASE64` and `MSIX_CERT_PASSWORD` were replaced via
  `gh secret set` at 12:06Z.
- The workflow edits (the windows.yml subject assertion, and signing the
  manager exe in windows.yml and build-manager.yml) are in the same PR that
  updates this file. The exe signing asserts positive evidence with
  Get-AuthenticodeSignature -- signer subject and timestamp -- rather than
  signtool verify, whose chain check fails by design on a runner that has
  not trusted our root.

What remains is the rollout, below.

## Rolling it out

Every station has to be told to update once through the manager. It will:

1. fail the install with 0x80073CF3 (different publisher),
2. save `Packages\<old family>\LocalCache\Roaming`,
3. remove the old package,
4. install the new one,
5. copy the saved data into the new container.

Worth watching the first one rather than sending it to twenty at once. The
station keeps its key mappings and layout; a station that somehow loses them
still has whatever the server holds.

## The real fix, when it is worth paying for

Everything above is self-signed: the name appears on stations that trusted our
root, and SmartScreen still warns the first time a build is downloaded
elsewhere. A code-signing certificate from a public CA (OV, or EV for immediate
SmartScreen reputation) removes both, and the Root import disappears with it.
If CentroidX is ever handed to a customer who installs it themselves, that is
the version to buy.
