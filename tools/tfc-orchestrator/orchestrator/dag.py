"""DAG scheduler — dependency graph for story execution ordering."""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import Plan


class NodeStatus(Enum):
    PENDING = 'pending'
    RUNNING = 'running'
    PASSED = 'passed'
    FAILED = 'failed'
    SKIPPED = 'skipped'


@dataclass
class DAGNode:
    story_id: int
    depends_on: list[int] = field(default_factory=list)
    status: NodeStatus = NodeStatus.PENDING
    validate: list[str] = field(default_factory=list)
    setup: list[str] = field(default_factory=list)


class DAGScheduler:
    """Manages a dependency graph of stories, scheduling ready ones and cascading failures."""

    def __init__(self, nodes: list[DAGNode]):
        self._nodes: dict[int, DAGNode] = {n.story_id: n for n in nodes}
        # Build reverse dependency map (dependents: who depends on me)
        self._dependents: dict[int, list[int]] = {n.story_id: [] for n in nodes}
        for n in nodes:
            for dep in n.depends_on:
                if dep in self._dependents:
                    self._dependents[dep].append(n.story_id)

        if nodes:
            self._check_cycles()

    def _check_cycles(self):
        """Detect cycles using Kahn's algorithm (topological sort)."""
        in_degree: dict[int, int] = {sid: 0 for sid in self._nodes}
        for node in self._nodes.values():
            for dep in node.depends_on:
                if dep in in_degree:
                    in_degree[node.story_id] += 1

        queue = deque(sid for sid, deg in in_degree.items() if deg == 0)
        visited = 0

        while queue:
            sid = queue.popleft()
            visited += 1
            for dependent in self._dependents.get(sid, []):
                in_degree[dependent] -= 1
                if in_degree[dependent] == 0:
                    queue.append(dependent)

        if visited != len(self._nodes):
            remaining = [sid for sid, deg in in_degree.items() if deg > 0]
            raise ValueError(
                f"Cycle detected in DAG: stories {remaining} form a cycle"
            )

    def ready_stories(self) -> list[int]:
        """Return story IDs that are PENDING with all deps satisfied (PASSED)."""
        ready = []
        for node in self._nodes.values():
            if node.status != NodeStatus.PENDING:
                continue
            deps_satisfied = all(
                self._nodes[dep].status == NodeStatus.PASSED
                for dep in node.depends_on
                if dep in self._nodes
            )
            if deps_satisfied:
                ready.append(node.story_id)
        return sorted(ready)

    def mark_running(self, story_id: int):
        self._nodes[story_id].status = NodeStatus.RUNNING

    def mark_passed(self, story_id: int):
        self._nodes[story_id].status = NodeStatus.PASSED

    def mark_failed(self, story_id: int):
        self._nodes[story_id].status = NodeStatus.FAILED
        self._cascade_skip(story_id)

    def _cascade_skip(self, failed_id: int):
        """Skip all transitive dependents of a failed story."""
        queue = deque(self._dependents.get(failed_id, []))
        while queue:
            sid = queue.popleft()
            node = self._nodes[sid]
            if node.status in (NodeStatus.PENDING, ):
                node.status = NodeStatus.SKIPPED
                queue.extend(self._dependents.get(sid, []))

    def get_status(self, story_id: int) -> NodeStatus:
        return self._nodes[story_id].status

    def get_node(self, story_id: int) -> DAGNode:
        return self._nodes[story_id]

    @property
    def all_done(self) -> bool:
        return all(
            n.status in (NodeStatus.PASSED, NodeStatus.FAILED, NodeStatus.SKIPPED)
            for n in self._nodes.values()
        )

    def summary(self) -> dict[str, int]:
        counts: dict[str, int] = {
            'total': 0, 'pending': 0, 'running': 0,
            'passed': 0, 'failed': 0, 'skipped': 0,
        }
        for node in self._nodes.values():
            counts['total'] += 1
            counts[node.status.value] += 1
        return counts

    @classmethod
    def from_plan(cls, plan: Plan) -> DAGScheduler:
        """Flatten all phases into a single DAG."""
        nodes = []
        for phase in plan.phases:
            for story in phase.stories:
                validate = story.acceptance_checks or phase.validate
                nodes.append(DAGNode(
                    story_id=story.id,
                    depends_on=list(story.depends_on),
                    validate=list(validate),
                    setup=list(phase.setup),
                ))
        return cls(nodes)
