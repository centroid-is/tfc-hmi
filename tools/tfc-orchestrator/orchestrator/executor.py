"""Execute stories via claude CLI in headless mode."""
import hashlib
import logging
import os
import signal
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from .models import Story, Plan
from .worker import _checkpoint_review

logger = logging.getLogger(__name__)


def _kill_process_tree(proc: subprocess.Popen | None):
    """Kill a process and its entire process group."""
    if proc is None:
        return
    try:
        # Kill the entire process group (claude + any children)
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
class ExecutionResult:
    story_id: int
    exit_code: int
    stdout: str
    stderr: str
    duration_seconds: float

    @property
    def success(self) -> bool:
        return self.exit_code == 0


def commit_story(story_id: int, story_name: str, project_dir: str, dry_run: bool = False) -> bool:
    """Git add + commit after a story passes. Returns True on success."""
    if dry_run:
        return True

    try:
        # Stage tracked file changes
        subprocess.run(
            ['git', 'add', '-u'],
            cwd=project_dir, capture_output=True, timeout=30,
        )
        # Stage new files only in packages/ and lib/ (avoid unrelated untracked files)
        for subdir in ['packages/', 'lib/', 'test/']:
            subprocess.run(
                ['git', 'add', subdir],
                cwd=project_dir, capture_output=True, timeout=30,
            )
        msg = f"feat(mqtt): Story {story_id} — {story_name}\n\nAutomated commit by tfc-orchestrator"
        result = subprocess.run(
            ['git', 'commit', '-m', msg, '--allow-empty'],
            cwd=project_dir, capture_output=True, text=True, timeout=30,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def _log_dir(project_dir: str, plan_name: str = '') -> Path:
    d = Path(project_dir) / '.orchestrator' / 'logs'
    if plan_name:
        d = d / plan_name
    d.mkdir(parents=True, exist_ok=True)
    return d


def execute_story(
    story: Story,
    plan: Plan,
    dry_run: bool = False,
) -> ExecutionResult:
    """Execute a single story via `claude -p`."""
    if dry_run:
        return ExecutionResult(
            story_id=story.id,
            exit_code=0,
            stdout=f'[DRY RUN] Story {story.id}: {story.name}',
            stderr='',
            duration_seconds=0.0,
        )

    cmd = [
        'claude', '-p', story.prompt,
        '--model', plan.model,
        '--allowedTools', plan.allowed_tools,
        '--max-turns', str(plan.max_turns),
        '--output-format', 'text',
        '--dangerously-skip-permissions',
    ]

    log_base = _log_dir(plan.project_dir, plan.name) / f'story_{story.id}'
    stdout_path = f'{log_base}.stdout.log'
    stderr_path = f'{log_base}.stderr.log'

    start = time.time()
    proc = None
    stdout_log = open(stdout_path, 'w')
    stderr_log = open(stderr_path, 'w')
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=plan.project_dir,
            stdin=subprocess.DEVNULL,  # prevent hanging on permission prompts
            stdout=stdout_log,
            stderr=stderr_log,
            text=True,
            start_new_session=True,  # own process group for clean cleanup
        )

        # Checkpoint loop: run for timeout, then ask reviewer
        interval = story.timeout
        extensions_used = 0
        while True:
            try:
                proc.wait(timeout=interval)
                break
            except subprocess.TimeoutExpired:
                elapsed = time.time() - start
                if extensions_used >= story.max_extensions:
                    _kill_process_tree(proc)
                    return ExecutionResult(
                        story_id=story.id, exit_code=124, stdout='',
                        stderr=f'Timeout after {elapsed:.0f}s ({extensions_used} extensions exhausted)',
                        duration_seconds=elapsed,
                    )

                extensions_used += 1
                logger.info(
                    'Story %d: checkpoint review (extension %d/%d, %.0fm elapsed)',
                    story.id, extensions_used, story.max_extensions, elapsed / 60,
                )
                should_extend = _checkpoint_review(
                    story_name=story.name,
                    story_id=story.id,
                    cwd=plan.project_dir,
                    log_path=stdout_path,
                    elapsed_seconds=elapsed,
                    extension_number=extensions_used,
                    max_extensions=story.max_extensions,
                )
                if should_extend:
                    continue
                else:
                    _kill_process_tree(proc)
                    return ExecutionResult(
                        story_id=story.id, exit_code=124, stdout='',
                        stderr=f'Killed by checkpoint reviewer after {elapsed:.0f}s',
                        duration_seconds=elapsed,
                    )

        stdout_log.close()
        stderr_log.close()
        stdout = Path(stdout_path).read_text()
        stderr = Path(stderr_path).read_text()
        duration = time.time() - start
        return ExecutionResult(
            story_id=story.id,
            exit_code=proc.returncode,
            stdout=stdout,
            stderr=stderr,
            duration_seconds=duration,
        )
    except KeyboardInterrupt:
        _kill_process_tree(proc)
        raise
    finally:
        stdout_log.close()
        stderr_log.close()


