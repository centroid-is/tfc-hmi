"""Main orchestration loop — v3 DAG-based parallel execution with verification."""
import argparse
import asyncio
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from .dag import DAGScheduler, NodeStatus
from .executor import execute_with_retry, commit_story
from .models import Plan, Phase
from .reviewer import run_review_cycle
from .gsd import run_gsd_pre_phase, run_gsd_post_phase
from .state import OrchestratorState, StoryResult
from .verify import run_verification_gate
from .worker import WorkerPool, WorkerResult


def _fmt_duration(seconds: float) -> str:
    """Format seconds as human-readable duration (e.g., '2m 30s', '1h 5m')."""
    if seconds < 60:
        return f"{seconds:.0f}s"
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    if minutes < 60:
        return f"{minutes}m {secs}s"
    hours = minutes // 60
    mins = minutes % 60
    return f"{hours}h {mins}m"


class _ElapsedClock:
    """Background thread that prints elapsed time every interval."""

    def __init__(self, interval: int = 30):
        self._interval = interval
        self._start = time.time()
        self._label = ''
        self._stop_event = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self, label: str = ''):
        self._label = label
        self._start = time.time()
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def update_label(self, label: str):
        self._label = label

    def stop(self):
        self._stop_event.set()
        self._thread.join(timeout=2)

    def _run(self):
        while not self._stop_event.wait(self._interval):
            elapsed = time.time() - self._start
            label = f" [{self._label}]" if self._label else ""
            print(f"  ⏱  {_fmt_duration(elapsed)} elapsed{label}",
                  flush=True)


@dataclass
class RunResult:
    success: bool
    completed_stories: set[int] = field(default_factory=set)
    failed_stories: set[int] = field(default_factory=set)
    skipped_stories: set[int] = field(default_factory=set)
    stories_executed: set[int] = field(default_factory=set)


def run_validation(
    commands: list[str], project_dir: str, dry_run: bool = False,
) -> bool:
    """Run phase validation commands. Returns True if all pass."""
    if dry_run or not commands:
        return True

    for cmd in commands:
        result = subprocess.run(
            cmd, shell=True, cwd=project_dir,
            capture_output=True, text=True, timeout=300,
        )
        if result.returncode != 0:
            print(f"  │   Validation FAILED: {cmd}")
            print(f"  │   {result.stderr[:300]}")
            return False
    return True


def run_plan(
    plan_path: str,
    dry_run: bool = False,
    state_dir: str | None = None,
    max_parallel: int = 3,
    no_review: bool = False,
    no_gsd: bool = False,
    no_verify: bool = False,
) -> RunResult:
    """Execute a plan. Auto-resumes from existing state if present."""
    plan = Plan.from_yaml(plan_path)

    # v2.1 fallback for phase-based execution
    if plan.execution_mode == 'phase':
        from .cli_v2 import run_plan_v2
        # Auto-detect resume: if state file exists, resume
        _sd = state_dir or str(Path(plan.project_dir) / '.orchestrator')
        _has_state = (Path(_sd) / f'{plan.name}.state.json').exists()
        v2_result = run_plan_v2(
            plan_path, dry_run=dry_run, resume=_has_state,
            state_dir=state_dir, max_parallel=max_parallel,
            no_review=no_review, no_gsd=no_gsd,
        )
        return RunResult(
            success=v2_result.success,
            completed_stories=v2_result.completed_stories,
            failed_stories=v2_result.failed_stories,
            stories_executed=v2_result.stories_executed,
        )

    # v3 DAG-based execution
    return asyncio.run(_run_plan_dag(
        plan, plan_path, dry_run=dry_run,
        state_dir=state_dir, max_parallel=max_parallel,
        no_review=no_review, no_gsd=no_gsd, no_verify=no_verify,
    ))


