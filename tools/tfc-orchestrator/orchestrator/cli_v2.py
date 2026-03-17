"""v2.1 orchestration loop — phase-based sequential execution (backward compat).

This is preserved as a fallback when execution_mode='phase' is set in the plan YAML.
The v3 DAG-based orchestration is in cli.py.
"""
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path

from .executor import execute_with_retry, commit_story
from .models import Plan, Phase
from .reviewer import run_review_cycle
from .gsd import run_gsd_pre_phase, run_gsd_post_phase
from .state import OrchestratorState, StoryResult


def _fmt_duration(seconds: float) -> str:
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
    stories_executed: set[int] = field(default_factory=set)


def run_validation(
    commands: list[str], project_dir: str, dry_run: bool = False,
) -> bool:
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


def run_plan_v2(
    plan_path: str,
    dry_run: bool = False,
    resume: bool = False,
    state_dir: str | None = None,
    max_parallel: int = 3,
    no_review: bool = False,
    no_gsd: bool = False,
) -> RunResult:
    """Execute a plan using v2.1 phase-based sequential execution."""
    plan = Plan.from_yaml(plan_path)

    if state_dir is None:
        state_dir = str(Path(plan.project_dir) / '.orchestrator')
    state_path = Path(state_dir) / f'{plan.name}.state.json'

    if resume and state_path.exists():
        state = OrchestratorState.load(state_path)
        print(f"Resuming {plan.name} from phase {state.current_phase + 1}")
        print(f"  Completed stories: {sorted(state.completed_story_ids)}")
    else:
        state = OrchestratorState(plan_name=plan.name)

    start_phase = state.current_phase
    stories_executed: set[int] = set()
    total_start = time.time()

    print(f"\n{'=' * 55}")
    print(f"  tfc-orchestrator v2.1: {plan.name}")
    print(f"  Phases: {len(plan.phases)} | Model: {plan.model}"
          f" | {'DRY RUN' if dry_run else 'LIVE'}")
    print(f"{'=' * 55}\n")

    phase_timings: list[tuple[str, float]] = []
    clock = _ElapsedClock(interval=30)

    for phase_idx in range(start_phase, len(plan.phases)):
        phase = plan.phases[phase_idx]
        state.current_phase = phase_idx
        phase_start = time.time()

        print(f"Phase {phase_idx + 1}/{len(plan.phases)}: {phase.name}")
        clock.start(label=f"Phase {phase_idx + 1}")

        if not no_gsd and plan.gsd.enabled:
            print(f"  ├── GSD: discuss + plan")
            run_gsd_pre_phase(phase, plan, dry_run)

        waves = phase.execution_waves()
        phase_failed = False

        for wave_idx, wave in enumerate(waves):
            wave = [
                s for s in wave if s.id not in state.completed_story_ids
            ]
            if not wave:
                continue

            if len(wave) == 1:
                story = wave[0]
                print(f"  ├── Story {story.id}: {story.name}")
                clock.update_label(f"Story {story.id}: {story.name}")
                result = execute_with_retry(
                    story, plan, phase.validate, dry_run,
                )
                stories_executed.add(story.id)

                if result.success:
                    review_iters = 0
                    review_findings = 0
                    if not no_review and plan.review.enabled:
                        ledger, review_iters = run_review_cycle(
                            story, plan, state_dir, dry_run,
                        )
                        review_findings = ledger.open_count
                        if review_iters > 0:
                            print(f"  │   ├── Review: {review_iters} iterations, "
                                  f"{review_findings} open findings")

                    if commit_story(story.id, story.name, plan.project_dir, dry_run):
                        print(f"  │   ├── Committed")
                    else:
                        print(f"  │   ├── Commit skipped (no changes or error)")

                    state.results.append(StoryResult(
                        story_id=story.id,
                        story_name=story.name,
                        status='pass',
                        duration_seconds=result.duration_seconds,
                        review_iterations=review_iters,
                        review_findings=review_findings,
                    ))
                    dur = _fmt_duration(result.duration_seconds)
                    print(f"  │   └── PASS ({dur})")
                else:
                    state.mark_failed(
                        story.id, story.name,
                        result.duration_seconds, result.stderr[:500],
                    )
                    dur = _fmt_duration(result.duration_seconds)
                    print(f"  │   └── FAIL ({dur})")
                    print(f"  │       {result.stderr[:200]}")
                    phase_failed = True
                    break
            else:
                ids = ', '.join(str(s.id) for s in wave)
                print(f"  ├── Wave {wave_idx + 1}: "
                      f"Stories [{ids}] in parallel")
                clock.update_label(f"Wave: Stories [{ids}]")
                with ThreadPoolExecutor(
                    max_workers=min(len(wave), max_parallel),
                ) as pool:
                    futures = {
                        pool.submit(
                            execute_with_retry, story, plan,
                            phase.validate, dry_run,
                        ): story
                        for story in wave
                    }

                    all_passed = True
                    for future in as_completed(futures):
                        story = futures[future]
                        result = future.result()
                        stories_executed.add(story.id)

                        if result.success:
                            review_iters = 0
                            review_findings = 0
                            if not no_review and plan.review.enabled:
                                ledger, review_iters = run_review_cycle(
                                    story, plan, state_dir, dry_run,
                                )
                                review_findings = ledger.open_count

                            committed = commit_story(
                                story.id, story.name, plan.project_dir, dry_run,
                            )

                            state.results.append(StoryResult(
                                story_id=story.id,
                                story_name=story.name,
                                status='pass',
                                duration_seconds=result.duration_seconds,
                                review_iterations=review_iters,
                                review_findings=review_findings,
                            ))
                            dur = _fmt_duration(result.duration_seconds)
                            review_info = (f" [review: {review_iters}i/{review_findings}f]"
                                          if review_iters > 0 else "")
                            commit_icon = " ✓" if committed else ""
                            print(f"  │   ├── Story {story.id}: "
                                  f"{story.name} → PASS ({dur}){review_info}{commit_icon}")
                        else:
                            state.mark_failed(
                                story.id, story.name,
                                result.duration_seconds,
                                result.stderr[:500],
                            )
                            print(f"  │   ├── Story {story.id}: "
                                  f"{story.name} → FAIL")
                            all_passed = False

                    if not all_passed:
                        phase_failed = True
                        break

        state.save(state_path)

        if phase_failed:
            clock.stop()
            print(f"\n  Phase {phase_idx + 1} FAILED. "
                  f"Fix issues and run with --resume.")
            return RunResult(
                success=False,
                completed_stories=state.completed_story_ids,
                failed_stories=state.failed_story_ids,
                stories_executed=stories_executed,
            )

        if phase.validate:
            print(f"  └── Validating...")
            if not run_validation(
                phase.validate, plan.project_dir, dry_run,
            ):
                clock.stop()
                print(f"  └── Validation FAILED")
                state.save(state_path)
                return RunResult(
                    success=False,
                    completed_stories=state.completed_story_ids,
                    failed_stories=state.failed_story_ids,
                    stories_executed=stories_executed,
                )
            print(f"  └── Validation PASS")

        if not no_gsd and plan.gsd.enabled:
            print(f"  ├── GSD: verify + ui-review")
            gap_report = run_gsd_post_phase(
                phase, phase_idx, plan, state_dir, dry_run,
            )
            if gap_report.has_gaps:
                print(f"  │   └── Gaps found (saved to phase_{phase_idx}_gaps.json)")

        clock.stop()
        phase_duration = time.time() - phase_start
        phase_timings.append((phase.name, phase_duration))
        print(f"  └── Phase complete ({_fmt_duration(phase_duration)})")
        print()

    total_duration = time.time() - total_start

    print(f"{'=' * 55}")
    print(f"  ALL PHASES COMPLETE ({_fmt_duration(total_duration)})")
    print(f"{'=' * 55}")

    if phase_timings:
        print(f"\n  Phase Timings:")
        for pname, pdur in phase_timings:
            print(f"    {pname:<40} {_fmt_duration(pdur)}")

    print(f"\n  {'Story':<8}{'Name':<35}{'Status':<8}{'Time':<10}{'Retry':<7}{'Review':<8}")
    print(f"  {'-' * 76}")
    for r in state.results:
        retry_str = f"x{r.retry_count}" if r.retry_count else "-"
        review_str = f"{r.review_iterations}i/{r.review_findings}f" if r.review_iterations else "-"
        print(f"  {r.story_id:<8}{r.story_name[:33]:<35}"
              f"{r.status:<8}{_fmt_duration(r.duration_seconds):<10}"
              f"{retry_str:<7}{review_str:<8}")

    story_total = sum(r.duration_seconds for r in state.results)
    print(f"  {'-' * 76}")
    print(f"  {'Total':<8}{'':<35}{'':<8}{_fmt_duration(story_total):<10}")
    print(f"\n  Wall clock: {_fmt_duration(total_duration)}")

    return RunResult(
        success=True,
        completed_stories=state.completed_story_ids,
        failed_stories=state.failed_story_ids,
        stories_executed=stories_executed,
    )
