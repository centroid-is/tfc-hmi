"""Tests for verification gate — golden tests, marionette, AI design review."""
import subprocess
from unittest.mock import patch, MagicMock

import pytest

from orchestrator.verify import (
    VerificationReport,
    run_golden_tests,
    run_marionette_check,
    run_ai_design_review,
    run_verification_gate,
)
from orchestrator.models import VerificationConfig


class TestVerificationReport:
    def test_empty_report_passes(self):
        report = VerificationReport(story_id=1)
        assert report.passed
        assert report.golden_passed is None
        assert report.marionette_passed is None
        assert report.ai_review_passed is None

    def test_golden_failure_means_overall_fail(self):
        report = VerificationReport(story_id=1, golden_passed=False)
        assert not report.passed

    def test_golden_pass_means_overall_pass(self):
        report = VerificationReport(story_id=1, golden_passed=True)
        assert report.passed

    def test_marionette_failure_is_soft(self):
        """Marionette failure doesn't fail the overall report."""
        report = VerificationReport(
            story_id=1, golden_passed=True, marionette_passed=False,
        )
        assert report.passed

    def test_ai_review_failure_is_soft(self):
        report = VerificationReport(
            story_id=1, golden_passed=True, ai_review_passed=False,
        )
        assert report.passed

    def test_to_dict(self):
        report = VerificationReport(
            story_id=1, golden_passed=True,
            golden_details='All painter tests pass',
        )
        d = report.to_dict()
        assert d['story_id'] == 1
        assert d['golden_passed'] is True
        assert d['golden_details'] == 'All painter tests pass'
        assert d['passed'] is True


class TestGoldenTests:
    @patch('orchestrator.verify.subprocess.run')
    def test_golden_tests_pass(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout='All tests pass')
        passed, details = run_golden_tests('/tmp/project')
        assert passed
        mock_run.assert_called_once()

    @patch('orchestrator.verify.subprocess.run')
    def test_golden_tests_fail(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=1, stdout='', stderr='2 tests failed',
        )
        passed, details = run_golden_tests('/tmp/project')
        assert not passed
        assert '2 tests failed' in details

    def test_golden_tests_dry_run(self):
        passed, details = run_golden_tests('/tmp/project', dry_run=True)
        assert passed
        assert details == 'dry run'


class TestMarionetteCheck:
    @patch('orchestrator.verify.subprocess.run')
    def test_marionette_pass(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout='Routes verified')
        passed, details = run_marionette_check(
            '/tmp/project', story_id=7, routes=['/', '/prefs'],
        )
        assert passed

    @patch('orchestrator.verify.subprocess.run')
    def test_marionette_fail(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=1, stdout='', stderr='Route /prefs not reachable',
        )
        passed, details = run_marionette_check(
            '/tmp/project', story_id=7, routes=['/', '/prefs'],
        )
        assert not passed

    def test_marionette_dry_run(self):
        passed, details = run_marionette_check(
            '/tmp/project', story_id=7, routes=['/'], dry_run=True,
        )
        assert passed


class TestAiDesignReview:
    @patch('orchestrator.verify.subprocess.run')
    def test_ai_review_pass(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=0, stdout='PASS\nDesign looks consistent',
        )
        passed, details = run_ai_design_review('/tmp/project', story_id=7)
        assert passed

    @patch('orchestrator.verify.subprocess.run')
    def test_ai_review_findings(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=0, stdout='FINDINGS\n- Inconsistent button spacing',
        )
        passed, details = run_ai_design_review('/tmp/project', story_id=7)
        assert not passed
        assert 'Inconsistent button spacing' in details

    def test_ai_review_dry_run(self):
        passed, details = run_ai_design_review(
            '/tmp/project', story_id=7, dry_run=True,
        )
        assert passed


class TestVerificationGate:
    def test_verification_gate_disabled(self):
        config = VerificationConfig()
        report = run_verification_gate(
            config=config, project_dir='/tmp', story_id=1,
        )
        assert report.passed
        assert report.golden_passed is None

    @patch('orchestrator.verify.run_golden_tests')
    def test_golden_only(self, mock_golden):
        mock_golden.return_value = (True, 'All pass')
        config = VerificationConfig(golden_tests=True, ui_stories=[1])
        report = run_verification_gate(
            config=config, project_dir='/tmp', story_id=1,
        )
        assert report.passed
        assert report.golden_passed is True
        mock_golden.assert_called_once()

    def test_skips_non_ui_story(self):
        """Verification only runs for stories listed in ui_stories."""
        config = VerificationConfig(golden_tests=True, ui_stories=[6, 7])
        report = run_verification_gate(
            config=config, project_dir='/tmp', story_id=1,
        )
        assert report.passed
        assert report.golden_passed is None  # not run

    @patch('orchestrator.verify.run_golden_tests')
    @patch('orchestrator.verify.run_marionette_check')
    @patch('orchestrator.verify.run_ai_design_review')
    def test_full_pipeline(self, mock_ai, mock_mario, mock_golden):
        mock_golden.return_value = (True, 'ok')
        mock_mario.return_value = (True, 'ok')
        mock_ai.return_value = (False, 'spacing issue')

        config = VerificationConfig(
            golden_tests=True, marionette=True, ai_design_review=True,
            ui_stories=[7], route_map={7: ['/', '/prefs']},
        )
        report = run_verification_gate(
            config=config, project_dir='/tmp', story_id=7,
        )
        assert report.passed  # golden passed = overall pass
        assert report.golden_passed is True
        assert report.marionette_passed is True
        assert report.ai_review_passed is False
