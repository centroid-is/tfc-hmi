# Shipping the iOS app

CentroidX has an iOS target (`centroid-hmi/ios`, bundle id `is.centroid.x`,
team `Q4FZLRTZ4M`). It ships on the same two channels the desktop builds use,
and on the same triggers — nobody runs a release by hand:

| Channel | Trigger | Workflow | Where the build lands |
|---------|---------|----------|-----------------------|
| **TestFlight** | every merge to `main` | `main-prerelease.yml` → `ios.yml` (`channel: testflight`) | TestFlight, for internal testers. The mobile equivalent of the rolling `main-latest` prerelease. |
| **App Store** | pushing a version tag | `tag.yml` → `ios.yml` (`channel: appstore`) | Uploaded, attached to an App Store version, and **submitted to Apple for review**. |

Pull requests that touch `centroid-hmi/ios/**`, `centroid-hmi/pubspec.yaml`,
`.flutter-version` or the workflow itself get an unsigned compile check and
nothing else.

## The one thing to understand

There is only one upload. App Store Connect has a single build stream, and
every build uploaded to it is a TestFlight build. "App Store" is not a
different upload — it is what happens to a build *afterwards*: a store version
is created, the build is attached to it, and the version is submitted.

That is why the two channels differ by exactly one step
(`.github/scripts/appstore_submit.py` runs on the second one), and why a
release that fails at submission has still successfully put the binary in
TestFlight.

## Version numbers

`CFBundleShortVersionString` is the `version:` in `centroid-hmi/pubspec.yaml`,
minus the `+n`. On a tag, `tag.yml` has already rewritten that to the tag's
version, so the App Store publishes under the tag.

`CFBundleVersion` is `git rev-list --count HEAD` — the commit count. Apple
requires it to be unique and higher than every build already uploaded under the
same version string, and neither obvious alternative survives that:

- pubspec's `+n` is reset to `+1` on every tag, so a stable release would
  collide with the main builds already uploaded under that version;
- `github.run_number` resets if a workflow file is ever renamed.

The commit count only goes up and is a property of the repository. It also
means re-running a release workflow offers Apple a build it already has; that
one specific rejection is downgraded to a warning so a rerun does not turn
`main` red.

## Required repository secrets

Until these are set, the release channels still **build** the app (so the iOS
target cannot silently rot) but skip the upload with a warning on the run
summary. They do not fail — a permanently red `main` is how a real failure gets
ignored.

| Secret | What it is |
|--------|-----------|
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64 of an **Apple Distribution** certificate exported as `.p12`, including its private key |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | The password set when exporting that `.p12` (may be empty) |
| `APPLE_IOS_PROVISIONING_PROFILE_BASE64` | Base64 of an **App Store** provisioning profile for `is.centroid.x` |
| `APPLE_ASC_KEY_ID` | App Store Connect API key id (10 characters) |
| `APPLE_ASC_ISSUER_ID` | App Store Connect API issuer id (a UUID) |
| `APPLE_ASC_PRIVATE_KEY` | The contents of the downloaded `AuthKey_<KEYID>.p8`, pasted whole |
| `APPLE_TEAM_ID` | Already set — reused from the macOS notarization job |

The existing `APPLE_CERTIFICATE_P12_BASE64` is a **Developer ID Application**
certificate. That signs software distributed outside the store and App Store
Connect rejects it, which is why iOS needs its own certificate secret rather
than sharing that one. `ios.yml` asserts the imported identity is an Apple
Distribution one before spending twenty minutes on a build.

### Getting each of them

**Apple Distribution certificate.** In Xcode: *Settings → Accounts → Centroid →
Manage Certificates → + → Apple Distribution*. Then in Keychain Access, find
the new "Apple Distribution: …" identity, expand it so both the certificate and
its private key are selected, and *Export* as `.p12`.

```bash
base64 -i AppleDistribution.p12 | pbcopy   # -> APPLE_DISTRIBUTION_P12_BASE64
```

A team may hold at most three distribution certificates. If that limit is
already reached, export the existing one from whoever's Mac has the private key
rather than revoking one — a revoked certificate invalidates every profile
built on it.

**App Store provisioning profile.** In the [Apple Developer
portal](https://developer.apple.com/account/resources/profiles/list): *Profiles
→ + → App Store Connect*, App ID `is.centroid.x`, the certificate above.
Download the `.mobileprovision`.

```bash
base64 -i CentroidX_App_Store.mobileprovision | pbcopy   # -> APPLE_IOS_PROVISIONING_PROFILE_BASE64
```

`ios.yml` rejects the profile if it lists provisioned devices, if
`get-task-allow` is true, or if it is for another bundle id — all three are
ways a Development profile builds cleanly and is refused only after the upload.

**App Store Connect API key.** In App Store Connect: *Users and Access → Integrations
→ App Store Connect API → +*, role **App Manager** (Developer is not enough to
create a version or submit for review). Download the `.p8` — Apple lets you
download it exactly once. The key id and issuer id are on the same page.

```bash
pbcopy < AuthKey_XXXXXXXXXX.p8   # -> APPLE_ASC_PRIVATE_KEY (the whole file)
```

### Setting them

```bash
gh secret set APPLE_DISTRIBUTION_P12_BASE64 --repo centroid-is/CentroidX < dist.p12.b64
gh secret set APPLE_ASC_PRIVATE_KEY        --repo centroid-is/CentroidX < AuthKey_XXXXXXXXXX.p8
# ...and the rest
```

## Before the first App Store submission

Uploading needs only the secrets above. *Submitting* needs an App Store Connect
app record whose metadata Apple considers complete, and none of that can be
automated from zero:

- the app record itself, for bundle id `is.centroid.x`;
- screenshots for every required device size;
- description, keywords, support URL, privacy policy URL;
- the App Privacy questionnaire;
- age rating.

Until those exist, `appstore_submit.py` fails at the submission step with
Apple's own error text — and the build is already in TestFlight by then, so the
only thing left to do is finish the listing and re-run the job. It is
idempotent: it reuses the open draft version and the open review submission
rather than creating second ones.

## Who gets the TestFlight builds

Nothing in the pipeline assigns builds to a tester group. Internal testers
(anyone with an App Store Connect role on the app, up to 100) receive every
processed build automatically, which is what the `testflight` channel is for.

External testing is a separate decision with a separate Apple review, so if
builds should reach testers outside the team, create the external group in App
Store Connect and turn on automatic distribution there rather than adding a
step here.

Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is
`false` in `centroid-hmi/ios/Runner/Info.plist`, so no build is ever held
waiting on that question.

## Running it by hand

`ios.yml` has a `workflow_dispatch` trigger with the channel as an input, plus
a `submit_for_review` toggle for when the build should be attached to a store
version but the final submission left to a person:

```bash
gh workflow run ios.yml --repo centroid-is/CentroidX \
  -f channel=appstore -f submit_for_review=false
```

## When something goes wrong

**"iOS upload skipped" warning** — a secret from the table above is unset. The
run summary names which.

**Build stuck in PROCESSING** — Apple's processing takes anywhere from two
minutes to most of an hour; the script polls for 45 minutes and then fails
saying the upload itself succeeded. Re-running picks the build up.

**A red `ios-build` on a tag** — check whether it failed before or after
"Upload to App Store Connect". After means the binary is in TestFlight and only
the store listing needs attention.

**Testing the submission logic** — `.github/scripts/tests/` drives
`appstore_submit.py` against an in-memory App Store Connect. It needs nothing
installed:

```bash
python3 -m unittest discover -s .github/scripts/tests -v
```
