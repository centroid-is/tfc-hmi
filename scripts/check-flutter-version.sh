#!/usr/bin/env bash
#
# Compare the Flutter on PATH against the version this repository pins in
# `.flutter-version`, and say so loudly when they differ.
#
# Why this exists: the pinned version is what CI installs (see
# `.github/actions/setup-flutter`), and running a different one locally
# produces the worst kind of failure — green on the developer's machine, red in
# CI forty minutes later, on `main`, for everybody. Two failure modes have
# actually bitten this repo:
#
#   1. Goldens. `test/**/goldens/` are rasterised PNGs. Different Flutter
#      versions antialias the same drawing slightly differently, so a golden
#      authored on the wrong version is either wrong in CI immediately, or —
#      worse — passes inside `test/helpers/golden_tolerance.dart`'s 0.01% and
#      leaves the next person a golden that is already half-way to the
#      threshold.
#
#   2. Framework assertions that only exist in the newer version. A
#      `ListTile`-inside-a-decorated-`Container` assertion ("ink splashes may
#      be invisible") reddened `main` from a PR whose author had run the full
#      suite locally, green, 3181 tests: the assertion is not in the older
#      Flutter's source at all. No amount of local testing can find that.
#
# Neither is detectable by running more tests locally. The only cheap defence
# is checking the toolchain itself, at the start of the work rather than at the
# end of CI.
#
# Usage:
#   scripts/check-flutter-version.sh [options]
#
#   --warn-only          Report a mismatch but exit 0. For advisory contexts
#                        that should not block (a shell prompt, an editor hook).
#   --quiet              Print nothing when the versions match.
#   --version-file PATH  Read the pinned version from PATH instead of
#                        `.flutter-version` at the repo root. Mainly for tests.
#   -h, --help           This text.
#
# Environment:
#   CENTROIDX_ALLOW_FLUTTER_SKEW=1   Same effect as --warn-only. An escape hatch for
#                              someone who knows they are on the wrong version
#                              and is deliberately not shipping goldens.
#
# Exit codes:
#   0  versions match (or a mismatch was downgraded to a warning)
#   1  versions differ
#   2  the check could not be run — no `.flutter-version`, no `flutter` on
#      PATH, unparseable version output

set -uo pipefail

warn_only=0
quiet=0
version_file=""

die() {
  printf 'check-flutter-version: %s\n' "$1" >&2
  exit 2
}

usage() {
  sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --warn-only) warn_only=1 ;;
    --quiet) quiet=1 ;;
    --version-file)
      [ $# -ge 2 ] || die "--version-file needs a path"
      version_file="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# Renamed, not exempted: the naming gate has no allowlist to park a key in.
[ "${CENTROIDX_ALLOW_FLUTTER_SKEW:-0}" = "1" ] && warn_only=1

# Locate `.flutter-version`. Prefer git so the script works from any
# subdirectory; fall back to the script's own parent for a tarball checkout.
if [ -z "$version_file" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$repo_root" ]; then
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  version_file="$repo_root/.flutter-version"
fi

[ -f "$version_file" ] || die "$version_file is missing — the pinned Flutter version lives there."

pinned="$(tr -d '[:space:]' < "$version_file")"
[ -n "$pinned" ] || die "$version_file is empty — it must contain exactly one Flutter version."

command -v flutter >/dev/null 2>&1 || die "no \`flutter\` on PATH. This repository needs Flutter $pinned."

# `--machine` is JSON and stable across versions; the human output has changed
# shape before. Tolerate leading noise (first-run banners, analytics notices)
# by grepping the field out rather than parsing the whole document.
machine_output="$(flutter --version --machine 2>/dev/null)"
installed="$(printf '%s' "$machine_output" \
  | sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n 1)"

if [ -z "$installed" ]; then
  # Fall back to the human-readable form: "Flutter 3.44.9 • channel stable ...".
  installed="$(flutter --version 2>/dev/null \
    | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' \
    | head -n 1)"
fi

[ -n "$installed" ] || die "could not read a version out of \`flutter --version\`."

flutter_path="$(command -v flutter)"

if [ "$installed" = "$pinned" ]; then
  [ "$quiet" = "1" ] || printf 'Flutter %s matches .flutter-version.\n' "$pinned"
  exit 0
fi

if [ "$warn_only" = "1" ]; then
  label="WARNING"
else
  label="ERROR"
fi

cat >&2 <<EOF

  ${label}: Flutter version mismatch.

    pinned   ${pinned}   (.flutter-version — what CI installs)
    on PATH  ${installed}   (${flutter_path})

  Work done on ${installed} can pass locally and fail in CI. Two ways it has:

    * Goldens rasterise differently between versions, so a golden you generate
      here is not the image CI compares against.
    * Framework assertions added in a newer Flutter cannot fire on an older
      one, so a widget tree that is already broken looks fine to you.

  Before you regenerate any golden, or trust a green local run of a UI change,
  get onto ${pinned}.

  This script does not change your toolchain — the global install is shared
  with other projects, and moving it is your call. See the "Flutter version"
  section of README.md for the ways to get ${pinned} without disturbing it.

  To proceed anyway (no goldens, no UI changes): set CENTROIDX_ALLOW_FLUTTER_SKEW=1
  or pass --warn-only.

EOF

[ "$warn_only" = "1" ] && exit 0
exit 1
