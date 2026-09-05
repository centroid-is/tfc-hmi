"""Tests for appstore_submit.py, against a fake App Store Connect.

The real thing cannot be exercised from CI: it needs Apple credentials, and
every call has a side effect on a live app listing. So the HTTP layer is
replaced with a small in-memory double and what gets tested is the part that
can actually be wrong — the order of the calls, which App Store version gets
reused rather than duplicated, and which of Apple's errors are survivable.

`unittest` rather than pytest, and a stub for PyJWT, so this suite runs on a
bare Python with nothing installed:

    python3 -m unittest discover -s .github/scripts/tests -v
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "appstore_submit.py"


def _load_module():
    # The script imports PyJWT, which is installed only on the release runner.
    # Nothing under test mints a token, so a stub keeps this suite dependency
    # free.
    sys.modules.setdefault("jwt", types.SimpleNamespace(encode=lambda *a, **k: "stub"))
    spec = importlib.util.spec_from_file_location("appstore_submit", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


asc = _load_module()


def _build(state, build_id="build1"):
    return {"id": build_id, "attributes": {"processingState": state}}


def _version(version_string, state, version_id="ver1"):
    return {"id": version_id,
            "attributes": {"versionString": version_string, "appVersionState": state}}


class FakeApi:
    """Stands in for appstore_submit.Client.

    Records every call so a test can assert on ordering, and lets a test
    program a specific error for a given (method, path prefix).
    """

    def __init__(self, *, app=True, builds=None, versions=None, localizations=None,
                 submissions=None, submission_items=None, errors=None):
        self.calls: list[tuple[str, str]] = []
        self.bodies: dict[str, dict] = {}
        self._app = app
        # A list of responses, popped one per poll, so a test can make a build
        # sit in PROCESSING for a while.
        self._builds = builds if builds is not None else [[_build("VALID")]]
        self._versions = versions if versions is not None else []
        self._localizations = localizations if localizations is not None else [
            {"id": "loc1", "attributes": {"locale": "en-US"}}
        ]
        self._submissions = submissions if submissions is not None else []
        self._submission_items = submission_items if submission_items is not None else []
        self._errors = errors or {}
        self.created_versions: list[dict] = []

    def _maybe_raise(self, method, path):
        for (m, prefix), exc in self._errors.items():
            if m == method and path.startswith(prefix):
                raise exc

    def request(self, method, path, body=None, params=None):
        self.calls.append((method, path))
        if body is not None:
            self.bodies[f"{method} {path}"] = body
        self._maybe_raise(method, path)

        if method == "GET":
            return self._get(path)
        if method == "POST" and path == "/v1/appStoreVersions":
            created = {"id": "ver-new", "attributes": dict(body["data"]["attributes"])}
            self.created_versions.append(created)
            self._versions.append(created)
            return {"data": created}
        if method == "POST" and path == "/v1/reviewSubmissions":
            sub = {"id": "sub-new", "attributes": {"state": "READY_FOR_REVIEW"}}
            self._submissions.append(sub)
            return {"data": sub}
        if method == "POST" and path == "/v1/reviewSubmissionItems":
            return {"data": {"id": "item-new"}}
        if method == "PATCH":
            if path.startswith("/v1/appStoreVersions/") and path.count("/") == 3:
                target = path.rsplit("/", 1)[1]
                for v in self._versions:
                    if v["id"] == target:
                        v["attributes"].update(body["data"]["attributes"])
            return {"data": {"id": "patched"}}
        raise AssertionError(f"unexpected {method} {path}")

    def _get(self, path):
        if path == "/v1/apps":
            return {"data": [{"id": "app1", "attributes": {"name": "CentroidX"}}]
                    if self._app else []}
        if path == "/v1/builds":
            return {"data": self._builds.pop(0) if self._builds else []}
        if path.endswith("/appStoreVersions"):
            return {"data": self._versions}
        if path.endswith("/appStoreVersionLocalizations"):
            return {"data": self._localizations}
        if path == "/v1/reviewSubmissions":
            return {"data": self._submissions}
        if path.endswith("/items"):
            return {"data": self._submission_items}
        if path.startswith("/v1/appStoreVersions/"):
            target = path.rsplit("/", 1)[1]
            for v in self._versions:
                if v["id"] == target:
                    return {"data": v}
        raise AssertionError(f"unexpected GET {path}")

    def get(self, path, **params):
        return self.request("GET", path, params=params or None)

    def paths(self, method=None):
        return [p for m, p in self.calls if method is None or m == method]


class NoSleep(unittest.TestCase):
    """Base for the tests that poll, so a suite run stays instant."""

    def setUp(self):
        patcher = mock.patch.object(asc.time, "sleep", lambda _s: None)
        patcher.start()
        self.addCleanup(patcher.stop)


class FindApp(unittest.TestCase):
    def test_missing_app_record_is_a_clear_failure(self):
        api = FakeApi(app=False)
        with self.assertRaises(SystemExit) as caught:
            asc.find_app(api, "is.centroid.x")
        self.assertIn("No such app", str(caught.exception))
        self.assertIn("is.centroid.x", str(caught.exception))


class WaitForBuild(NoSleep):
    def test_waits_until_the_build_stops_processing(self):
        api = FakeApi(builds=[[], [_build("PROCESSING")], [_build("VALID")]])
        build = asc.wait_for_build(api, "app1", "2026.9.5", "748", timeout_s=600)
        self.assertEqual(build["id"], "build1")
        self.assertEqual(api.paths().count("/v1/builds"), 3)

    def test_a_build_apple_rejects_fails_instead_of_polling_forever(self):
        api = FakeApi(builds=[[_build("INVALID")]])
        with self.assertRaises(SystemExit) as caught:
            asc.wait_for_build(api, "app1", "2026.9.5", "748", timeout_s=600)
        self.assertIn("INVALID", str(caught.exception))

    def test_processing_timeout_says_the_upload_still_worked(self):
        # A zero timeout is already in the past on the first check.
        api = FakeApi(builds=[[_build("PROCESSING")]] * 5)
        with self.assertRaises(SystemExit) as caught:
            asc.wait_for_build(api, "app1", "2026.9.5", "748", timeout_s=0)
        self.assertIn("upload itself succeeded", str(caught.exception))


class ChooseVersion(unittest.TestCase):
    def test_reuses_an_editable_version_with_the_same_number(self):
        api = FakeApi(versions=[_version("2026.9.5", "PREPARE_FOR_SUBMISSION")])
        version = asc.find_or_create_version(api, "app1", "2026.9.5", "AFTER_APPROVAL")
        self.assertEqual(version["id"], "ver1")
        self.assertEqual(api.paths("POST"), [])

    def test_reuses_a_version_apple_sent_back(self):
        # A rejected version is still ours to edit — that is the whole point of
        # tagging a fix and re-running.
        api = FakeApi(versions=[_version("2026.9.5", "DEVELOPER_REJECTED")])
        version = asc.find_or_create_version(api, "app1", "2026.9.5", "AFTER_APPROVAL")
        self.assertEqual(version["id"], "ver1")

    def test_refuses_to_touch_a_version_already_with_apple(self):
        api = FakeApi(versions=[_version("2026.9.5", "IN_REVIEW")])
        with self.assertRaises(SystemExit) as caught:
            asc.find_or_create_version(api, "app1", "2026.9.5", "AFTER_APPROVAL")
        self.assertIn("not editable", str(caught.exception))

    def test_renames_an_open_draft_rather_than_creating_a_second_one(self):
        # Apple allows exactly one editable version per platform, so a draft
        # someone opened by hand has to be reused or the release dies.
        api = FakeApi(versions=[_version("2026.9.4", "PREPARE_FOR_SUBMISSION")])
        version = asc.find_or_create_version(api, "app1", "2026.9.5", "AFTER_APPROVAL")
        self.assertEqual(version["id"], "ver1")
        self.assertEqual(version["attributes"]["versionString"], "2026.9.5")
        self.assertEqual(api.created_versions, [])
        self.assertIn(("PATCH", "/v1/appStoreVersions/ver1"), api.calls)

    def test_creates_a_version_when_there_is_nothing_to_reuse(self):
        api = FakeApi(versions=[_version("2026.9.4", "READY_FOR_DISTRIBUTION")])
        version = asc.find_or_create_version(api, "app1", "2026.9.5", "AFTER_APPROVAL")
        self.assertEqual(version["id"], "ver-new")
        body = api.bodies["POST /v1/appStoreVersions"]["data"]
        self.assertEqual(body["attributes"], {"platform": "IOS",
                                              "versionString": "2026.9.5",
                                              "releaseType": "AFTER_APPROVAL"})
        self.assertEqual(body["relationships"]["app"]["data"]["id"], "app1")


class ReleaseNotes(unittest.TestCase):
    def test_release_notes_go_to_every_locale(self):
        api = FakeApi(localizations=[{"id": "loc1", "attributes": {"locale": "en-US"}},
                                     {"id": "loc2", "attributes": {"locale": "is"}}])
        asc.set_whats_new(api, "ver1", "hello")
        self.assertIn(("PATCH", "/v1/appStoreVersionLocalizations/loc1"), api.calls)
        self.assertIn(("PATCH", "/v1/appStoreVersionLocalizations/loc2"), api.calls)
        self.assertEqual(
            api.bodies["PATCH /v1/appStoreVersionLocalizations/loc1"]["data"]["attributes"],
            {"whatsNew": "hello"})

    def test_a_first_release_refusing_whats_new_does_not_kill_the_release(self):
        # Apple rejects What's New on an app's very first version.
        err = asc.ApiError("PATCH", "/v1/appStoreVersionLocalizations/loc1", 409, "{}")
        api = FakeApi(errors={("PATCH", "/v1/appStoreVersionLocalizations"): err})
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            asc.set_whats_new(api, "ver1", "hello")
        self.assertIn("::warning", out.getvalue())

    def test_an_unexpected_error_on_release_notes_still_fails(self):
        err = asc.ApiError("PATCH", "/v1/appStoreVersionLocalizations/loc1", 500, "{}")
        api = FakeApi(errors={("PATCH", "/v1/appStoreVersionLocalizations"): err})
        with self.assertRaises(asc.ApiError):
            asc.set_whats_new(api, "ver1", "hello")

    def test_no_localizations_warns_rather_than_failing(self):
        api = FakeApi(localizations=[])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            asc.set_whats_new(api, "ver1", "hello")
        self.assertIn("::warning", out.getvalue())


class Submit(unittest.TestCase):
    def test_submission_creates_adds_and_submits_in_that_order(self):
        api = FakeApi()
        with contextlib.redirect_stdout(io.StringIO()):
            asc.submit_for_review(api, "app1", "ver1")
        self.assertEqual(api.calls, [
            ("GET", "/v1/reviewSubmissions"),
            ("POST", "/v1/reviewSubmissions"),
            ("GET", "/v1/reviewSubmissions/sub-new/items"),
            ("POST", "/v1/reviewSubmissionItems"),
            ("PATCH", "/v1/reviewSubmissions/sub-new"),
        ])
        self.assertEqual(
            api.bodies["PATCH /v1/reviewSubmissions/sub-new"]["data"]["attributes"],
            {"submitted": True})

    def test_rerun_reuses_the_open_submission_and_does_not_re_add_the_version(self):
        # What a re-run of the release workflow looks like.
        api = FakeApi(
            submissions=[{"id": "sub1", "attributes": {"state": "READY_FOR_REVIEW"}}],
            submission_items=[{"id": "item1", "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": "ver1"}}}}],
        )
        with contextlib.redirect_stdout(io.StringIO()):
            asc.submit_for_review(api, "app1", "ver1")
        self.assertNotIn(("POST", "/v1/reviewSubmissions"), api.calls)
        self.assertNotIn(("POST", "/v1/reviewSubmissionItems"), api.calls)
        self.assertIn(("PATCH", "/v1/reviewSubmissions/sub1"), api.calls)

    def test_an_item_for_a_different_version_does_not_count_as_ours(self):
        api = FakeApi(
            submissions=[{"id": "sub1", "attributes": {"state": "READY_FOR_REVIEW"}}],
            submission_items=[{"id": "item1", "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": "other"}}}}],
        )
        with contextlib.redirect_stdout(io.StringIO()):
            asc.submit_for_review(api, "app1", "ver1")
        self.assertIn(("POST", "/v1/reviewSubmissionItems"), api.calls)

    def test_an_item_with_no_version_relationship_is_ignored(self):
        # Review submissions can hold items that are not app versions at all.
        api = FakeApi(
            submissions=[{"id": "sub1", "attributes": {"state": "READY_FOR_REVIEW"}}],
            submission_items=[{"id": "item1", "relationships": {}}],
        )
        with contextlib.redirect_stdout(io.StringIO()):
            asc.submit_for_review(api, "app1", "ver1")
        self.assertIn(("POST", "/v1/reviewSubmissionItems"), api.calls)


BASE_ARGS = ["--key-id", "K", "--issuer-id", "I", "--private-key", "/dev/null",
             "--bundle-id", "is.centroid.x", "--version", "2026.9.5",
             "--build-number", "748"]


class FullRun(NoSleep):
    def _run(self, argv, api):
        with mock.patch.object(asc, "Client", lambda *a, **k: api), \
             mock.patch.object(sys, "argv", ["appstore_submit.py"] + argv), \
             contextlib.redirect_stdout(io.StringIO()):
            return asc.main()

    def test_full_run_attaches_the_build_then_submits(self):
        api = FakeApi()
        self.assertEqual(
            self._run(BASE_ARGS + ["--whats-new", "notes", "--submit"], api), 0)
        order = api.paths()
        self.assertLess(order.index("/v1/appStoreVersions/ver-new/relationships/build"),
                        order.index("/v1/reviewSubmissionItems"))
        self.assertEqual(
            api.bodies["PATCH /v1/appStoreVersions/ver-new/relationships/build"],
            {"data": {"type": "builds", "id": "build1"}})

    def test_no_submit_stops_after_attaching_the_build(self):
        api = FakeApi()
        self.assertEqual(self._run(BASE_ARGS + ["--no-submit"], api), 0)
        self.assertNotIn("/v1/reviewSubmissions", api.paths())
        self.assertIn("/v1/appStoreVersions/ver-new/relationships/build", api.paths())

    def test_empty_release_notes_skips_the_localization_calls(self):
        api = FakeApi()
        self._run(BASE_ARGS + ["--no-submit"], api)
        self.assertEqual([p for p in api.paths() if "Localizations" in p], [])


if __name__ == "__main__":
    unittest.main()
