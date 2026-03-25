# macOS Code Signing & Notarization Setup

## Overview

This guide sets up Apple Developer ID signing and notarization for `centroidx-manager` on macOS. After completing these steps, the macOS binary will be signed and notarized — users can run it without Gatekeeper warnings or `xattr` workarounds.

## Prerequisites

- macOS machine with Xcode Command Line Tools (`xcode-select --install`)
- Apple Developer Program membership ($99/year)
- Access to the GitHub repo's Settings → Secrets

## Step 1: Find Your Team ID

```bash
# If you have Xcode installed:
xcrun xcodebuild -showTeamIDs 2>/dev/null

# Or check at: https://developer.apple.com/account → Membership Details
# Team ID looks like: ABC123XYZ
```

Save your Team ID — you'll need it for the GitHub secret.

## Step 2: Create a Developer ID Application Certificate

1. Open **Keychain Access** → Certificate Assistant → Request a Certificate from a Certificate Authority
   - Email: your Apple ID email
   - Request is: Saved to disk
   - This creates a `.certSigningRequest` file

2. Go to https://developer.apple.com/account/resources/certificates/add
   - Select **Developer ID Application**
   - Upload the `.certSigningRequest`
   - Download the `.cer` file
   - Double-click to install in Keychain

3. Verify it's installed:
```bash
security find-identity -v -p codesigning
# Should show: "Developer ID Application: Your Name (TEAM_ID)"
```

## Step 3: Export the Certificate as .p12

```bash
# Find the certificate name
security find-identity -v -p codesigning | grep "Developer ID Application"

# Export via Keychain Access:
# 1. Open Keychain Access
# 2. Find "Developer ID Application: ..." under "My Certificates"
# 3. Right-click → Export Items
# 4. Save as .p12 format
# 5. Set a strong password (you'll need it for the GitHub secret)

# Or via command line (replace IDENTITY with the hash from find-identity):
# security export -k login.keychain -t identities -f pkcs12 -o developer_id.p12

# Base64-encode it for the GitHub secret:
base64 -i developer_id.p12 -o developer_id_base64.txt
cat developer_id_base64.txt | pbcopy  # copies to clipboard
echo "Base64 copied to clipboard"
```

## Step 4: Generate an App-Specific Password

1. Go to https://account.apple.com → Sign-In and Security → App-Specific Passwords
2. Click "Generate an app-specific password"
3. Name it: `centroidx-ci-notarize`
4. Save the generated password

## Step 5: Set GitHub Secrets

Go to: https://github.com/centroid-is/tfc-hmi/settings/secrets/actions

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded .p12 from Step 3 |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set when exporting the .p12 |
| `APPLE_TEAM_ID` | Your Team ID from Step 1 |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_ID_PASSWORD` | App-specific password from Step 4 |

```bash
# Or set them via CLI (if you have gh installed):
gh secret set APPLE_CERTIFICATE_P12_BASE64 < developer_id_base64.txt
echo "your-p12-password" | gh secret set APPLE_CERTIFICATE_PASSWORD
echo "ABC123XYZ" | gh secret set APPLE_TEAM_ID
echo "you@example.com" | gh secret set APPLE_ID
echo "xxxx-xxxx-xxxx-xxxx" | gh secret set APPLE_ID_PASSWORD
```

## Step 6: Verify Locally (Optional)

Before pushing to CI, you can test signing and notarization locally:

```bash
cd tools/centroidx-manager

# Build the binary
CGO_ENABLED=1 go build -o centroidx-manager_darwin_arm64 .

# Sign it
codesign --force --options runtime --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
  --timestamp centroidx-manager_darwin_arm64

# Verify signature
codesign --verify --deep --strict centroidx-manager_darwin_arm64
echo "Signing OK"

# Create a zip for notarization
zip centroidx-manager_darwin_arm64.zip centroidx-manager_darwin_arm64

# Submit for notarization
xcrun notarytool submit centroidx-manager_darwin_arm64.zip \
  --apple-id "you@example.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID" \
  --wait

# Staple the notarization ticket (optional for standalone binaries)
# xcrun stapler staple centroidx-manager_darwin_arm64
# Note: stapler only works on .app, .dmg, .pkg — not standalone binaries.
# For standalone binaries, Gatekeeper checks notarization online.

# Test Gatekeeper
spctl --assess --type execute centroidx-manager_darwin_arm64
echo "Gatekeeper OK"
```

## What CI Does After Setup

Once the secrets are configured, the CI pipeline (`.github/workflows/build-manager.yml`) will automatically:

1. Import the .p12 certificate into a temporary macOS keychain
2. Build the Go binary with CGO_ENABLED=1
3. Sign it with `codesign --options runtime --timestamp`
4. Create a zip and submit to Apple's notary service via `notarytool`
5. Wait for notarization to complete (~2-5 minutes)
6. Upload the signed+notarized binary as a CI artifact

Users downloading from GitHub Releases will be able to run the binary without any Gatekeeper warnings.

## Troubleshooting

### "Developer ID Application certificate not found"
- Make sure you created a **Developer ID Application** cert, not an iOS or Mac App Store cert
- Check it's in the login keychain: `security find-identity -v -p codesigning`

### "Unable to authenticate" during notarization
- Verify the app-specific password is correct (regenerate if unsure)
- Make sure your Apple ID has accepted the latest Developer Program agreement

### "The signature is invalid" after signing
- Ensure `--options runtime` is used (required for notarization)
- Ensure `--timestamp` is used (required for notarization)

### Notarization fails with "invalid binary"
- The binary must be built with hardened runtime (`--options runtime` in codesign)
- If using CGO, ensure all linked libraries are also signed
