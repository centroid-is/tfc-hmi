#!/usr/bin/env python3
"""
Take a build that is already in App Store Connect and put it in front of Apple.

Uploading a binary (which `xcrun altool --upload-app` has already done by the
time this runs) only makes it a TestFlight build. Shipping it to the App Store
is a separate sequence of App Store Connect API calls, and this script is that
sequence:

    1. wait for Apple to finish processing the uploaded build,
    2. find or create the App Store version for this version string,
    3. write the "What's New" text,
    4. attach the build to that version,
    5. submit the version for review.

Steps 2-5 are skipped with --no-submit, which leaves the build in TestFlight
only — that is what the `testflight` channel of ios.yml does by simply not
running this script.

Everything here is idempotent on purpose. A release workflow gets re-run: after
a cancelled job, after a flaky upload, after someone fixes metadata in the web
UI. Re-running must converge on the same state rather than pile up a second
draft version or a second review submission.

Usage:
    appstore_submit.py --key-id KEYID --issuer-id ISSUER --private-key key.p8 \
        --bundle-id is.centroid.x --version 2026.9.5 --build-number 748 \
        --whats-new "..." [--submit | --no-submit]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"

# States an App Store version can be in and still accept a new build and new
# metadata. Anything else (WAITING_FOR_REVIEW, IN_REVIEW, READY_FOR_DISTRIBUTION,
# ...) is Apple's to move, not ours, and writing to it fails at the API.
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
    "DEVELOPER_REMOVED_FROM_SALE",
}


class ApiError(RuntimeError):
    """An App Store Connect error, carrying Apple's own explanation."""

    def __init__(self, method: str, path: str, status: int, body: str):
        self.status = status
        self.body = body
        detail = body
        try:
            errors = json.loads(body).get("errors", [])
            detail = "\n".join(
                f"  {e.get('title', '?')}: {e.get('detail', '')}".rstrip() for e in errors
            ) or body
        except ValueError:
            pass
        super().__init__(f"{method} {path} -> HTTP {status}\n{detail}")


class Client:
    def __init__(self, key_id: str, issuer_id: str, private_key_path: str):
        self._key_id = key_id
        self._issuer_id = issuer_id
        with open(private_key_path) as fh:
            self._private_key = fh.read()
        self._token = None
        self._token_expires = 0.0

    def _auth_header(self) -> str:
        # App Store Connect caps token lifetime at 20 minutes. Waiting for a
        # build to process routinely takes longer than that, so the token is
        # minted lazily and re-minted before it can go stale mid-poll.
        now = time.time()
        if self._token is None or now > self._token_expires - 60:
            expires = now + 15 * 60
            self._token = jwt.encode(
                {"iss": self._issuer_id, "iat": int(now), "exp": int(expires),
                 "aud": "appstoreconnect-v1"},
                self._private_key,
                algorithm="ES256",
                headers={"kid": self._key_id, "typ": "JWT"},
            )
            self._token_expires = expires
        return f"Bearer {self._token}"

    def request(self, method: str, path: str, body: dict | None = None,
                params: dict | None = None) -> dict:
        url = API + path
        if params:
            # Apple's filter keys contain brackets, which must survive quoting.
            url += "?" + urllib.parse.urlencode(params, safe="[].")
        data = json.dumps(body).encode() if body is not None else None

        last: Exception | None = None
        for attempt in range(5):
            req = urllib.request.Request(url, data=data, method=method)
            req.add_header("Authorization", self._auth_header())
            req.add_header("Content-Type", "application/json")
            try:
                with urllib.request.urlopen(req, timeout=90) as resp:
                    raw = resp.read()
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as exc:
                raw = exc.read().decode(errors="replace")
                # 429 is Apple's rate limiter and 5xx is Apple having a bad
                # minute; both are worth a retry. A 4xx is us being wrong and
                # retrying only makes the log longer.
                if exc.code == 429 or 500 <= exc.code < 600:
                    last = ApiError(method, path, exc.code, raw)
                    time.sleep(2 ** attempt * 3)
                    continue
                raise ApiError(method, path, exc.code, raw) from None
            except urllib.error.URLError as exc:
                last = exc
                time.sleep(2 ** attempt * 3)
        raise last if last else RuntimeError("unreachable")

    def get(self, path, **params):
        return self.request("GET", path, params=params or None)


