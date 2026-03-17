"""Tests for plan models — parsing, dependency waves, validation."""
import tempfile
from pathlib import Path

import pytest
import yaml

from orchestrator.models import (
    Plan, Phase, Story,
    RetryConfig, ReviewConfig, ReviewerDef, GsdConfig,
    WorkersConfig, VerificationConfig,
)


class TestStory:
    def test_story_defaults(self):
        s = Story(id=1, name="test", prompt="do stuff")
        assert s.depends_on == []

    def test_story_with_deps(self):
        s = Story(id=2, name="test", prompt="do stuff", depends_on=[1])
        assert s.depends_on == [1]


class TestPhaseExecutionWaves:
    def test_single_story_one_wave(self):
        phase = Phase(name="p1", stories=[
            Story(id=1, name="s1", prompt="p"),
        ])
        waves = phase.execution_waves()
        assert len(waves) == 1
        assert [s.id for s in waves[0]] == [1]

    def test_independent_stories_one_wave(self):
        """Stories with no deps between them run in one wave (parallel)."""
        phase = Phase(name="p1", stories=[
            Story(id=4, name="s4", prompt="p", depends_on=[2]),
            Story(id=5, name="s5", prompt="p", depends_on=[1]),
        ])
        # depends_on=[2] and [1] are outside this phase, so both are wave 1
        waves = phase.execution_waves()
        assert len(waves) == 1
        assert {s.id for s in waves[0]} == {4, 5}

    def test_sequential_deps_within_phase(self):
        """Stories depending on each other within a phase create multiple waves."""
        phase = Phase(name="p1", stories=[
            Story(id=1, name="s1", prompt="p"),
            Story(id=2, name="s2", prompt="p", depends_on=[1]),
            Story(id=3, name="s3", prompt="p", depends_on=[2]),
        ])
        waves = phase.execution_waves()
        assert len(waves) == 3
        assert [s.id for s in waves[0]] == [1]
        assert [s.id for s in waves[1]] == [2]
        assert [s.id for s in waves[2]] == [3]

    def test_diamond_dependency(self):
        """Diamond: 1 -> 2,3 -> 4. Should be 3 waves."""
        phase = Phase(name="p1", stories=[
            Story(id=1, name="s1", prompt="p"),
            Story(id=2, name="s2", prompt="p", depends_on=[1]),
            Story(id=3, name="s3", prompt="p", depends_on=[1]),
            Story(id=4, name="s4", prompt="p", depends_on=[2, 3]),
        ])
        waves = phase.execution_waves()
        assert len(waves) == 3
        assert [s.id for s in waves[0]] == [1]
        assert {s.id for s in waves[1]} == {2, 3}
        assert [s.id for s in waves[2]] == [4]

    def test_circular_dependency_raises(self):
        phase = Phase(name="p1", stories=[
            Story(id=1, name="s1", prompt="p", depends_on=[2]),
            Story(id=2, name="s2", prompt="p", depends_on=[1]),
        ])
        with pytest.raises(ValueError, match="Circular dependency"):
            phase.execution_waves()


