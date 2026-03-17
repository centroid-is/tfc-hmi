"""Integration tests for the orchestrator — v2 phase-based execution via fallback."""
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

import yaml

from orchestrator.cli import run_plan
from orchestrator.state import OrchestratorState


def _create_plan_file(tmpdir: str, plan_data: dict) -> str:
    plan_path = Path(tmpdir) / 'plan.yaml'
    with open(plan_path, 'w') as f:
        yaml.dump(plan_data, f)
    return str(plan_path)


SIMPLE_PLAN = {
    'name': 'test-plan',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'phase',
    'phases': [
        {
            'name': 'Phase 1',
            'stories': [
                {'id': 1, 'name': 'Story 1', 'prompt': 'Do story 1'},
            ],
        },
        {
            'name': 'Phase 2',
            'stories': [
                {'id': 2, 'name': 'Story 2', 'prompt': 'Do story 2', 'depends_on': [1]},
            ],
        },
    ],
}

PARALLEL_PLAN = {
    'name': 'parallel-plan',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'phase',
    'phases': [
        {
            'name': 'Parallel Phase',
            'stories': [
                {'id': 1, 'name': 'Story A', 'prompt': 'Do A'},
                {'id': 2, 'name': 'Story B', 'prompt': 'Do B'},
                {'id': 3, 'name': 'Story C', 'prompt': 'Do C'},
            ],
        },
    ],
}


class TestDryRun:
    def test_dry_run_completes_all_phases(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_PLAN)
            result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            assert result.success
            assert result.completed_stories == {1, 2}

    def test_dry_run_parallel_stories(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, PARALLEL_PLAN)
            result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            assert result.success
            assert result.completed_stories == {1, 2, 3}


class TestResume:
    def test_resume_skips_completed_stories(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_PLAN)

            # Pre-populate state: story 1 already done
            state = OrchestratorState(plan_name='test-plan')
            state.mark_complete(1, 'Story 1', 60.0)
            state.current_phase = 1
            state.save(Path(tmpdir) / 'test-plan.state.json')

            result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            assert result.success
            # Story 1 should not have been re-executed
            assert result.stories_executed == {2}


class TestFailureHandling:
    @patch('orchestrator.executor.subprocess.Popen')
    def test_stops_on_failure(self, mock_popen_cls):
        mock_proc = MagicMock()
        mock_proc.communicate.return_value = ('', 'compile error')
        mock_proc.returncode = 1
        mock_proc.pid = 12345
        mock_popen_cls.return_value = mock_proc

        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_PLAN)
            result = run_plan(plan_path, dry_run=False, state_dir=tmpdir)
            assert not result.success
            assert 1 in result.failed_stories

    @patch('orchestrator.executor.subprocess.Popen')
    def test_state_saved_on_failure(self, mock_popen_cls):
        mock_proc = MagicMock()
        mock_proc.communicate.return_value = ('', 'error')
        mock_proc.returncode = 1
        mock_proc.pid = 12345
        mock_popen_cls.return_value = mock_proc

        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_PLAN)
            run_plan(plan_path, dry_run=False, state_dir=tmpdir)

            state_path = Path(tmpdir) / 'test-plan.state.json'
            assert state_path.exists()
            state = OrchestratorState.load(state_path)
            assert 1 in state.failed_story_ids


class TestValidation:
    def test_phase_validation_runs_after_stories(self):
        plan_data = {
            'name': 'validate-plan',
            'project_dir': '/tmp/test',
            'model': 'sonnet',
            'execution_mode': 'phase',
            'phases': [{
                'name': 'P1',
                'validate': ['echo "all good"'],
                'stories': [{'id': 1, 'name': 's1', 'prompt': 'p'}],
            }],
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, plan_data)
            with patch('orchestrator.cli_v2.run_validation') as mock_validate:
                mock_validate.return_value = True
                result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
                # Validation should have been called for the phase
                mock_validate.assert_called_once()


RETRY_PLAN = {
    'name': 'retry-plan',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'phase',
    'retry': {'max_attempts': 2},
    'phases': [{
        'name': 'Phase 1',
        'stories': [{'id': 1, 'name': 'Story 1', 'prompt': 'Do story 1'}],
    }],
}

REVIEW_PLAN = {
    'name': 'review-plan',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'phase',
    'review': {'enabled': True},
    'phases': [{
        'name': 'Phase 1',
        'stories': [{'id': 1, 'name': 'Story 1', 'prompt': 'Do story 1'}],
    }],
}

GSD_PLAN = {
    'name': 'gsd-plan',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'phase',
    'gsd': {'enabled': True},
    'phases': [{
        'name': 'Phase 1',
        'stories': [{'id': 1, 'name': 'Story 1', 'prompt': 'Do story 1'}],
    }],
}


class TestRetryIntegration:
    def test_dry_run_with_retry_config(self):
        """Retry config is parsed and execute_with_retry is called without error."""
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, RETRY_PLAN)
            with patch('orchestrator.cli_v2.execute_with_retry') as mock_retry:
                # Simulate successful execution
                mock_retry.return_value = MagicMock(
                    success=True, duration_seconds=0.0, stderr='',
                )
                result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
                assert result.success
                assert result.completed_stories == {1}
                mock_retry.assert_called_once()


class TestGsdIntegration:
    def test_gsd_pre_post_called_on_dry_run(self):
        """GSD pre-phase and post-phase are called when gsd.enabled=True."""
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, GSD_PLAN)
            with patch('orchestrator.cli_v2.run_gsd_pre_phase') as mock_pre, \
                 patch('orchestrator.cli_v2.run_gsd_post_phase') as mock_post:
                mock_pre.return_value = True
                mock_post.return_value = MagicMock(has_gaps=False)
                result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
                assert result.success
                mock_pre.assert_called_once()
                mock_post.assert_called_once()


class TestNoFlags:
    def test_no_review_flag_skips_review(self):
        """When no_review=True, run_review_cycle is never called."""
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, REVIEW_PLAN)
            with patch('orchestrator.cli_v2.run_review_cycle') as mock_review:
                result = run_plan(
                    plan_path, dry_run=True, state_dir=tmpdir,
                    no_review=True,
                )
                assert result.success
                mock_review.assert_not_called()

    def test_no_gsd_flag_skips_gsd(self):
        """When no_gsd=True, run_gsd_pre_phase is never called."""
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, GSD_PLAN)
            with patch('orchestrator.cli_v2.run_gsd_pre_phase') as mock_pre, \
                 patch('orchestrator.cli_v2.run_gsd_post_phase') as mock_post:
                result = run_plan(
                    plan_path, dry_run=True, state_dir=tmpdir,
                    no_gsd=True,
                )
                assert result.success
                mock_pre.assert_not_called()
                mock_post.assert_not_called()
