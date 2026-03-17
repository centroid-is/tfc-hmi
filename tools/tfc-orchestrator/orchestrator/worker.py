"""Worker pool — worktree-isolated parallel story execution."""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import IO, TYPE_CHECKING

if TYPE_CHECKING:
    from .models import Story, Plan, RetryConfig

logger = logging.getLogger(__name__)


def _checkpoint_review(
    story_name: str,
    story_id: int,
    cwd: str,
    log_path: str,
    elapsed_seconds: float,
    extension_number: int,
    max_extensions: int,
) -> bool:
    """Ask a reviewer Claude whether a running story should get more time.

    Returns True to extend, False to kill.
    """
    # Gather evidence: git diff (what changed) + log tail (what it's doing)
    try:
        diff = subprocess.run(
            ['git', 'diff', '--stat', 'HEAD'],
            cwd=cwd, capture_output=True, text=True, timeout=10,
        ).stdout.strip()[:2000]
    except Exception:
        diff = '(could not read git diff)'

    try:
        log_tail = Path(log_path).read_text()[-3000:]
    except Exception:
        log_tail = '(could not read log)'

    prompt = (
        f"You are a checkpoint reviewer for an autonomous coding agent.\n\n"
        f"Story {story_id}: {story_name}\n"
        f"Elapsed: {elapsed_seconds / 60:.0f} minutes\n"
        f"Extension: {extension_number} of {max_extensions}\n\n"
        f"## Git diff --stat (work done so far):\n```\n{diff}\n```\n\n"
        f"## Recent log output (last ~3000 chars):\n```\n{log_tail}\n```\n\n"
        f"## Decision\n"
        f"Is the agent making meaningful progress? Consider:\n"
        f"- Is it creating/editing files relevant to the story?\n"
        f"- Is it stuck in a loop (repeating the same action)?\n"
        f"- Is it making forward progress toward the goal?\n\n"
        f"Reply with EXACTLY one line:\n"
        f"EXTEND — if the agent is making progress and should continue\n"
        f"KILL — if the agent is stuck, looping, or not making progress"
    )

    try:
        result = subprocess.run(
            ['claude', '-p', prompt, '--model', 'haiku',
             '--output-format', 'text', '--max-turns', '1'],
            capture_output=True, text=True, timeout=60,
        )
        verdict = result.stdout.strip().upper()
        logger.info(
            'Checkpoint review for story %d (ext %d/%d): %s',
            story_id, extension_number, max_extensions, verdict[:100],
        )
        return verdict.startswith('EXTEND')
    except Exception as e:
        logger.warning('Checkpoint review failed for story %d: %s', story_id, e)
        # On review failure, be generous — extend
        return True


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


