"""Worker pool — worktree-isolated parallel story execution."""
from __future__ import annotations

import asyncio
import logging
import os
import signal
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import Story, Plan, RetryConfig

logger = logging.getLogger(__name__)


def _kill_process_tree(proc: subprocess.Popen | None):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
    except (ProcessLookupError, ChildProcessError):
        pass
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=3)
        except (ProcessLookupError, ChildProcessError, subprocess.TimeoutExpired):
            pass


@dataclass
class WorkerResult:
    story_id: int
    exit_code: int
    duration: float
    worktree_branch: str = ''
    merge_commit: str = ''
    error: str = ''
    events: list[str] = field(default_factory=list)
    retry_count: int = 0

    @property
    def success(self) -> bool:
        return self.exit_code == 0


def _story_with_prompt(story: Story, prompt: str) -> Story:
    """Create a copy of a Story with a different prompt."""
    from .models import Story as StoryModel
    return StoryModel(
        id=story.id,
        name=story.name,
        prompt=prompt,
        depends_on=story.depends_on,
        acceptance_checks=story.acceptance_checks,
    )


class WorkerPool:
    """Manages concurrent story execution in git worktrees."""

    def __init__(
        self,
        max_workers: int,
        project_dir: str,
        plan_name: str = '',
    ):
        self.max_workers = max_workers
        self.project_dir = project_dir
        self.plan_name = plan_name
        self._semaphore = asyncio.Semaphore(max_workers)
        self._merge_lock = threading.Lock()
        self._snapshot_done = False

    def _worktree_dir(self) -> Path:
        parts = [Path(self.project_dir) / '.orchestrator' / 'worktrees']
        if self.plan_name:
            parts = [parts[0] / self.plan_name]
        d = parts[0]
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _log_dir(self) -> Path:
        parts = [Path(self.project_dir) / '.orchestrator' / 'logs']
        if self.plan_name:
            parts = [parts[0] / self.plan_name]
        d = parts[0]
        d.mkdir(parents=True, exist_ok=True)
        return d

    def _branch_prefix(self) -> str:
        if self.plan_name:
            return f'orchestrator/{self.plan_name}'
        return 'orchestrator'

    def snapshot_working_tree(self):
        """Commit any outstanding changes so worktrees created from HEAD include them.

        This is critical for resume scenarios: if prior stories ran without
        worktree isolation (or their merge was lost), their output exists only
        as untracked/modified files. This snapshot commit captures them.

        Also handles gitignored-but-needed artifacts: if a story created
        build artifacts that were never committed, they'd be missing from
        worktrees. The snapshot includes everything via --no-ignore-removal.

        Safe to call multiple times — no-ops if nothing to commit.
        """
        if self._snapshot_done:
            return

        # Stage all changes (tracked + untracked)
        subprocess.run(
            ['git', 'add', '-A'],
            cwd=self.project_dir, capture_output=True, timeout=30,
        )

        # Check if there's anything to commit
        status = subprocess.run(
            ['git', 'status', '--porcelain'],
            cwd=self.project_dir, capture_output=True, text=True, timeout=10,
        )
        if status.stdout.strip():
            result = subprocess.run(
                ['git', 'commit', '-m',
                 f'chore(orchestrator): snapshot working tree before worktree dispatch\n\n'
                 f'Auto-commit by tfc-orchestrator to ensure worktrees\n'
                 f'contain all prior story outputs.'],
                cwd=self.project_dir, capture_output=True, text=True, timeout=30,
            )
            if result.returncode == 0:
                logger.info('Snapshot commit created for working tree')
            else:
                logger.warning('Snapshot commit failed: %s', result.stderr[:200])

        self._snapshot_done = True

    def _create_worktree(self, story_id: int) -> tuple[str, str]:
        """Create a git worktree for a story, or reuse if it exists. Returns (branch_name, worktree_path)."""
        branch = f'{self._branch_prefix()}/story-{story_id}'
        wt_path = str(self._worktree_dir() / f'story-{story_id}')

        # Reuse existing worktree from interrupted run
        if Path(wt_path).exists():
            return branch, wt_path

        # Ensure HEAD contains all prior work
        self.snapshot_working_tree()

        # Create branch from HEAD
        result = subprocess.run(
            ['git', 'branch', '-f', branch, 'HEAD'],
            cwd=self.project_dir, capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f'Failed to create branch {branch}: {result.stderr[:200]}'
            )

        # Create worktree
        result = subprocess.run(
            ['git', 'worktree', 'add', wt_path, branch],
            cwd=self.project_dir, capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f'Failed to create worktree at {wt_path}: {result.stderr[:200]}'
            )

        return branch, wt_path

    def _commit_worktree(self, wt_path: str, story) -> bool:
        """Stage and commit all changes in a worktree. Returns True if committed."""
        subprocess.run(
            ['git', 'add', '-A'],
            cwd=wt_path, capture_output=True, timeout=30,
        )
        # Check if there's anything to commit
        status = subprocess.run(
            ['git', 'status', '--porcelain'],
            cwd=wt_path, capture_output=True, text=True, timeout=10,
        )
        if not status.stdout.strip():
            return False  # Nothing to commit
        result = subprocess.run(
            ['git', 'commit', '-m', f'feat: Story {story.id} — {story.name}'],
            cwd=wt_path, capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            logger.warning('Commit in worktree %s failed: %s', wt_path, result.stderr[:200])
            return False
        return True

    def _cleanup_worktree(self, wt_path: str):
        """Remove a git worktree and its branch."""
        subprocess.run(
            ['git', 'worktree', 'remove', wt_path, '--force'],
            cwd=self.project_dir, capture_output=True, timeout=30,
        )

    def _merge_branch(self, branch: str, plan: 'Plan | None' = None) -> tuple[str | None, str]:
        """Merge a worktree branch back. On conflict, invokes Claude to resolve."""
        result = subprocess.run(
            ['git', 'merge', branch, '--no-edit'],
            cwd=self.project_dir, capture_output=True, text=True, timeout=60,
        )
        if result.returncode != 0:
            error_detail = (result.stdout + result.stderr)[:500]
            # Try Claude-assisted conflict resolution
            if plan and self._resolve_conflicts_with_claude(branch, error_detail, plan):
                rev = subprocess.run(
                    ['git', 'rev-parse', 'HEAD'],
                    cwd=self.project_dir, capture_output=True, text=True, timeout=10,
                )
                return rev.stdout.strip(), ''
            # Claude couldn't fix it — abort
            subprocess.run(
                ['git', 'merge', '--abort'],
                cwd=self.project_dir, capture_output=True, timeout=30,
            )
            return None, error_detail

        # Get the merge commit hash
        rev = subprocess.run(
            ['git', 'rev-parse', 'HEAD'],
            cwd=self.project_dir, capture_output=True, text=True, timeout=10,
        )
        return rev.stdout.strip(), ''

    def _resolve_conflicts_with_claude(self, branch: str, conflict_output: str, plan: 'Plan') -> bool:
        """Invoke Claude to resolve merge conflicts. Returns True if resolved."""
        # Get list of conflicted files
        status = subprocess.run(
            ['git', 'diff', '--name-only', '--diff-filter=U'],
            cwd=self.project_dir, capture_output=True, text=True, timeout=10,
        )
        conflicted_files = status.stdout.strip()
        if not conflicted_files:
            return False

        prompt = (
            f"You are resolving a git merge conflict.\n\n"
            f"Branch `{branch}` is being merged into the current branch.\n"
            f"Conflicted files:\n{conflicted_files}\n\n"
            f"Merge output:\n{conflict_output}\n\n"
            f"Instructions:\n"
            f"1. Read each conflicted file and resolve the conflict markers (<<<<<<< ======= >>>>>>>)\n"
            f"2. Keep both sides' changes where possible — the intent is to combine work from parallel stories\n"
            f"3. After resolving, run: git add <file> for each resolved file\n"
            f"4. Then run: git commit --no-edit\n"
            f"5. Do NOT abort the merge\n"
        )

        log_base = self._log_dir() / 'merge_conflict'
        stdout_log = open(f'{log_base}.stdout.log', 'w')
        stderr_log = open(f'{log_base}.stderr.log', 'w')

        proc = None
        try:
            proc = subprocess.Popen(
                [
                    'claude', '-p', prompt,
                    '--model', plan.model,
                    '--allowedTools', 'Bash,Read,Edit,Write,Glob,Grep',
                    '--max-turns', '50',
                    '--output-format', 'text',
                    '--dangerously-skip-permissions',
                ],
                cwd=self.project_dir,
                stdin=subprocess.DEVNULL,
                stdout=stdout_log, stderr=stderr_log,
                text=True, start_new_session=True,
            )
            proc.wait(timeout=300)

            if proc.returncode != 0:
                return False

            # Check if merge was completed (no more conflicts)
            check = subprocess.run(
                ['git', 'diff', '--name-only', '--diff-filter=U'],
                cwd=self.project_dir, capture_output=True, text=True, timeout=10,
            )
            return check.stdout.strip() == ''

        except (subprocess.TimeoutExpired, Exception):
            _kill_process_tree(proc)
            return False
        finally:
            stdout_log.close()
            stderr_log.close()

    async def run_story(
        self,
        story: Story,
        plan: Plan,
        validate_cmds: list[str],
        dry_run: bool = False,
    ) -> WorkerResult:
        """Execute a story in an isolated worktree. Respects semaphore for concurrency limiting."""
        async with self._semaphore:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(
                None, self._run_story_sync, story, plan, validate_cmds, dry_run,
            )

    def _run_story_sync(
        self,
        story: Story,
        plan: Plan,
        validate_cmds: list[str],
        dry_run: bool,
    ) -> WorkerResult:
        """Synchronous story execution with retry loop.

        Flow: create worktree → (run claude → validate → retry if failed) → merge → cleanup.
        On validation failure, re-runs claude with the error as context so it can fix the issues.
        """
        if dry_run:
            return WorkerResult(
                story_id=story.id, exit_code=0, duration=0.0,
                worktree_branch=f'{self._branch_prefix()}/story-{story.id}',
            )

        max_attempts = plan.retry.max_attempts
        start = time.time()
        events: list[str] = []

        # 1. Create worktree
        branch, wt_path = self._create_worktree(story.id)
        events.append(f'worktree_created:{wt_path}')

        try:
            last_error = ''
            for attempt in range(1, max_attempts + 1):
                # 2. Run claude -p in the worktree
                if attempt == 1:
                    exit_code, error = self._execute_claude(story, plan, wt_path)
                else:
                    # Retry: feed the validation error back to claude
                    from .prompts import build_retry_prompt
                    retry_prompt = build_retry_prompt(
                        original_prompt=story.prompt,
                        error_output=last_error,
                        attempt=attempt,
                    )
                    retry_story = _story_with_prompt(story, retry_prompt)
                    events.append(f'retry:{attempt}')
                    exit_code, error = self._execute_claude(retry_story, plan, wt_path)

                if exit_code != 0:
                    last_error = error
                    if attempt < max_attempts:
                        events.append(f'claude_failed:{attempt}')
                        continue
                    self._cleanup_worktree(wt_path)
                    return WorkerResult(
                        story_id=story.id, exit_code=exit_code,
                        duration=time.time() - start,
                        worktree_branch=branch, error=error, events=events,
                        retry_count=attempt - 1,
                    )

                # 3. Run validation in worktree
                validation_error = self._run_validation(validate_cmds, wt_path)
                if validation_error:
                    last_error = validation_error
                    events.append(f'validation_failed:{attempt}')
                    if attempt < max_attempts:
                        continue
                    self._cleanup_worktree(wt_path)
                    return WorkerResult(
                        story_id=story.id, exit_code=1,
                        duration=time.time() - start,
                        worktree_branch=branch, error=validation_error,
                        events=events, retry_count=attempt - 1,
                    )

                events.append('validation_passed')
                break  # Success — proceed to merge

            # 4. Commit all changes in worktree
            self._commit_worktree(wt_path, story)
            events.append('committed')

            # 5. Merge back (serialized)
            merge_commit, merge_error = self._merge_sync(branch, plan)
            if merge_commit is None:
                self._cleanup_worktree(wt_path)
                return WorkerResult(
                    story_id=story.id, exit_code=1,
                    duration=time.time() - start,
                    worktree_branch=branch,
                    error=f'Merge conflict:\n{merge_error}',
                    events=events,
                )
            events.append(f'merged:{merge_commit}')

            # 6. Cleanup worktree
            self._cleanup_worktree(wt_path)
            events.append('cleanup_done')

            retry_count = max(0, len([e for e in events if e.startswith('retry:')]))
            return WorkerResult(
                story_id=story.id, exit_code=0,
                duration=time.time() - start,
                worktree_branch=branch, merge_commit=merge_commit,
                events=events, retry_count=retry_count,
            )

        except Exception as e:
            try:
                self._cleanup_worktree(wt_path)
            except Exception:
                pass
            return WorkerResult(
                story_id=story.id, exit_code=1,
                duration=time.time() - start,
                worktree_branch=branch, error=str(e), events=events,
            )

    def _run_validation(self, validate_cmds: list[str], cwd: str) -> str | None:
        """Run validation commands. Returns error string on failure, None on success."""
        if not validate_cmds:
            return None
        for cmd in validate_cmds:
            vr = subprocess.run(
                cmd, shell=True, cwd=cwd,
                capture_output=True, text=True, timeout=300,
            )
            if vr.returncode != 0:
                output = vr.stdout[-500:] if vr.stdout else ''
                stderr = vr.stderr[:500] if vr.stderr else ''
                return f'Validation failed: {cmd}\n{stderr}\n{output}'.strip()
        return None

    def _execute_claude(
        self, story: Story, plan: Plan, cwd: str,
    ) -> tuple[int, str]:
        """Run claude -p in the given directory. Returns (exit_code, error)."""
        cmd = [
            'claude', '-p', story.prompt,
            '--model', plan.model,
            '--allowedTools', plan.allowed_tools,
            '--max-turns', str(plan.max_turns),
            '--output-format', 'text',
            '--dangerously-skip-permissions',
        ]

        log_base = self._log_dir() / f'story_{story.id}'
        stdout_path = f'{log_base}.stdout.log'
        stderr_path = f'{log_base}.stderr.log'

        proc = None
        stdout_log = open(stdout_path, 'w')
        stderr_log = open(stderr_path, 'w')
        try:
            proc = subprocess.Popen(
                cmd, cwd=cwd,
                stdin=subprocess.DEVNULL,
                stdout=stdout_log, stderr=stderr_log,
                text=True, start_new_session=True,
            )
            proc.wait(timeout=1800)
            stderr = Path(stderr_path).read_text()
            return proc.returncode, stderr if proc.returncode != 0 else ''
        except subprocess.TimeoutExpired:
            _kill_process_tree(proc)
            return 124, 'Timeout after 1800s'
        except KeyboardInterrupt:
            _kill_process_tree(proc)
            raise
        finally:
            stdout_log.close()
            stderr_log.close()

    def _merge_sync(self, branch: str, plan: 'Plan | None' = None) -> tuple[str | None, str]:
        """Thread-safe merge using threading lock (called from thread pool)."""
        with self._merge_lock:
            return self._merge_branch(branch, plan)

    def cleanup_stale(self):
        """Recover work from stale worktrees, then remove them.

        On crashed runs, worktrees may contain committed work that was never
        merged back to the main branch. This method detects such work and
        merges it before cleanup, preventing data loss.
        """
        wt_dir = self._worktree_dir()
        if not wt_dir.exists():
            return
        for entry in wt_dir.iterdir():
            if entry.is_dir():
                self._recover_and_cleanup_worktree(str(entry))

    def _recover_and_cleanup_worktree(self, wt_path: str):
        """Try to recover committed work from a stale worktree before removing it."""
        wt_name = Path(wt_path).name
        branch = f'{self._branch_prefix()}/{wt_name}'

        # Check if there are uncommitted changes that need saving
        status = subprocess.run(
            ['git', 'status', '--porcelain'],
            cwd=wt_path, capture_output=True, text=True, timeout=10,
        )
        if status.returncode == 0 and status.stdout.strip():
            # Has uncommitted work — commit it
            subprocess.run(
                ['git', 'add', '-A'],
                cwd=wt_path, capture_output=True, timeout=30,
            )
            subprocess.run(
                ['git', 'commit', '-m',
                 f'chore(orchestrator): recover uncommitted work from {wt_name}'],
                cwd=wt_path, capture_output=True, timeout=30,
            )

        # Check if the worktree branch has commits ahead of HEAD
        try:
            ahead = subprocess.run(
                ['git', 'rev-list', '--count', f'HEAD..{branch}'],
                cwd=self.project_dir, capture_output=True, text=True, timeout=10,
            )
            if ahead.returncode == 0 and int(ahead.stdout.strip() or '0') > 0:
                # Branch has work not in HEAD — merge it
                logger.info('Recovering %d commit(s) from stale worktree %s',
                            int(ahead.stdout.strip()), wt_name)
                with self._merge_lock:
                    merge_result, error = self._merge_branch(branch)
                    if merge_result:
                        logger.info('Recovered stale worktree %s (merged %s)',
                                    wt_name, merge_result[:8])
                    else:
                        logger.warning('Could not merge stale worktree %s: %s',
                                       wt_name, error[:200])
        except (ValueError, subprocess.TimeoutExpired):
            pass

        self._cleanup_worktree(wt_path)