class TestPlanFromYaml:
    def _write_yaml(self, data: dict) -> str:
        f = tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False)
        yaml.dump(data, f)
        f.close()
        return f.name

    def test_minimal_plan(self):
        path = self._write_yaml({
            'name': 'test-plan',
            'project_dir': '/tmp/test',
            'model': 'sonnet',
            'phases': [{
                'name': 'Phase 1',
                'stories': [{
                    'id': 1,
                    'name': 'Do thing',
                    'prompt': 'Do the thing',
                }],
            }],
        })
        plan = Plan.from_yaml(path)
        assert plan.name == 'test-plan'
        assert plan.model == 'sonnet'
        assert len(plan.phases) == 1
        assert plan.phases[0].stories[0].prompt == 'Do the thing'

    def test_default_model_is_opus(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'}
            ]}],
        })
        plan = Plan.from_yaml(path)
        assert plan.model == 'opus'

    def test_dependencies_parsed(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
                {'id': 2, 'name': 's2', 'prompt': 'p', 'depends_on': [1]},
            ]}],
        })
        plan = Plan.from_yaml(path)
        assert plan.phases[0].stories[1].depends_on == [1]

    def test_auto_prompt_when_missing(self):
        """When no prompt given, generate one referencing ralph-plan.md."""
        path = self._write_yaml({
            'name': 'test',
            'project_dir': '/tmp/proj',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 3, 'name': 'MQTT adapter'},
            ]}],
        })
        plan = Plan.from_yaml(path)
        prompt = plan.phases[0].stories[0].prompt
        assert 'Story 3' in prompt
        assert 'MQTT adapter' in prompt
        assert 'ralph-plan.md' in prompt
        assert 'TDD' in prompt

    def test_per_phase_validate_commands(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{
                'name': 'P1',
                'validate': ['dart test', 'dart analyze'],
                'stories': [{'id': 1, 'name': 's1', 'prompt': 'p'}],
            }],
        })
        plan = Plan.from_yaml(path)
        assert plan.phases[0].validate == ['dart test', 'dart analyze']

    def test_phase_validate_defaults_empty(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{
                'name': 'P1',
                'stories': [{'id': 1, 'name': 's1', 'prompt': 'p'}],
            }],
        })
        plan = Plan.from_yaml(path)
        assert plan.phases[0].validate == []

    def test_prompt_file_support(self):
        """prompt_file loads prompt from external file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            prompt_path = Path(tmpdir) / 'story1.md'
            prompt_path.write_text('Execute story 1 with TDD')

            plan_data = {
                'name': 'test',
                'phases': [{'name': 'P1', 'stories': [{
                    'id': 1, 'name': 's1',
                    'prompt_file': 'story1.md',
                }]}],
            }
            plan_path = Path(tmpdir) / 'plan.yaml'
            with open(plan_path, 'w') as f:
                yaml.dump(plan_data, f)

            plan = Plan.from_yaml(plan_path)
            assert plan.phases[0].stories[0].prompt == 'Execute story 1 with TDD'


class TestConfigDataclasses:
    """Tests for v2 config dataclasses: RetryConfig, ReviewConfig, GsdConfig."""

    def _write_yaml(self, data: dict) -> str:
        f = tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False)
        yaml.dump(data, f)
        f.close()
        return f.name

    # --- 1. RetryConfig defaults ---
    def test_retry_config_defaults(self):
        rc = RetryConfig()
        assert rc.max_attempts == 3
        assert rc.circuit_breaker is True

    # --- 2. ReviewConfig defaults ---
    def test_review_config_defaults(self):
        rc = ReviewConfig()
        assert rc.enabled is False
        assert rc.max_iterations == 3
        assert len(rc.reviewers) == 2
        assert rc.reviewers[0].role == 'flutter_architect'
        assert rc.reviewers[1].role == 'test_engineer'

    # --- 3. GsdConfig defaults ---
    def test_gsd_config_defaults(self):
        gc = GsdConfig()
        assert gc.enabled is False
        assert gc.discuss is True
        assert gc.plan is True
        assert gc.verify is True
        assert gc.ui_review == []

    # --- 4. Story.acceptance_checks default ---
    def test_story_acceptance_checks_default(self):
        s = Story(id=1, name='test', prompt='do stuff')
        assert s.acceptance_checks == []

    # --- 5. Plan.from_yaml parses retry ---
    def test_plan_from_yaml_parses_retry(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
            'retry': {
                'max_attempts': 5,
                'circuit_breaker': False,
            },
        })
        plan = Plan.from_yaml(path)
        assert plan.retry.max_attempts == 5
        assert plan.retry.circuit_breaker is False

    # --- 6. Plan.from_yaml parses review ---
    def test_plan_from_yaml_parses_review(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
            'review': {
                'enabled': True,
                'max_iterations': 5,
                'reviewers': [
                    {'role': 'custom_role', 'focus': 'custom focus area'},
                ],
            },
        })
        plan = Plan.from_yaml(path)
        assert plan.review.enabled is True
        assert plan.review.max_iterations == 5
        assert len(plan.review.reviewers) == 1
        assert plan.review.reviewers[0].role == 'custom_role'
        assert plan.review.reviewers[0].focus == 'custom focus area'

    # --- 7. Plan.from_yaml parses gsd ---
    def test_plan_from_yaml_parses_gsd(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
            'gsd': {
                'enabled': True,
                'discuss': False,
                'plan': True,
                'verify': False,
                'ui_review': ['Phase 1'],
            },
        })
        plan = Plan.from_yaml(path)
        assert plan.gsd.enabled is True
        assert plan.gsd.discuss is False
        assert plan.gsd.plan is True
        assert plan.gsd.verify is False
        assert plan.gsd.ui_review == ['Phase 1']

    # --- 8. Plan.from_yaml defaults when config blocks missing ---
    def test_plan_from_yaml_config_defaults_when_missing(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
        })
        plan = Plan.from_yaml(path)
        # retry defaults
        assert plan.retry.max_attempts == 3
        assert plan.retry.circuit_breaker is True
        # review defaults
        assert plan.review.enabled is False
        assert plan.review.max_iterations == 3
        assert len(plan.review.reviewers) == 2
        # gsd defaults
        assert plan.gsd.enabled is False
        assert plan.gsd.discuss is True
        assert plan.gsd.plan is True
        assert plan.gsd.verify is True
        assert plan.gsd.ui_review == []
        # v3 defaults
        assert plan.execution_mode == 'dag'
        assert plan.workers.max_parallel == 3
        assert plan.workers.worktree_isolation is True
        assert plan.verification.golden_tests is False
        assert plan.verification.marionette is False
        assert plan.verification.ai_design_review is False
        assert plan.verification.ui_stories == []
        assert plan.verification.route_map == {}


class TestV3ConfigDataclasses:
    """Tests for v3 config: WorkersConfig, VerificationConfig, execution_mode."""

    def _write_yaml(self, data: dict) -> str:
        f = tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False)
        yaml.dump(data, f)
        f.close()
        return f.name

    def test_workers_config_defaults(self):
        wc = WorkersConfig()
        assert wc.max_parallel == 3
        assert wc.worktree_isolation is True

    def test_verification_config_defaults(self):
        vc = VerificationConfig()
        assert vc.golden_tests is False
        assert vc.marionette is False
        assert vc.ai_design_review is False
        assert vc.ui_stories == []
        assert vc.route_map == {}

    def test_plan_from_yaml_parses_execution_mode(self):
        path = self._write_yaml({
            'name': 'test',
            'execution_mode': 'phase',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
        })
        plan = Plan.from_yaml(path)
        assert plan.execution_mode == 'phase'

    def test_plan_from_yaml_parses_workers(self):
        path = self._write_yaml({
            'name': 'test',
            'workers': {'max_parallel': 4, 'worktree_isolation': False},
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
        })
        plan = Plan.from_yaml(path)
        assert plan.workers.max_parallel == 4
        assert plan.workers.worktree_isolation is False

    def test_plan_from_yaml_parses_verification(self):
        path = self._write_yaml({
            'name': 'test',
            'verification': {
                'golden_tests': True,
                'marionette': True,
                'ai_design_review': False,
                'ui_stories': [6, 7, 8],
                'route_map': {7: ['/', '/prefs'], 10: ['/']},
            },
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
        })
        plan = Plan.from_yaml(path)
        assert plan.verification.golden_tests is True
        assert plan.verification.marionette is True
        assert plan.verification.ai_design_review is False
        assert plan.verification.ui_stories == [6, 7, 8]
        assert plan.verification.route_map == {7: ['/', '/prefs'], 10: ['/']}

    def test_plan_from_yaml_execution_mode_default_is_dag(self):
        path = self._write_yaml({
            'name': 'test',
            'phases': [{'name': 'P1', 'stories': [
                {'id': 1, 'name': 's1', 'prompt': 'p'},
            ]}],
        })
        plan = Plan.from_yaml(path)
        assert plan.execution_mode == 'dag'