def log(msg: str) -> None:
    print(msg, flush=True)


def notice(title: str, msg: str) -> None:
    print(f"::notice title={title}::{msg}", flush=True)


def warn(title: str, msg: str) -> None:
    print(f"::warning title={title}::{msg}", flush=True)


def find_app(api: Client, bundle_id: str) -> dict:
    apps = api.get("/v1/apps", **{"filter[bundleId]": bundle_id}).get("data", [])
    if not apps:
        raise SystemExit(
            f"::error title=No such app::App Store Connect has no app with bundle id "
            f"{bundle_id} visible to this API key. Create the app record in App Store "
            f"Connect, or check that the key's role includes App Manager."
        )
    app = apps[0]
    log(f"App: {app['attributes'].get('name')} ({bundle_id}) id={app['id']}")
    return app


def wait_for_build(api: Client, app_id: str, version: str, build_number: str,
                   timeout_s: int) -> dict:
    """Poll until Apple has finished processing the build we just uploaded.

    A build cannot be attached to a version while it is PROCESSING, and Apple
    takes anywhere from two minutes to most of an hour. Polling is the only
    option — there is no callback.
    """
    deadline = time.time() + timeout_s
    delay = 30
    seen_state = None
    while True:
        builds = api.get("/v1/builds", **{
            "filter[app]": app_id,
            "filter[version]": build_number,
            "filter[preReleaseVersion.version]": version,
            "limit": 1,
        }).get("data", [])

        if builds:
            build = builds[0]
            state = build["attributes"].get("processingState")
            if state != seen_state:
                log(f"Build {version} ({build_number}): {state}")
                seen_state = state
            if state == "VALID":
                return build
            if state in ("FAILED", "INVALID"):
                raise SystemExit(
                    f"::error title=Build rejected::App Store Connect marked build "
                    f"{version} ({build_number}) as {state}. Apple emails the reason to "
                    f"the account holder; it is also on the build's page in App Store Connect."
                )
        elif seen_state is None:
            log(f"Waiting for build {version} ({build_number}) to appear...")

        if time.time() > deadline:
            raise SystemExit(
                f"::error title=Build processing timed out::Build {version} "
                f"({build_number}) was still {seen_state or 'absent'} after "
                f"{timeout_s // 60} minutes. The upload itself succeeded — check App "
                f"Store Connect and re-run this job, it will pick the build up."
            )
        time.sleep(delay)
        delay = min(delay * 2, 120)


def version_state(version: dict) -> str:
    attrs = version["attributes"]
    # appStoreState is deprecated in favour of appVersionState but is still
    # what older keys see, so read whichever is present.
    return attrs.get("appVersionState") or attrs.get("appStoreState") or "UNKNOWN"


def find_or_create_version(api: Client, app_id: str, version: str,
                           release_type: str) -> dict:
    versions = api.get(f"/v1/apps/{app_id}/appStoreVersions",
                       **{"filter[platform]": "IOS", "limit": 20}).get("data", [])

    for v in versions:
        if v["attributes"].get("versionString") == version:
            state = version_state(v)
            if state in EDITABLE_STATES:
                log(f"Reusing App Store version {version} (state {state})")
                return v
            raise SystemExit(
                f"::error title=Version not editable::App Store version {version} is in "
                f"state {state}, which Apple will not let us modify. If this release was "
                f"already submitted there is nothing to do; otherwise bump the version "
                f"and tag again."
            )

    # Apple allows exactly one editable version per platform. If a draft is
    # already open under a different version string, renaming it is the only
    # way forward — creating a second one is rejected. This is the normal path
    # when someone opened a draft in the web UI before the tag was pushed.
    for v in versions:
        if version_state(v) in EDITABLE_STATES:
            existing = v["attributes"].get("versionString")
            log(f"Renaming the open draft {existing} -> {version}")
            api.request("PATCH", f"/v1/appStoreVersions/{v['id']}", {
                "data": {
                    "type": "appStoreVersions",
                    "id": v["id"],
                    "attributes": {"versionString": version, "releaseType": release_type},
                }
            })
            return api.get(f"/v1/appStoreVersions/{v['id']}")["data"]

    log(f"Creating App Store version {version}")
    created = api.request("POST", "/v1/appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version,
                "releaseType": release_type,
            },
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    return created["data"]


