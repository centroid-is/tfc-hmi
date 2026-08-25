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

## 7. Give main builds their own version (decided, needs applying)

`tag.yml` rewrites `msix_version` from the tag and commits it; nothing else
does. So every main build carried the last stable release's number, and two
things followed on the test station:

- installing one main build over another failed with 0x80073CFB. Windows keys
  a package by identity -- name, publisher, version, architecture -- and never
  by content, so the same version is the same package however much the
  contents changed
- the version manager reported a main build as the stable channel: it reads
  `Get-AppxPackage`, which said `2026.8.23.1`, and that is genuinely the
  stable release's version

Scheme: **0.year.month.run_number** for anything not built from a tag. The
leading zero reads as unstable and sorts below every stable `2026.x`; the run
number is monotonic, so builds order correctly within a month and across
months and years.

One step in `.github/workflows/windows.yml`, immediately before "Build MSIX
(sideload, signed)". Conditioned on `inputs.ref == ''` because `tag.yml`
passes a ref and has already committed the tag's version -- a stable build
must not be restamped. PR and dispatch builds are stamped too, which is right:
an MSIX built from a PR should not claim a release's version either.

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

Do not commit the stamp back to main: `tag.yml` commits its version
deliberately, a prerelease stamp is per-build only.

The plant PC's token has no `workflow` scope, so this cannot be pushed from
there. It is committed on the branch `chore/stamp-unstable-msix-version`
locally, and exported as a patch (`stamp-unstable-msix-version.patch` in that
session's scratchpad) -- or just paste the step above.

### The consequence to know about

`0.x` sits below stable, so a stable release always installs over a main build
-- the direction the plant travels. The reverse (stable to main build) is a
downgrade, which Windows refuses outright, so a station on stable must
uninstall before it can take a main build. Making that one click needs a
manager change: recognise the downgrade and take the uninstall-then-install
route the publisher-conflict path already uses, carrying
`LocalCache\Roaming` across so key mappings and layout survive. Not written yet.