async def _run_plan_dag(
    plan: Plan,
    plan_path: str,
    dry_run: bool = False,
    state_dir: str | None = None,
    max_parallel: int = 3,
    no_review: bool = False,
    no_gsd: bool = False,
    no_verify: bool = False,
) -> RunResult:
    """Execute a plan using DAG-based parallel scheduling. Auto-resumes from existing state."""
    if state_dir is None:
        state_dir = str(Path(plan.project_dir) / '.orchestrator')
    state_path = Path(state_dir) / f'{plan.name}.state.json'

    if state_path.exists():
        state = OrchestratorState.load(state_path)
        # Remove failed/running results so they get re-dispatched
        interrupted = state.running_story_ids
        failed = state.failed_story_ids
        state.remove_incomplete()
        state.save(state_path)
        if interrupted:
            print(f"  Recovering interrupted stories: {sorted(interrupted)}")
        if failed:
            print(f"  Retrying failed stories: {sorted(failed)}")
        if state.completed_story_ids:
            print(f"  Resuming (completed: {sorted(state.completed_story_ids)})")
    else:
        state = OrchestratorState(plan_name=plan.name)

    # Build DAG from plan
    dag = DAGScheduler.from_plan(plan)

    # Mark already-completed stories as passed in the DAG
    for sid in state.completed_story_ids:
        try:
            dag.mark_running(sid)
            dag.mark_passed(sid)
        except KeyError:
            pass

    # Build story lookup
    story_map = {}
    for phase in plan.phases:
        for story in phase.stories:
            story_map[story.id] = story

    # Effective max_parallel from plan.workers or CLI flag
    effective_parallel = plan.workers.max_parallel
    if max_parallel != 3:  # CLI override
        effective_parallel = max_parallel

    stories_executed: set[int] = set()
    total_start = time.time()

    print(f"\n{'=' * 55}")
    print(f"  tfc-orchestrator v3.0: {plan.name}")
    print(f"  Mode: DAG | Workers: {effective_parallel} | Model: {plan.model}"
          f" | {'DRY RUN' if dry_run else 'LIVE'}")
    summary = dag.summary()
    print(f"  Stories: {summary['total']} total, {summary['passed']} already done")
    print(f"{'=' * 55}\n")

    clock = _ElapsedClock(interval=30)
    clock.start(label="DAG dispatch")

    # DAG dispatch loop
    pending_futures: dict[asyncio.Task, int] = {}
    pool = WorkerPool(max_workers=effective_parallel, project_dir=plan.project_dir, plan_name=plan.name)

    # Recover work from stale worktrees, then clean up
    if not dry_run:
        pool.cleanup_stale()

    # Snapshot any uncommitted changes so worktrees include prior story outputs.
    # Critical for resume: if prior stories left untracked/uncommitted files,
    # new worktrees (created from HEAD) wouldn't contain them without this.
    if not dry_run and plan.workers.worktree_isolation:
        pool.snapshot_working_tree()

    while not dag.all_done:
        # Dispatch ready stories
        ready = dag.ready_stories()
        for sid in ready:
            if sid in state.completed_story_ids:
                continue
            story = story_map.get(sid)
            if story is None:
                dag.mark_passed(sid)
                continue

            dag.mark_running(sid)
            if not dry_run:
                state.mark_running(sid, story.name)
                state.save(state_path)
            node = dag.get_node(sid)
            clock.update_label(f"Story {sid}: {story.name}")
            print(f"  ├── Dispatching Story {sid}: {story.name}", flush=True)

            if plan.workers.worktree_isolation and not dry_run:
                # Use worker pool (worktree isolation)
                task = asyncio.create_task(
                    pool.run_story(story, plan, node.validate, node.setup, dry_run),
                )
            else:
                # Direct execution (no worktree)
                task = asyncio.create_task(
                    _run_story_direct(
                        story, plan, node.validate, state_dir,
                        dry_run, no_review,
                    ),
                )
            pending_futures[task] = sid

        if not pending_futures:
            # No pending work and not all done — check for stuck state
            if not dag.all_done:
                break
            continue

        # Wait for at least one to complete
        done, _ = await asyncio.wait(
            pending_futures.keys(),
            return_when=asyncio.FIRST_COMPLETED,
        )

        for task in done:
            sid = pending_futures.pop(task)
            result = task.result()
            story = story_map[sid]
            stories_executed.add(sid)

            if result.success:
                # Run verification if enabled
                verify_passed = None
                verify_details = ''
                if not no_verify:
                    vr = run_verification_gate(
                        plan.verification, plan.project_dir, sid, dry_run,
                    )
                    verify_passed = vr.passed if vr.golden_passed is not None else None
                    verify_details = vr.golden_details

                    if vr.golden_passed is False:
                        # Hard gate failure
                        dag.mark_failed(sid)
                        state.mark_failed(
                            sid, story.name, result.duration,
                            f"Verification failed: {vr.golden_details}",
                        )
                        dur = _fmt_duration(result.duration)
                        print(f"  │   └── Story {sid}: VERIFY FAIL ({dur})")
                        if not dry_run:
                            state.save(state_path)
                        continue

                # Run review if enabled (after merge, on main branch)
                review_iters = 0
                review_findings = 0
                if not no_review and plan.review.enabled:
                    ledger, review_iters = run_review_cycle(
                        story, plan, state_dir, dry_run,
                    )
                    review_findings = ledger.open_count

                # Commit if not using worktree (worktree already committed)
                if not plan.workers.worktree_isolation or dry_run:
                    commit_story(sid, story.name, plan.project_dir, dry_run)

                dag.mark_passed(sid)
                state.results = [r for r in state.results if r.story_id != sid]
                state.results.append(StoryResult(
                    story_id=sid,
                    story_name=story.name,
                    status='pass',
                    duration_seconds=result.duration,
                    review_iterations=review_iters,
                    review_findings=review_findings,
                    worktree_branch=result.worktree_branch,
                    merge_commit=result.merge_commit,
                    verification_passed=verify_passed,
                    verification_details=verify_details,
                ))

                dur = _fmt_duration(result.duration)
                extras = []
                if review_iters > 0:
                    extras.append(f"review:{review_iters}i")
                if verify_passed is not None:
                    extras.append("verified" if verify_passed else "verify-warn")
                extra_str = f" [{', '.join(extras)}]" if extras else ""
                print(f"  │   └── Story {sid}: PASS ({dur}){extra_str}", flush=True)
            else:
                dag.mark_failed(sid)
                state.mark_failed(
                    sid, story.name, result.duration, result.error[:500],
                )
                dur = _fmt_duration(result.duration)
                print(f"  │   └── Story {sid}: FAIL ({dur})", flush=True)
                if result.error:
                    print(f"  │       {result.error[:200]}", flush=True)

            if not dry_run:
                state.save(state_path)

    clock.stop()
    total_duration = time.time() - total_start

    # Final summary
    final = dag.summary()
    success = final['failed'] == 0 and final['skipped'] == 0

    print(f"\n{'=' * 55}")
    status = "ALL STORIES COMPLETE" if success else "COMPLETED WITH FAILURES"
    print(f"  {status} ({_fmt_duration(total_duration)})")
    print(f"  Passed: {final['passed']} | Failed: {final['failed']} | Skipped: {final['skipped']}")
    print(f"{'=' * 55}")

    # Story summary table
    print(f"\n  {'Story':<8}{'Name':<35}{'Status':<8}{'Time':<10}{'Review':<8}{'Verify':<8}")
    print(f"  {'-' * 84}")
    for r in sorted(state.results, key=lambda x: x.story_id):
        review_str = f"{r.review_iterations}i/{r.review_findings}f" if r.review_iterations else "-"
        if r.verification_passed is True:
            verify_str = "pass"
        elif r.verification_passed is False:
            verify_str = "FAIL"
        else:
            verify_str = "-"
        print(f"  {r.story_id:<8}{r.story_name[:33]:<35}"
              f"{r.status:<8}{_fmt_duration(r.duration_seconds):<10}"
              f"{review_str:<8}{verify_str:<8}")

    story_total = sum(r.duration_seconds for r in state.results)
    print(f"  {'-' * 84}")
    print(f"  {'Total':<8}{'':<35}{'':<8}{_fmt_duration(story_total):<10}")
    print(f"\n  Wall clock: {_fmt_duration(total_duration)}")

    skipped_ids = {
        sid for sid in story_map
        if dag.get_status(sid) == NodeStatus.SKIPPED
    }

    return RunResult(
        success=success,
        completed_stories=state.completed_story_ids,
        failed_stories=state.failed_story_ids,
        skipped_stories=skipped_ids,
        stories_executed=stories_executed,
    )


