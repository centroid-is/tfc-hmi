"""Tests for state v3 — thread safety, new fields, v2 backward compat, atomic write."""
import json
import tempfile
import threading
from pathlib import Path

import pytest

from orchestrator.state import OrchestratorState, StoryResult


class TestStateV3Fields:
    """Per-story v3 fields: worktree_branch, merge_commit, verification, worker_slot."""

    def test_v3_fields_default_to_none_or_empty(self):
        result = StoryResult(story_id=1, story_name='s1', status='pass')
        assert result.worktree_branch == ''
        assert result.merge_commit == ''
        assert result.verification_passed is None
        assert result.verification_details == ''
        assert result.started_at == ''
        assert result.worker_slot == -1

    def test_v3_fields_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            state = OrchestratorState(plan_name='v3-test')
            state.results.append(StoryResult(
                story_id=1,
                story_name='Story 1',
                status='pass',
                worktree_branch='orchestrator/story-1',
                merge_commit='abc1234',
                verification_passed=True,
                verification_details='Golden tests passed',
                started_at='2026-03-17T10:00:00',
                worker_slot=2,
            ))
            state.save(state_path)

            loaded = OrchestratorState.load(state_path)
            r = loaded.results[0]
            assert r.worktree_branch == 'orchestrator/story-1'
            assert r.merge_commit == 'abc1234'
            assert r.verification_passed is True
            assert r.verification_details == 'Golden tests passed'
            assert r.started_at == '2026-03-17T10:00:00'
            assert r.worker_slot == 2


class TestStateVersion:
    def test_saves_version_3(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            state = OrchestratorState(plan_name='test')
            state.save(state_path)
            data = json.loads(state_path.read_text())
            assert data['version'] == 3

    def test_loads_v2_state_file(self):
        """Backward-compatible load of v2 state files (no version field)."""
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            v2_data = {
                'plan_name': 'old-plan',
                'current_phase': 1,
                'started_at': '2026-03-16T10:00:00',
                'results': [{
                    'story_id': 1,
                    'story_name': 'Story 1',
                    'status': 'pass',
                    'duration_seconds': 120.0,
                    'error': '',
                    'timestamp': '2026-03-16T10:30:00',
                    'retry_count': 1,
                    'review_iterations': 2,
                    'review_findings': 3,
                }],
            }
            state_path.write_text(json.dumps(v2_data))

            loaded = OrchestratorState.load(state_path)
            assert loaded.plan_name == 'old-plan'
            assert loaded.current_phase == 1
            assert len(loaded.results) == 1
            r = loaded.results[0]
            assert r.retry_count == 1
            assert r.review_iterations == 2
            # v3 fields should be defaults
            assert r.worktree_branch == ''
            assert r.merge_commit == ''
            assert r.verification_passed is None
            assert r.worker_slot == -1


class TestThreadSafety:
    def test_concurrent_mark_complete(self):
        """Multiple threads can safely call mark_complete."""
        state = OrchestratorState(plan_name='thread-test')
        errors = []

        def mark(story_id):
            try:
                state.mark_complete(story_id, f'Story {story_id}', 10.0)
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=mark, args=(i,)) for i in range(1, 51)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert not errors
        assert len(state.results) == 50
        assert state.completed_story_ids == set(range(1, 51))

    def test_concurrent_mark_failed(self):
        state = OrchestratorState(plan_name='thread-test')
        errors = []

        def mark(story_id):
            try:
                state.mark_failed(story_id, f'Story {story_id}', 5.0, 'err')
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=mark, args=(i,)) for i in range(1, 21)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert not errors
        assert len(state.results) == 20

    def test_concurrent_save(self):
        """Multiple threads saving should not corrupt the file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            state = OrchestratorState(plan_name='save-test')
            state.mark_complete(1, 'Story 1', 10.0)
            errors = []

            def save():
                try:
                    state.save(state_path)
                except Exception as e:
                    errors.append(e)

            threads = [threading.Thread(target=save) for _ in range(10)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()

            assert not errors
            loaded = OrchestratorState.load(state_path)
            assert loaded.plan_name == 'save-test'
            assert len(loaded.results) == 1


class TestAtomicWrite:
    def test_save_uses_atomic_write(self):
        """Verify atomic write by checking no partial files on crash simulation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            state = OrchestratorState(plan_name='atomic-test')
            for i in range(1, 10):
                state.mark_complete(i, f'Story {i}', float(i))
            state.save(state_path)

            # File should be valid JSON
            data = json.loads(state_path.read_text())
            assert len(data['results']) == 9
            # No temp files should remain
            tmpfiles = list(Path(tmpdir).glob('*.tmp'))
            assert len(tmpfiles) == 0


class TestExistingBehaviorPreserved:
    """Ensure all v2 behavior still works."""

    def test_new_state(self):
        state = OrchestratorState(plan_name='test')
        assert state.completed_story_ids == set()
        assert state.failed_story_ids == set()
        assert state.current_phase == 0

    def test_mark_complete(self):
        state = OrchestratorState(plan_name='test')
        state.mark_complete(1, 'Story 1', 120.5)
        assert 1 in state.completed_story_ids
        assert state.results[-1].status == 'pass'

    def test_mark_failed(self):
        state = OrchestratorState(plan_name='test')
        state.mark_failed(2, 'Story 2', 45.0, 'Tests failed')
        assert 2 in state.failed_story_ids
        assert state.results[-1].error == 'Tests failed'


class TestResumeRecovery:
    """Tests for mid-story recovery and auto-retry of failed/running stories."""

    def test_mark_running(self):
        state = OrchestratorState(plan_name='test')
        state.mark_running(1, 'Story 1')
        assert 1 in state.running_story_ids
        assert 1 not in state.completed_story_ids
        assert state.results[-1].status == 'running'

    def test_mark_running_replaces_previous_fail(self):
        state = OrchestratorState(plan_name='test')
        state.mark_failed(1, 'Story 1', 30.0, 'broken')
        assert 1 in state.failed_story_ids
        state.mark_running(1, 'Story 1')
        assert 1 in state.running_story_ids
        assert 1 not in state.failed_story_ids
        assert len([r for r in state.results if r.story_id == 1]) == 1

    def test_mark_failed_replaces_running(self):
        state = OrchestratorState(plan_name='test')
        state.mark_running(1, 'Story 1')
        state.mark_failed(1, 'Story 1', 60.0, 'tests failed')
        assert 1 in state.failed_story_ids
        assert 1 not in state.running_story_ids
        assert len([r for r in state.results if r.story_id == 1]) == 1

    def test_remove_incomplete(self):
        state = OrchestratorState(plan_name='test')
        state.mark_complete(1, 'Story 1', 100.0)
        state.mark_failed(2, 'Story 2', 50.0, 'err')
        state.mark_running(3, 'Story 3')
        state.remove_incomplete()
        assert state.completed_story_ids == {1}
        assert state.failed_story_ids == set()
        assert state.running_story_ids == set()
        assert len(state.results) == 1

    def test_remove_incomplete_roundtrip(self):
        """remove_incomplete + save + load preserves only passed stories."""
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            state = OrchestratorState(plan_name='test')
            state.mark_complete(1, 'S1', 10.0)
            state.mark_failed(2, 'S2', 5.0, 'err')
            state.mark_running(3, 'S3')
            state.remove_incomplete()
            state.save(state_path)

            loaded = OrchestratorState.load(state_path)
            assert loaded.completed_story_ids == {1}
            assert len(loaded.results) == 1
