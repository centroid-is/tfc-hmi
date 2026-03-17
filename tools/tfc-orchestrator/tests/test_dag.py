"""Tests for DAG scheduler — node management, ready queue, cascade skip, cycle detection."""
import pytest

from orchestrator.dag import DAGNode, DAGScheduler, NodeStatus


class TestDAGNode:
    def test_node_defaults(self):
        node = DAGNode(story_id=1)
        assert node.story_id == 1
        assert node.depends_on == []
        assert node.status == NodeStatus.PENDING
        assert node.validate == []

    def test_node_with_deps(self):
        node = DAGNode(story_id=3, depends_on=[1, 2])
        assert node.depends_on == [1, 2]

    def test_node_with_validate(self):
        node = DAGNode(story_id=1, validate=['dart test'])
        assert node.validate == ['dart test']


class TestDAGSchedulerConstruction:
    def test_empty_scheduler(self):
        sched = DAGScheduler([])
        assert sched.ready_stories() == []
        assert sched.all_done

    def test_single_node_is_ready(self):
        nodes = [DAGNode(story_id=1)]
        sched = DAGScheduler(nodes)
        assert sched.ready_stories() == [1]

    def test_independent_nodes_all_ready(self):
        nodes = [DAGNode(story_id=i) for i in [1, 4, 5]]
        sched = DAGScheduler(nodes)
        assert set(sched.ready_stories()) == {1, 4, 5}

    def test_dependent_node_not_ready(self):
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
        ]
        sched = DAGScheduler(nodes)
        assert sched.ready_stories() == [1]


class TestDAGSchedulerWorkflow:
    def _mqtt_dag(self) -> DAGScheduler:
        """Build the mqtt_web DAG:
        1 → 2 → 3 → 8,9 → 10
        1 → 5 → 6 → 7
        2 → 4
        7,10 → 11
        """
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
            DAGNode(story_id=3, depends_on=[2]),
            DAGNode(story_id=4, depends_on=[2]),
            DAGNode(story_id=5, depends_on=[1]),
            DAGNode(story_id=6, depends_on=[5]),
            DAGNode(story_id=7, depends_on=[5, 6]),
            DAGNode(story_id=8, depends_on=[3]),
            DAGNode(story_id=9, depends_on=[3]),
            DAGNode(story_id=10, depends_on=[8, 9]),
            DAGNode(story_id=11, depends_on=[7, 10]),
        ]
        return DAGScheduler(nodes)

    def test_initial_ready_is_story_1(self):
        sched = self._mqtt_dag()
        assert sched.ready_stories() == [1]

    def test_after_story_1_passes(self):
        sched = self._mqtt_dag()
        sched.mark_running(1)
        sched.mark_passed(1)
        ready = set(sched.ready_stories())
        assert ready == {2, 5}

    def test_after_stories_1_2_pass(self):
        sched = self._mqtt_dag()
        sched.mark_running(1)
        sched.mark_passed(1)
        sched.mark_running(2)
        sched.mark_running(5)
        sched.mark_passed(2)
        sched.mark_passed(5)
        ready = set(sched.ready_stories())
        assert ready == {3, 4, 6}

    def test_full_execution_order(self):
        """Walk through the full DAG and ensure all stories complete."""
        sched = self._mqtt_dag()
        executed = []
        while not sched.all_done:
            ready = sched.ready_stories()
            assert ready, f"Deadlock: no ready stories, executed={executed}"
            for sid in ready:
                sched.mark_running(sid)
            for sid in ready:
                sched.mark_passed(sid)
                executed.append(sid)
        assert set(executed) == set(range(1, 12))

    def test_running_stories_not_in_ready(self):
        """A story marked RUNNING should not appear in ready_stories()."""
        sched = self._mqtt_dag()
        sched.mark_running(1)
        assert sched.ready_stories() == []

    def test_all_done_false_until_complete(self):
        sched = self._mqtt_dag()
        assert not sched.all_done
        sched.mark_running(1)
        assert not sched.all_done


