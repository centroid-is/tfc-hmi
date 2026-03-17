"""Tests for v3 CLI — DAG dispatch, phase fallback, no-verify flag."""
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


SIMPLE_DAG_PLAN = {
    'name': 'dag-test',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'dag',
    'workers': {'worktree_isolation': False},
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

PARALLEL_DAG_PLAN = {
    'name': 'parallel-dag',
    'project_dir': '/tmp/test-project',
    'model': 'sonnet',
    'execution_mode': 'dag',
    'workers': {'worktree_isolation': False},
    'phases': [
        {
            'name': 'Phase 1',
            'stories': [
                {'id': 1, 'name': 'Story 1', 'prompt': 'Do 1'},
            ],
        },
        {
            'name': 'Phase 2',
            'stories': [
                {'id': 2, 'name': 'Story 2', 'prompt': 'Do 2', 'depends_on': [1]},
                {'id': 3, 'name': 'Story 3', 'prompt': 'Do 3', 'depends_on': [1]},
            ],
        },
    ],
}

PHASE_FALLBACK_PLAN = {
    'name': 'phase-fallback',
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
    ],
}


class TestDAGDryRun:
    def test_dag_dry_run_completes_all(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_DAG_PLAN)
            result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            assert result.success
            assert result.completed_stories == {1, 2}

    def test_dag_parallel_stories(self):
        """Stories 2 and 3 depend only on 1, so they run after 1 completes."""
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, PARALLEL_DAG_PLAN)
            result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            assert result.success
            assert result.completed_stories == {1, 2, 3}

    def test_dag_dry_run_does_not_save_state(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_DAG_PLAN)
            run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            state_path = Path(tmpdir) / 'dag-test.state.json'
            assert not state_path.exists()


class TestPhaseFallback:
    def test_phase_mode_uses_v2(self):
        """When execution_mode='phase', should use cli_v2.run_plan_v2."""
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, PHASE_FALLBACK_PLAN)
            result = run_plan(plan_path, dry_run=True, state_dir=tmpdir)
            assert result.success
            assert result.completed_stories == {1}


class TestDAGResume:
    def test_resume_skips_completed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_DAG_PLAN)

            # Pre-populate: story 1 done
            state = OrchestratorState(plan_name='dag-test')
            state.mark_complete(1, 'Story 1', 60.0)
            state.save(Path(tmpdir) / 'dag-test.state.json')

            result = run_plan(
                plan_path, dry_run=True, state_dir=tmpdir,
            )
            assert result.success
            # Story 1 should not be re-executed
            assert 1 not in result.stories_executed
            assert 2 in result.stories_executed


class TestNoVerifyFlag:
    def test_no_verify_skips_verification(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            plan_data = {
                **SIMPLE_DAG_PLAN,
                'verification': {
                    'golden_tests': True,
                    'ui_stories': [1, 2],
                },
            }
            plan_path = _create_plan_file(tmpdir, plan_data)
            with patch('orchestrator.cli.run_verification_gate') as mock_verify:
                result = run_plan(
                    plan_path, dry_run=True, state_dir=tmpdir,
                    no_verify=True,
                )
                assert result.success
                mock_verify.assert_not_called()


class TestDAGFailureCascade:
    @patch('orchestrator.cli.execute_with_retry')
    def test_failure_skips_dependents(self, mock_execute):
        """When story 1 fails, story 2 (depends on 1) should be skipped."""
        mock_execute.return_value = MagicMock(
            success=False, exit_code=1,
            duration_seconds=10.0, stderr='compile error',
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            plan_path = _create_plan_file(tmpdir, SIMPLE_DAG_PLAN)
            result = run_plan(plan_path, dry_run=False, state_dir=tmpdir)
            assert not result.success
            assert 1 in result.failed_stories
            assert 2 in result.skipped_stories
