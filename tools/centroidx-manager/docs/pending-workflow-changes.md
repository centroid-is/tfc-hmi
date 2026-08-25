# Release changes to apply from a machine with workflow scope

Written 2026-08-24. **Steps 1-3 are DONE (2026-08-24, from the mac):**

- The certificate was minted with openssl (the ps1's cmdlets are
  Windows-only): subject renders `CN=Centroid, O=Centroid ehf., C=IS` byte
  for byte, RSA 2048, 10 years, DigitalSignature + Code Signing EKU, CA:FALSE
  -- the same parameters generate-cert.ps1 asks Windows for. PFX, CER, key
  and password live in `~/centroidx-cert-2026-08-24/` on the mac; move them
  to the password manager.
- **If it is ever re-minted with openssl: `string_mask = pkix` is
  load-bearing.** The appx signer compares the manifest publisher and the
  certificate subject at the DER level. OpenSSL 3 defaults to UTF8String;
  Windows encodes the same ASCII as PrintableString, so the first mint
  failed `msix:create` with `SignerSign() ... 0x8007000B` while every
  string *looked* identical. generate-cert.ps1 never hits this because
  Windows encodes both sides.
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

## 7. Deferred: give main-latest builds their own version

Not decided yet -- parked 2026-08-25.

`tag.yml` rewrites `msix_version` from the tag and commits it, but
`main-prerelease.yml` builds straight from whatever `pubspec.yaml` says. So
every main build carries the *last stable release's* number. Two symptoms,
both seen on the test station:

- the version manager reports a main build as the stable channel -- it is
  reading `Get-AppxPackage`, which says `2026.8.23.1`, and that is genuinely
  the stable release's version
- installing one main build over another fails with 0x80073CFB
  (ERROR_PACKAGE_ALREADY_EXISTS), because the version did not change

An MSIX `Identity Version` is four numbers, 0-65535 each, so a label like
"unstable" cannot go in it; the release name carries that. Jon's preference is
a leading zero, which also sorts every main build below every stable release.
Two shapes fit:

    MSIX_VERSION="0.$(date -u +%Y.%-m.%-d)"                       # 0.2026.8.25
    # one build per day; a second the same day collides again

    MSIX_VERSION="0.$(date -u +%Y.%m%d).$(( 10#$(date -u +%H) * 60 + 10#$(date -u +%M) ))"
    # 0.2026.825.312 = unstable | 2026 | Aug 25 | 05:12 UTC; several a day

Stamp it in the Windows build job before the MSIX step, and do NOT commit it
back to main -- `tag.yml` commits its version deliberately, a prerelease stamp
is per-build only.

Consequence either way: `0.x` is below every stable `2026.x`, so stable always
installs over a main build, and moving *to* a main build from stable is a
downgrade, which Windows refuses. Making that one click needs a manager-side
change: recognise the downgrade and take the uninstall-then-install route the
publisher-conflict path already uses, carrying the container data across.
Not written yet.