async def _run_story_direct(
    story, plan, validate_cmds, state_dir, dry_run, no_review,
) -> WorkerResult:
    """Run a story directly (no worktree isolation) — wraps execute_with_retry."""
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        None, execute_with_retry, story, plan, validate_cmds, dry_run,
    )
    return WorkerResult(
        story_id=story.id,
        exit_code=result.exit_code,
        duration=result.duration_seconds,
        error=result.stderr if not result.success else '',
    )


def show_status(plan_path: str, state_dir: str | None = None):
    plan = Plan.from_yaml(plan_path)
    if state_dir is None:
        state_dir = str(Path(plan.project_dir) / '.orchestrator')
    state_path = Path(state_dir) / f'{plan.name}.state.json'

    if not state_path.exists():
        print("No state found. Run 'run' or 'dry-run' first.")
        return

    state = OrchestratorState.load(state_path)
    total = sum(len(p.stories) for p in plan.phases)
    done = len(state.completed_story_ids)
    failed = len(state.failed_story_ids)

    print(f"\nPlan: {state.plan_name}")
    print(f"Mode: {plan.execution_mode}")
    print(f"Progress: {done}/{total} stories complete")
    if failed:
        print(f"Failed: {sorted(state.failed_story_ids)}")
    print(f"\nCompleted: {sorted(state.completed_story_ids)}")


