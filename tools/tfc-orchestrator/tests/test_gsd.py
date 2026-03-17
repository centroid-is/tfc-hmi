"""Tests for gsd — GSD command wrapper: discuss, plan, verify, UI review."""
import json
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

from orchestrator.gsd import (
    GapReport,
    _parse_verify_output,
    _parse_ui_review_output,
    run_gsd_pre_phase,
    run_gsd_post_phase,
)
from orchestrator.models import Plan, Phase, Story, GsdConfig


def _make_plan(gsd_enabled=False, **gsd_overrides):
    gsd = GsdConfig(enabled=gsd_enabled, **gsd_overrides)
    return Plan(
        name='test', project_dir='/tmp/test', model='sonnet',
        phases=[], gsd=gsd,
    )


def _make_phase(name='Phase 1'):
    return Phase(name=name, stories=[
        Story(id=1, name='s1', prompt='do stuff'),
    ])


class TestGapReport:
    def test_empty_gap_report(self):
        report = GapReport(phase_name='P1', phase_index=0)
        assert report.has_gaps is False

    def test_gap_report_with_verify_gaps(self):
        report = GapReport(
            phase_name='P1', phase_index=0,
            verify_gaps=['missing test'],
        )
        assert report.has_gaps is True

    def test_gap_report_save(self):
        report = GapReport(phase_name='P1', phase_index=0, verify_gaps=['gap1'])
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / 'sub' / 'report.json'
            report.save(path)
            assert path.exists()
            data = json.loads(path.read_text())
            assert data['phase_name'] == 'P1'


class TestParseVerifyOutput:
    def test_pass_output(self):
        passed, gaps = _parse_verify_output("PASS\nAll good")
        assert passed is True
        assert gaps == []

    def test_gaps_found_output(self):
        passed, gaps = _parse_verify_output(
            "GAPS_FOUND\n- missing test\n- no validation"
        )
        assert passed is False
        assert gaps == ['missing test', 'no validation']


class TestParseUiReviewOutput:
    def test_findings_output(self):
        passed, findings = _parse_ui_review_output(
            "FINDINGS\n- bad contrast"
        )
        assert passed is False
        assert findings == ['bad contrast']


class TestRunGsdPrePhase:
    def test_disabled_returns_true(self):
        plan = _make_plan(gsd_enabled=False)
        phase = _make_phase()
        result = run_gsd_pre_phase(phase, plan)
        assert result is True

    @patch('orchestrator.gsd.execute_story')
    def test_dry_run_succeeds(self, mock_exec):
        from orchestrator.executor import ExecutionResult
        mock_exec.return_value = ExecutionResult(
            story_id=0, exit_code=0, stdout='[DRY RUN]',
            stderr='', duration_seconds=0.0,
        )
        plan = _make_plan(gsd_enabled=True, discuss=True, plan=True)
        phase = _make_phase()
        result = run_gsd_pre_phase(phase, plan, dry_run=True)
        assert result is True


class TestRunGsdPostPhase:
    def test_disabled_returns_empty_report(self):
        plan = _make_plan(gsd_enabled=False)
        phase = _make_phase()
        with tempfile.TemporaryDirectory() as tmpdir:
            report = run_gsd_post_phase(phase, 0, plan, tmpdir)
            assert report.has_gaps is False

    @patch('orchestrator.gsd.execute_story')
    def test_dry_run_returns_empty_report(self, mock_exec):
        from orchestrator.executor import ExecutionResult
        mock_exec.return_value = ExecutionResult(
            story_id=0, exit_code=0, stdout='[DRY RUN]',
            stderr='', duration_seconds=0.0,
        )
        plan = _make_plan(
            gsd_enabled=True, verify=True, ui_review=['Phase 1'],
        )
        phase = _make_phase()
        with tempfile.TemporaryDirectory() as tmpdir:
            report = run_gsd_post_phase(phase, 0, plan, tmpdir, dry_run=True)
            assert report.has_gaps is False