def _stream_json_to_log(pipe: IO[str], log_file_handle: IO[str]):
    """Read stream-json from Claude's stdout pipe and write readable progress to log.

    stream-json format: newline-delimited JSON objects. Key message types:
    - {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
    - {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{...}}]}}
    - {"type":"result","subtype":"success","result":"final text",...}

    Extracts and writes:
    - Text output lines as-is
    - Tool calls as: [ToolName] brief description
    - Results as: --- Result: success | N turns | $X.XX | Ns ---
    - Unrecognized event types as: [type] (for debugging)
    """
    for raw_line in pipe:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            event = json.loads(raw_line)
        except (json.JSONDecodeError, ValueError):
            log_file_handle.write(raw_line + '\n')
            log_file_handle.flush()
            continue

        etype = event.get('type', '')

        if etype == 'assistant':
            msg = event.get('message', {})
            for block in msg.get('content', []):
                btype = block.get('type', '')
                if btype == 'text':
                    text = block.get('text', '')
                    if text.strip():
                        log_file_handle.write(text)
                        if not text.endswith('\n'):
                            log_file_handle.write('\n')
                        log_file_handle.flush()
                elif btype == 'tool_use':
                    name = block.get('name', '?')
                    inp = block.get('input', {})
                    if name in ('Read', 'Write', 'Edit'):
                        desc = inp.get('file_path', '')
                    elif name == 'Bash':
                        desc = inp.get('command', '')[:80]
                    elif name in ('Glob', 'Grep'):
                        desc = inp.get('pattern', '')
                    else:
                        desc = str(inp)[:80]
                    log_file_handle.write(f'[{name}] {desc}\n')
                    log_file_handle.flush()

        elif etype == 'result':
            subtype = event.get('subtype', '')
            cost = event.get('cost_usd', 0)
            duration = event.get('duration_ms', 0)
            turns = event.get('num_turns', 0)
            log_file_handle.write(
                f'\n--- Result: {subtype} | {turns} turns | '
                f'${cost:.2f} | {duration / 1000:.0f}s ---\n'
            )
            result_text = event.get('result', '')
            if result_text:
                log_file_handle.write(result_text)
                if not result_text.endswith('\n'):
                    log_file_handle.write('\n')
            log_file_handle.flush()

        else:
            # Log unrecognized event types for debugging
            log_file_handle.write(f'[{etype}] {str(event)[:120]}\n')
            log_file_handle.flush()


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

    def _is_valid_worktree(self, wt_path: str) -> bool:
        """Check if a directory is a valid git worktree (has .git file and is tracked)."""
        git_file = Path(wt_path) / '.git'
        if not git_file.exists():
            return False
        # Verify git recognizes it as a worktree
        result = subprocess.run(
            ['git', 'rev-parse', '--git-dir'],
            cwd=wt_path, capture_output=True, text=True, timeout=10,
        )
        return result.returncode == 0

    def _create_worktree(self, story_id: int) -> tuple[str, str]:
        """Create a git worktree for a story, or reuse if valid. Returns (branch_name, worktree_path)."""
        branch = f'{self._branch_prefix()}/story-{story_id}'
        wt_path = str(self._worktree_dir() / f'story-{story_id}')

        # Reuse existing worktree ONLY if it's a valid git worktree
        if Path(wt_path).exists():
            if self._is_valid_worktree(wt_path):
                return branch, wt_path
            # Stale/broken directory — remove it before recreating
            logger.warning('Removing broken worktree remnant at %s', wt_path)
            subprocess.run(
                ['git', 'worktree', 'remove', wt_path, '--force'],
                cwd=self.project_dir, capture_output=True, timeout=30,
            )
            # If git worktree remove didn't clean it, force-remove the dir
            if Path(wt_path).exists():
                import shutil
                shutil.rmtree(wt_path, ignore_errors=True)

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
        # Auto-commit any dirty files on the base branch (e.g. generated files
        # left by a previous story's merge) so git merge doesn't refuse.
        subprocess.run(
            ['git', 'add', '-A'],
            cwd=self.project_dir, capture_output=True, timeout=30,
        )
        status = subprocess.run(
            ['git', 'diff', '--cached', '--quiet'],
            cwd=self.project_dir, capture_output=True, timeout=10,
        )
        if status.returncode != 0:
            subprocess.run(
                ['git', 'commit', '-m',
                 'chore(orchestrator): auto-commit dirty files before merge'],
                cwd=self.project_dir, capture_output=True, text=True, timeout=30,
            )
            logger.info('Auto-committed dirty files on base branch before merge')

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
        setup_cmds: list[str] | None = None,
        dry_run: bool = False,
    ) -> WorkerResult:
        """Execute a story in an isolated worktree. Respects semaphore for concurrency limiting."""
        async with self._semaphore:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(
                None, self._run_story_sync, story, plan, validate_cmds,
                setup_cmds or [], dry_run,
            )

    def _run_story_sync(
        self,
        story: Story,
        plan: Plan,
        validate_cmds: list[str],
        setup_cmds: list[str],
        dry_run: bool,
    ) -> WorkerResult:
        """Synchronous story execution with retry loop.

        Flow: create worktree → setup deps → (run claude → validate → retry if failed) → merge → cleanup.
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

        # 2. Setup: run explicit setup commands + auto-install missing deps
        self._setup_worktree(wt_path, setup_cmds, events)

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

    def _setup_worktree(self, wt_path: str, setup_cmds: list[str], events: list[str]):
        """Run setup commands and auto-install dependencies in a worktree.

        Self-healing: scans for dependency manifests (package.json, pyproject.toml,
        pubspec.yaml) where the install directory is missing, and runs the
        appropriate install command automatically.
        """
        # Run explicit setup commands first
        for cmd in setup_cmds:
            result = subprocess.run(
                cmd, shell=True, cwd=wt_path,
                capture_output=True, text=True, timeout=300,
            )
            if result.returncode == 0:
                events.append(f'setup_ok:{cmd[:50]}')
            else:
                logger.warning('Setup command failed in %s: %s → %s',
                               wt_path, cmd, result.stderr[:200])
                events.append(f'setup_fail:{cmd[:50]}')

        # Auto-detect and install missing dependencies
        self._auto_install_deps(wt_path, events)

    def _auto_install_deps(self, wt_path: str, events: list[str]):
        """Scan worktree for dependency manifests and install if deps dir is missing.

        Supports: npm (package.json), pip (pyproject.toml/requirements.txt),
        dart/flutter (pubspec.yaml).
        """
        wt = Path(wt_path)

        # Find all package.json files (npm/node projects)
        for pkg_json in wt.rglob('package.json'):
            # Skip node_modules to avoid false positives
            if 'node_modules' in pkg_json.parts:
                continue
            pkg_dir = pkg_json.parent
            if not (pkg_dir / 'node_modules').exists():
                logger.info('Auto-installing npm deps: %s', pkg_dir)
                result = subprocess.run(
                    ['npm', 'install'],
                    cwd=str(pkg_dir), capture_output=True, text=True, timeout=120,
                )
                if result.returncode == 0:
                    events.append(f'auto_npm_install:{pkg_dir.name}')
                else:
                    logger.warning('npm install failed in %s: %s',
                                   pkg_dir, result.stderr[:200])

        # Find pyproject.toml or requirements.txt (Python projects)
        for marker in wt.rglob('pyproject.toml'):
            if '.venv' in marker.parts or 'node_modules' in marker.parts:
                continue
            pkg_dir = marker.parent
            venv_dir = pkg_dir / '.venv'
            if venv_dir.exists():
                # venv exists but may need deps installed
                pip = venv_dir / 'bin' / 'pip'
                if pip.exists():
                    result = subprocess.run(
                        [str(pip), 'install', '-e', '.', '-q'],
                        cwd=str(pkg_dir), capture_output=True, text=True, timeout=120,
                    )
                    if result.returncode == 0:
                        events.append(f'auto_pip_install:{pkg_dir.name}')

        # Find pubspec.yaml (Dart/Flutter projects)
        for pubspec in wt.rglob('pubspec.yaml'):
            if '.dart_tool' in pubspec.parts or 'node_modules' in pubspec.parts:
                continue
            pkg_dir = pubspec.parent
            if not (pkg_dir / '.dart_tool').exists():
                # Try flutter first, fall back to dart
                for cmd in [['flutter', 'pub', 'get'], ['dart', 'pub', 'get']]:
                    result = subprocess.run(
                        cmd, cwd=str(pkg_dir), capture_output=True, text=True, timeout=120,
                    )
                    if result.returncode == 0:
                        events.append(f'auto_pub_get:{pkg_dir.name}')
                        break

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
        """Run claude -p in the given directory. Returns (exit_code, error).

        Uses --output-format stream-json and parses output in a reader thread
        to write human-readable progress to the log file in real-time.
        """
        # Wrap story prompt with worktree isolation context
        wrapped_prompt = (
            f"## Environment\n"
            f"You are working in an isolated git worktree at: {cwd}\n"
            f"This worktree is a FULL copy of the repository.\n"
            f"CRITICAL: Do ALL work within this directory. NEVER cd to "
            f"{self.project_dir} or any other directory outside the worktree.\n"
            f"All file paths in the task below are relative to the repo root, "
            f"which is this worktree directory.\n\n"
            f"## Task: Story {story.id} — {story.name}\n"
            f"{story.prompt}"
        )
        cmd = [
            'claude', '-p', wrapped_prompt,
            '--model', plan.model,
            '--allowedTools', plan.allowed_tools,
            '--max-turns', str(plan.max_turns),
            '--output-format', 'stream-json',
            '--verbose',
            '--dangerously-skip-permissions',
        ]

        log_base = self._log_dir() / f'story_{story.id}'
        stdout_path = f'{log_base}.stdout.log'
        stderr_path = f'{log_base}.stderr.log'

        proc = None
        stdout_log = open(stdout_path, 'w')
        stderr_log = open(stderr_path, 'w')
        start_time = time.time()
        try:
            proc = subprocess.Popen(
                cmd, cwd=cwd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=stderr_log,
                text=True, start_new_session=True,
            )
            reader = threading.Thread(
                target=_stream_json_to_log,
                args=(proc.stdout, stdout_log),
                daemon=True,
            )
            reader.start()

            # Checkpoint loop: run for timeout, then ask reviewer
            interval = story.timeout
            extensions_used = 0
            while True:
                try:
                    proc.wait(timeout=interval)
                    # Process finished naturally
                    break
                except subprocess.TimeoutExpired:
                    elapsed = time.time() - start_time
                    if extensions_used >= story.max_extensions:
                        logger.info(
                            'Story %d: max extensions (%d) reached after %.0fs, killing',
                            story.id, story.max_extensions, elapsed,
                        )
                        _kill_process_tree(proc)
                        return 124, (
                            f'Timeout after {elapsed:.0f}s '
                            f'({extensions_used} extensions exhausted)'
                        )

                    extensions_used += 1
                    logger.info(
                        'Story %d: checkpoint review (extension %d/%d, %.0fm elapsed)',
                        story.id, extensions_used, story.max_extensions,
                        elapsed / 60,
                    )
                    should_extend = _checkpoint_review(
                        story_name=story.name,
                        story_id=story.id,
                        cwd=cwd,
                        log_path=stdout_path,
                        elapsed_seconds=elapsed,
                        extension_number=extensions_used,
                        max_extensions=story.max_extensions,
                    )
                    if should_extend:
                        logger.info(
                            'Story %d: reviewer approved extension %d/%d',
                            story.id, extensions_used, story.max_extensions,
                        )
                        continue
                    else:
                        logger.info(
                            'Story %d: reviewer denied extension, killing',
                            story.id,
                        )
                        _kill_process_tree(proc)
                        return 124, (
                            f'Killed by checkpoint reviewer after {elapsed:.0f}s '
                            f'(extension {extensions_used} denied)'
                        )

            reader.join(timeout=5)
            stderr = Path(stderr_path).read_text()
            return proc.returncode, stderr if proc.returncode != 0 else ''
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