def main():
    parser = argparse.ArgumentParser(
        description='tfc-orchestrator v3.1 — autonomous Claude Code execution with DAG parallelism',
    )
    parser.add_argument(
        'command',
        choices=['run', 'status', 'dry-run', 'dashboard', 'reset'],
    )
    parser.add_argument('plan', help='Path to plan YAML file')
    parser.add_argument(
        '--max-parallel', type=int, default=3,
        help='Max parallel stories (default: 3)',
    )
    parser.add_argument(
        '--host', default='127.0.0.1',
        help='Dashboard host (default: 127.0.0.1)',
    )
    parser.add_argument(
        '--port', type=int, default=8080,
        help='Dashboard port (default: 8080)',
    )
    parser.add_argument(
        '--no-review', action='store_true',
        help='Disable senior dev review layer',
    )
    parser.add_argument(
        '--no-gsd', action='store_true',
        help='Disable GSD integration (discuss/plan/verify/ui-review)',
    )
    parser.add_argument(
        '--no-verify', action='store_true',
        help='Disable verification gate (golden tests, marionette, AI review)',
    )

    args = parser.parse_args()

    try:
        if args.command == 'dry-run':
            result = run_plan(
                args.plan, dry_run=True,
                no_review=args.no_review, no_gsd=args.no_gsd,
                no_verify=args.no_verify,
            )
            sys.exit(0 if result.success else 1)
        elif args.command == 'run':
            result = run_plan(
                args.plan, max_parallel=args.max_parallel,
                no_review=args.no_review, no_gsd=args.no_gsd,
                no_verify=args.no_verify,
            )
            sys.exit(0 if result.success else 1)
        elif args.command == 'status':
            show_status(args.plan)
        elif args.command == 'dashboard':
            from .dashboard import run_dashboard
            plan_arg = Path(args.plan)
            if plan_arg.is_file():
                plans_dir = str(plan_arg.parent)
            else:
                plans_dir = str(plan_arg)
            run_dashboard(plans_dir, host=args.host, port=args.port)
        elif args.command == 'reset':
            plan = Plan.from_yaml(args.plan)
            state_path = Path(plan.project_dir) / '.orchestrator' / f'{plan.name}.state.json'
            if state_path.exists():
                state_path.unlink()
                print(f"Reset: removed {state_path}")
            else:
                print("No state file to reset.")
    except KeyboardInterrupt:
        print("\n\n  Interrupted by user (Ctrl+C).")
        print("  State saved. Run again to continue.")
        sys.exit(130)


if __name__ == '__main__':
    main()