def run_acceptance_checks(
    checks: list[str],
    project_dir: str,
    dry_run: bool = False,
) -> tuple[bool, str]:
    """Run acceptance check commands. Returns (passed, error_output)."""
    if dry_run or not checks:
        return True, ''

    errors = []
    for cmd in checks:
        result = subprocess.run(
            cmd, shell=True, cwd=project_dir,
            capture_output=True, text=True, timeout=300,
        )
        if result.returncode != 0:
            errors.append(f"Check failed: {cmd}\n{result.stderr[:500]}")

    if errors:
        return False, '\n'.join(errors)
    return True, ''


def get_git_diff_hash(project_dir: str) -> str:
    """Get hash of current git diff for circuit breaker detection."""
    try:
        result = subprocess.run(
            ['git', 'diff', 'HEAD'],
            cwd=project_dir, capture_output=True, text=True, timeout=30,
        )
        return hashlib.sha256(result.stdout.encode()).hexdigest()[:16]
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ''


def execute_with_retry(
    story: Story,
    plan: Plan,
    phase_validate: list[str],
    dry_run: bool = False,
) -> ExecutionResult:
    """Execute a story with retry loop and acceptance checks.

    Uses story.acceptance_checks if set, else falls back to phase_validate.
    Implements circuit breaker: if git diff hash unchanged between retries, stop.
    """
    from .prompts import build_retry_prompt

    checks = story.acceptance_checks or phase_validate
    retry_config = plan.retry
    last_diff_hash = ''
    last_result = None

    for attempt in range(1, retry_config.max_attempts + 1):
        if attempt == 1:
            result = execute_story(story, plan, dry_run)
        else:
            # Build retry prompt with error context
            error_context = last_result.stderr[:2000] if last_result else ''
            retry_prompt = build_retry_prompt(
                story.prompt, error_context, attempt,
            )
            retry_story = Story(
                id=story.id, name=story.name, prompt=retry_prompt,
            )
            result = execute_story(retry_story, plan, dry_run)

        if not result.success:
            last_result = result
            continue

        # Story execution passed -- now run acceptance checks
        passed, error_output = run_acceptance_checks(
            checks, plan.project_dir, dry_run,
        )
        if passed:
            return result

        # Acceptance checks failed
        result = ExecutionResult(
            story_id=result.story_id,
            exit_code=1,
            stdout=result.stdout,
            stderr=f"Acceptance checks failed:\n{error_output}",
            duration_seconds=result.duration_seconds,
        )
        last_result = result

        # Circuit breaker: check if code changed
        if retry_config.circuit_breaker and not dry_run:
            current_hash = get_git_diff_hash(plan.project_dir)
            if current_hash and current_hash == last_diff_hash:
                result = ExecutionResult(
                    story_id=story.id, exit_code=1,
                    stdout=result.stdout,
                    stderr=f"Circuit breaker: no code change between attempts. {result.stderr}",
                    duration_seconds=result.duration_seconds,
                )
                return result
            last_diff_hash = current_hash

    return last_result or result