def set_whats_new(api: Client, version_id: str, text: str) -> None:
    locs = api.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations") \
              .get("data", [])
    if not locs:
        warn("No localizations",
             "This App Store version has no localizations yet, so there was nowhere to "
             "put the release notes. Add a locale in App Store Connect.")
        return

    for loc in locs:
        locale = loc["attributes"].get("locale")
        try:
            api.request("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc["id"],
                    "attributes": {"whatsNew": text},
                }
            })
            log(f"Release notes set for {locale}")
        except ApiError as exc:
            # Apple rejects whatsNew on an app's very first version — there is
            # nothing for it to be new since. Not worth failing a release over.
            if exc.status in (400, 409):
                warn("Release notes not set",
                     f"Apple refused the What's New text for {locale}: {exc.body[:300]}")
            else:
                raise


def attach_build(api: Client, version_id: str, build_id: str) -> None:
    api.request("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", {
        "data": {"type": "builds", "id": build_id}
    })
    log("Build attached to the App Store version")


def submit_for_review(api: Client, app_id: str, version_id: str) -> None:
    submissions = api.get("/v1/reviewSubmissions", **{
        "filter[app]": app_id,
        "filter[platform]": "IOS",
        "filter[state]": "READY_FOR_REVIEW",
        "limit": 1,
    }).get("data", [])

    if submissions:
        submission = submissions[0]
        log(f"Reusing the open review submission {submission['id']}")
    else:
        submission = api.request("POST", "/v1/reviewSubmissions", {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })["data"]
        log(f"Created review submission {submission['id']}")

    items = api.get(f"/v1/reviewSubmissions/{submission['id']}/items").get("data", [])
    already = any(
        (it.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id")
        == version_id
        for it in items
    )
    if already:
        log("The version is already an item on this submission")
    else:
        api.request("POST", "/v1/reviewSubmissionItems", {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": submission["id"]}
                    },
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    },
                },
            }
        })
        log("Version added to the review submission")

    api.request("PATCH", f"/v1/reviewSubmissions/{submission['id']}", {
        "data": {
            "type": "reviewSubmissions",
            "id": submission["id"],
            "attributes": {"submitted": True},
        }
    })
    notice("Submitted for review",
           "The App Store version was submitted to Apple. Review usually takes a day or two.")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--key-id", required=True)
    p.add_argument("--issuer-id", required=True)
    p.add_argument("--private-key", required=True, help="path to the .p8 file")
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--version", required=True, help="CFBundleShortVersionString")
    p.add_argument("--build-number", required=True, help="CFBundleVersion")
    p.add_argument("--whats-new", default="")
    p.add_argument("--release-type", default="AFTER_APPROVAL",
                   choices=["MANUAL", "AFTER_APPROVAL"],
                   help="AFTER_APPROVAL goes live as soon as Apple approves it")
    p.add_argument("--processing-timeout", type=int, default=45 * 60,
                   help="seconds to wait for Apple to finish processing the build")
    submit = p.add_mutually_exclusive_group()
    submit.add_argument("--submit", dest="submit", action="store_true", default=True)
    submit.add_argument("--no-submit", dest="submit", action="store_false",
                        help="prepare the version and attach the build, but leave the "
                             "final submission to a human")
    args = p.parse_args()

    api = Client(args.key_id, args.issuer_id, args.private_key)

    app = find_app(api, args.bundle_id)
    build = wait_for_build(api, app["id"], args.version, args.build_number,
                           args.processing_timeout)

    version = find_or_create_version(api, app["id"], args.version, args.release_type)
    if args.whats_new:
        set_whats_new(api, version["id"], args.whats_new)
    attach_build(api, version["id"], build["id"])

    if args.submit:
        submit_for_review(api, app["id"], version["id"])
    else:
        notice("Ready to submit",
               f"App Store version {args.version} has build {args.build_number} attached "
               f"and is waiting for someone to press Submit in App Store Connect.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ApiError as exc:
        print(f"::error title=App Store Connect rejected the request::{exc}", flush=True)
        sys.exit(1)
