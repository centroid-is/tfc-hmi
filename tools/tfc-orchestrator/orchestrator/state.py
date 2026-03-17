"""State tracking — save/load/resume across runs. Thread-safe (v3)."""
import json
import os
import tempfile
import threading
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


@dataclass
class StoryResult:
    story_id: int
    story_name: str
    status: str  # 'pass' or 'fail'
    duration_seconds: float = 0.0
    error: str = ''
    timestamp: str = field(
        default_factory=lambda: datetime.now().isoformat()
    )
    # v2 fields
    retry_count: int = 0
    review_iterations: int = 0
    review_findings: int = 0
    # v3 fields
    worktree_branch: str = ''
    merge_commit: str = ''
    verification_passed: bool | None = None
    verification_details: str = ''
    started_at: str = ''
    worker_slot: int = -1


@dataclass
class OrchestratorState:
    plan_name: str
    results: list[StoryResult] = field(default_factory=list)
    current_phase: int = 0
    started_at: str = field(
        default_factory=lambda: datetime.now().isoformat()
    )

    def __post_init__(self):
        self._lock = threading.Lock()

    @property
    def completed_story_ids(self) -> set[int]:
        with self._lock:
            return {r.story_id for r in self.results if r.status == 'pass'}

    @property
    def failed_story_ids(self) -> set[int]:
        with self._lock:
            return {r.story_id for r in self.results if r.status == 'fail'}

    @property
    def running_story_ids(self) -> set[int]:
        with self._lock:
            return {r.story_id for r in self.results if r.status == 'running'}

    def mark_running(self, story_id: int, name: str):
        with self._lock:
            # Remove any prior result for this story (e.g. previous fail)
            self.results = [r for r in self.results if r.story_id != story_id]
            self.results.append(StoryResult(
                story_id=story_id,
                story_name=name,
                status='running',
                started_at=datetime.now().isoformat(),
            ))

    def remove_incomplete(self):
        """Remove all non-pass results so they can be re-dispatched."""
        with self._lock:
            self.results = [r for r in self.results if r.status == 'pass']

    def mark_complete(self, story_id: int, name: str, duration: float):
        with self._lock:
            self.results = [r for r in self.results if r.story_id != story_id]
            self.results.append(StoryResult(
                story_id=story_id,
                story_name=name,
                status='pass',
                duration_seconds=duration,
            ))

    def mark_failed(
        self, story_id: int, name: str, duration: float, error: str,
    ):
        with self._lock:
            self.results = [r for r in self.results if r.story_id != story_id]
            self.results.append(StoryResult(
                story_id=story_id,
                story_name=name,
                status='fail',
                duration_seconds=duration,
                error=error,
            ))

    def save(self, path: str | Path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)

        with self._lock:
            data = {
                'version': 3,
                'plan_name': self.plan_name,
                'current_phase': self.current_phase,
                'started_at': self.started_at,
                'results': [
                    {
                        'story_id': r.story_id,
                        'story_name': r.story_name,
                        'status': r.status,
                        'duration_seconds': r.duration_seconds,
                        'error': r.error,
                        'timestamp': r.timestamp,
                        'retry_count': r.retry_count,
                        'review_iterations': r.review_iterations,
                        'review_findings': r.review_findings,
                        'worktree_branch': r.worktree_branch,
                        'merge_commit': r.merge_commit,
                        'verification_passed': r.verification_passed,
                        'verification_details': r.verification_details,
                        'started_at': r.started_at,
                        'worker_slot': r.worker_slot,
                    }
                    for r in self.results
                ],
            }

        # Atomic write: write to temp file, then rename
        fd, tmp_path = tempfile.mkstemp(
            dir=str(path.parent), suffix='.tmp',
        )
        try:
            with os.fdopen(fd, 'w') as f:
                json.dump(data, f, indent=2)
            os.replace(tmp_path, str(path))
        except BaseException:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise

    @classmethod
    def load(cls, path: str | Path) -> 'OrchestratorState':
        with open(path) as f:
            data = json.load(f)
        state = cls(
            plan_name=data['plan_name'],
            current_phase=data['current_phase'],
            started_at=data['started_at'],
        )
        for r in data.get('results', []):
            state.results.append(StoryResult(
                story_id=r['story_id'],
                story_name=r['story_name'],
                status=r['status'],
                duration_seconds=r.get('duration_seconds', 0.0),
                error=r.get('error', ''),
                timestamp=r.get('timestamp', ''),
                retry_count=r.get('retry_count', 0),
                review_iterations=r.get('review_iterations', 0),
                review_findings=r.get('review_findings', 0),
                # v3 fields with backward-compat defaults
                worktree_branch=r.get('worktree_branch', ''),
                merge_commit=r.get('merge_commit', ''),
                verification_passed=r.get('verification_passed', None),
                verification_details=r.get('verification_details', ''),
                started_at=r.get('started_at', ''),
                worker_slot=r.get('worker_slot', -1),
            ))
        return state
