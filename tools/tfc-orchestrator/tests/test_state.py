"""Tests for state tracking — save, load, resume, mark complete/failed."""
import json
import tempfile
from pathlib import Path

from orchestrator.state import OrchestratorState, StoryResult


class TestOrchestratorState:
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
        assert state.results[-1].duration_seconds == 120.5

    def test_mark_failed(self):
        state = OrchestratorState(plan_name='test')
        state.mark_failed(2, 'Story 2', 45.0, 'Tests failed')
        assert 2 in state.failed_story_ids
        assert state.results[-1].error == 'Tests failed'

    def test_save_and_load_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'

            state = OrchestratorState(plan_name='mqtt-web')
            state.current_phase = 2
            state.mark_complete(1, 'Story 1', 100.0)
            state.mark_complete(2, 'Story 2', 200.0)
            state.mark_failed(3, 'Story 3', 50.0, 'compile error')
            state.save(state_path)

            loaded = OrchestratorState.load(state_path)
            assert loaded.plan_name == 'mqtt-web'
            assert loaded.current_phase == 2
            assert loaded.completed_story_ids == {1, 2}
            assert loaded.failed_story_ids == {3}
            assert len(loaded.results) == 3

    def test_save_creates_parent_dirs(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'nested' / 'deep' / 'state.json'
            state = OrchestratorState(plan_name='test')
            state.save(state_path)
            assert state_path.exists()

    def test_load_nonexistent_raises(self):
        import pytest
        with pytest.raises(FileNotFoundError):
            OrchestratorState.load('/nonexistent/state.json')

    def test_mark_complete_replaces_previous_fail(self):
        """If a story fails then passes on retry, only the pass is kept."""
        state = OrchestratorState(plan_name='test')
        state.mark_failed(1, 'Story 1', 30.0, 'first attempt')
        state.mark_complete(1, 'Story 1', 60.0)
        assert 1 in state.completed_story_ids
        assert 1 not in state.failed_story_ids
        assert len(state.results) == 1

    def test_saved_json_is_readable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'
            state = OrchestratorState(plan_name='test')
            state.mark_complete(1, 'Story 1', 100.0)
            state.save(state_path)

            raw = json.loads(state_path.read_text())
            assert raw['plan_name'] == 'test'
            assert len(raw['results']) == 1
            assert raw['results'][0]['status'] == 'pass'


class TestStoryResultV2Fields:
    def test_new_fields_default_to_zero(self):
        result = StoryResult(story_id=1, story_name='s1', status='pass')
        assert result.retry_count == 0
        assert result.review_iterations == 0
        assert result.review_findings == 0

    def test_save_load_roundtrip_preserves_new_fields(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / 'state.json'

            state = OrchestratorState(plan_name='v2-test')
            state.results.append(StoryResult(
                story_id=1,
                story_name='Story 1',
                status='pass',
                duration_seconds=90.0,
                retry_count=2,
                review_iterations=3,
                review_findings=5,
            ))
            state.save(state_path)

            loaded = OrchestratorState.load(state_path)
            r = loaded.results[0]
            assert r.retry_count == 2
            assert r.review_iterations == 3
            assert r.review_findings == 5
