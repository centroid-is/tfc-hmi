#!/usr/bin/env bash
#
# Create a compressed DMG from a folder, retrying a "Resource busy" failure.
#
#   create-dmg.sh <volume-name> <source-folder> <output-dmg>
#
# `hdiutil create -srcfolder` attaches a temporary read/write image, copies the
# folder into it, then detaches and converts it. If anything on the runner is
# still holding that volume when it tries to detach — Spotlight/mds indexing
# the fresh mount is the usual culprit — the command dies with "Resource busy".
# Observed on PR #299, on a branch that touched only Go code, so it is not
# something a code change can provoke or avoid. The volume is left mounted, so
# a bare retry hits the same busy volume and fails identically; the stale mount
# has to be detached first, which is the whole reason this is a script and not
# a `for i in 1 2 3` around the command.
#
# Worth retrying because every caller is building a published release asset and
# every calling job sits in create-release's `needs`. By the time they run,
# retag-pubspec has already pushed the version bump and made the tag public, so
# one transient failure here leaves a live tag with no release behind it,
# recoverable only by re-running the whole workflow.
#
# After the final attempt this exits non-zero and takes the job down with it. A
# retry loop that swallowed the last error would be worse than no retry at all:
# create-release would proceed with a missing or truncated asset.
#
# Callers — keep this the only copy, two workflows drifting apart is what it
# exists to prevent:
#   .github/workflows/macos.yml           "Create DMG"
#   .github/workflows/build-manager.yml   "Sign and notarize macOS app bundle"
#                                         "Create unsigned DMG (when signing is not available)"
set -eu

VOLNAME=${1:?volume name required}
SRC_DIR=${2:?source folder required}
DMG_PATH=${3:?output dmg path required}

# Overridable so the retry path can be exercised without a ten-second wait.
ATTEMPTS=${DMG_CREATE_ATTEMPTS:-3}
RETRY_SLEEP=${DMG_CREATE_RETRY_SLEEP:-10}

detach_stale_volume() {
  # `mount` prints e.g. "/dev/disk4s1 on /Volumes/CentroidX (hfs, local, ...)".
  # Look the device up from the volume name we just asked for rather than
  # assuming a path: detaching by device node also catches a re-mount suffix
  # ("CentroidX 1") and needs no quoting of a mountpoint containing a space.
  # A no-match grep is expected and must not be fatal — see the `for` below.
  local dev
  for dev in $(mount | grep -F " on /Volumes/$VOLNAME" | awk '{ print $1 }'); do
    echo "Detaching stale volume $dev left attached by hdiutil"
    hdiutil detach "$dev" -force || true
  done
}

created=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  if hdiutil create -volname "$VOLNAME" -srcfolder "$SRC_DIR" \
    -ov -format UDZO "$DMG_PATH"; then
    created=yes
    break
  fi
  echo "::warning title=hdiutil create failed::Attempt $attempt of $ATTEMPTS failed for $DMG_PATH. Detaching any stale volume and retrying."
  detach_stale_volume
  # Drop a half-written image so nothing downstream can pick up a truncated
  # asset, and so the failure below is unambiguous.
  rm -f "$DMG_PATH"
  # Give DiskArbitration time to settle the unmount before attaching again.
  # Guarded with an explicit `if` rather than `[ ... ] && sleep`, which would
  # abort the script under `set -e` on the last iteration.
  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    sleep "$RETRY_SLEEP"
  fi
done

if [ -z "$created" ]; then
  echo "::error title=DMG creation failed::hdiutil create failed $ATTEMPTS times for $DMG_PATH. Failing the job — a release must not be published without this asset."
  exit 1
fi

ls -lh "$DMG_PATH"