class TestDAGCascadeSkip:
    def test_failure_cascades_to_dependents(self):
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
            DAGNode(story_id=3, depends_on=[2]),
        ]
        sched = DAGScheduler(nodes)
        sched.mark_running(1)
        sched.mark_failed(1)

        # Stories 2 and 3 should be skipped
        assert sched.get_status(2) == NodeStatus.SKIPPED
        assert sched.get_status(3) == NodeStatus.SKIPPED
        assert sched.ready_stories() == []
        assert sched.all_done

    def test_failure_only_cascades_to_dependents(self):
        """Stories not dependent on the failed one remain schedulable."""
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
            DAGNode(story_id=3),  # independent
        ]
        sched = DAGScheduler(nodes)
        sched.mark_running(1)
        sched.mark_running(3)
        sched.mark_failed(1)
        assert sched.get_status(2) == NodeStatus.SKIPPED
        assert sched.get_status(3) == NodeStatus.RUNNING

    def test_partial_dependency_failure(self):
        """If one of multiple deps fails, the dependent is skipped."""
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2),
            DAGNode(story_id=3, depends_on=[1, 2]),
        ]
        sched = DAGScheduler(nodes)
        sched.mark_running(1)
        sched.mark_running(2)
        sched.mark_failed(1)
        sched.mark_passed(2)
        assert sched.get_status(3) == NodeStatus.SKIPPED


class TestDAGCycleDetection:
    def test_simple_cycle_raises(self):
        nodes = [
            DAGNode(story_id=1, depends_on=[2]),
            DAGNode(story_id=2, depends_on=[1]),
        ]
        with pytest.raises(ValueError, match="[Cc]ycle"):
            DAGScheduler(nodes)

    def test_self_cycle_raises(self):
        nodes = [DAGNode(story_id=1, depends_on=[1])]
        with pytest.raises(ValueError, match="[Cc]ycle"):
            DAGScheduler(nodes)

    def test_long_cycle_raises(self):
        nodes = [
            DAGNode(story_id=1, depends_on=[3]),
            DAGNode(story_id=2, depends_on=[1]),
            DAGNode(story_id=3, depends_on=[2]),
        ]
        with pytest.raises(ValueError, match="[Cc]ycle"):
            DAGScheduler(nodes)

    def test_valid_dag_passes(self):
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
            DAGNode(story_id=3, depends_on=[1]),
            DAGNode(story_id=4, depends_on=[2, 3]),
        ]
        sched = DAGScheduler(nodes)  # Should not raise
        assert sched.ready_stories() == [1]


class TestDAGFromPlan:
    def test_from_plan_flattens_phases(self):
        """from_plan() should flatten all phases into a single DAG."""
        from orchestrator.models import Plan, Phase, Story

        plan = Plan(
            name='test',
            project_dir='/tmp',
            model='sonnet',
            phases=[
                Phase(name='P1', stories=[
                    Story(id=1, name='s1', prompt='p'),
                    Story(id=2, name='s2', prompt='p', depends_on=[1]),
                ], validate=['dart test']),
                Phase(name='P2', stories=[
                    Story(id=3, name='s3', prompt='p', depends_on=[2]),
                ]),
            ],
        )
        sched = DAGScheduler.from_plan(plan)
        assert sched.ready_stories() == [1]
        sched.mark_running(1)
        sched.mark_passed(1)
        assert sched.ready_stories() == [2]

    def test_from_plan_inherits_phase_validate(self):
        """Nodes should inherit their phase's validate commands."""
        from orchestrator.models import Plan, Phase, Story

        plan = Plan(
            name='test',
            project_dir='/tmp',
            model='sonnet',
            phases=[
                Phase(name='P1', stories=[
                    Story(id=1, name='s1', prompt='p'),
                ], validate=['dart test', 'dart analyze']),
            ],
        )
        sched = DAGScheduler.from_plan(plan)
        node = sched.get_node(1)
        assert node.validate == ['dart test', 'dart analyze']

    def test_from_plan_story_checks_override_phase(self):
        """Story acceptance_checks should override phase validate."""
        from orchestrator.models import Plan, Phase, Story

        plan = Plan(
            name='test',
            project_dir='/tmp',
            model='sonnet',
            phases=[
                Phase(name='P1', stories=[
                    Story(id=1, name='s1', prompt='p',
                          acceptance_checks=['custom check']),
                ], validate=['dart test']),
            ],
        )
        sched = DAGScheduler.from_plan(plan)
        node = sched.get_node(1)
        assert node.validate == ['custom check']


class TestDAGSummary:
    def test_summary_shows_counts(self):
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
            DAGNode(story_id=3, depends_on=[1]),
        ]
        sched = DAGScheduler(nodes)
        sched.mark_running(1)
        sched.mark_passed(1)
        summary = sched.summary()
        assert summary['total'] == 3
        assert summary['passed'] == 1
        assert summary['pending'] == 2

    def test_failed_and_skipped_in_summary(self):
        nodes = [
            DAGNode(story_id=1),
            DAGNode(story_id=2, depends_on=[1]),
        ]
        sched = DAGScheduler(nodes)
        sched.mark_running(1)
        sched.mark_failed(1)
        summary = sched.summary()
        assert summary['failed'] == 1
        assert summary['skipped'] == 1
