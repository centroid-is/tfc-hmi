"""GSD integration — discuss, plan, verify, UI review with fix loops."""
import json
import subprocess
from dataclasses import dataclass, field, asdict
from pathlib import Path

from .models import Story, Plan, Phase
from .prompts import (
    build_gsd_discuss_prompt, build_gsd_plan_prompt,
    build_gsd_verify_prompt, build_gsd_ui_review_prompt,
)
from .executor import execute_story, ExecutionResult


@dataclass
class GapReport:
    """Tracks unresolved gaps per phase."""
    phase_name: str
    phase_index: int
    verify_gaps: list[str] = field(default_factory=list)
    ui_review_gaps: list[str] = field(default_factory=list)
    iterations_used: int = 0

    def save(self, path: str | Path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(asdict(self), indent=2))

    @property
    def has_gaps(self) -> bool:
        return bool(self.verify_gaps or self.ui_review_gaps)


def _run_gsd_command(
    prompt: str,
    plan: Plan,
    dry_run: bool = False,
) -> ExecutionResult:
    """Run a GSD command via claude -p."""
    gsd_story = Story(id=0, name='gsd-command', prompt=prompt)
    return execute_story(gsd_story, plan, dry_run)


def _parse_verify_output(stdout: str) -> tuple[bool, list[str]]:
    """Parse verify-work output. Returns (passed, gaps)."""
    text = stdout.strip()
    if text.startswith('PASS'):
        return True, []

    # Extract gaps from GAPS_FOUND output
    gaps = []
    in_gaps = False
    for line in text.split('\n'):
        stripped = line.strip()
        if 'GAPS_FOUND' in stripped:
            in_gaps = True
            continue
        if in_gaps and stripped and stripped.startswith('-'):
            gaps.append(stripped.lstrip('- '))
        elif in_gaps and stripped:
            gaps.append(stripped)

    if not gaps and 'GAPS_FOUND' in text:
        gaps.append('Unspecified gaps found')

    return False, gaps


def _parse_ui_review_output(stdout: str) -> tuple[bool, list[str]]:
    """Parse UI review output. Returns (passed, findings)."""
    text = stdout.strip()
    if text.startswith('PASS'):
        return True, []

    findings = []
    in_findings = False
    for line in text.split('\n'):
        stripped = line.strip()
        if 'FINDINGS' in stripped:
            in_findings = True
            continue
        if in_findings and stripped and stripped.startswith('-'):
            findings.append(stripped.lstrip('- '))
        elif in_findings and stripped:
            findings.append(stripped)

    if not findings and 'FINDINGS' in text:
        findings.append('Unspecified UI findings')

    return False, findings


def run_gsd_pre_phase(
    phase: Phase,
    plan: Plan,
    dry_run: bool = False,
) -> bool:
    """Run discuss + plan before stories. Returns True if successful.

    Failures are warnings only -- stories still run.
    """
    if not plan.gsd.enabled:
        return True

    success = True

    if plan.gsd.discuss:
        print(f"  │   ├── GSD discuss: {phase.name}", flush=True)
        prompt = build_gsd_discuss_prompt(phase.name, plan.name)
        result = _run_gsd_command(prompt, plan, dry_run)
        if not result.success:
            print(f"  │   │   Warning: discuss failed (non-blocking)", flush=True)
            success = False
        else:
            print(f"  │   │   └── done", flush=True)

    if plan.gsd.plan:
        print(f"  │   ├── GSD plan: {phase.name}", flush=True)
        prompt = build_gsd_plan_prompt(phase.name, plan.name)
        result = _run_gsd_command(prompt, plan, dry_run)
        if not result.success:
            print(f"  │   │   Warning: plan failed (non-blocking)", flush=True)
            success = False
        else:
            print(f"  │   │   └── done", flush=True)

    return success


def run_gsd_post_phase(
    phase: Phase,
    phase_index: int,
    plan: Plan,
    state_dir: str | Path,
    dry_run: bool = False,
    max_fix_iterations: int = 3,
) -> GapReport:
    """Run verify + ui-review after stories, with fix loops.

    Returns GapReport with any unresolved gaps.
    """
    gap_report = GapReport(phase_name=phase.name, phase_index=phase_index)

    if not plan.gsd.enabled:
        return gap_report

    # Verify-work with fix loop
    if plan.gsd.verify:
        for iteration in range(1, max_fix_iterations + 1):
            gap_report.iterations_used = iteration
            prompt = build_gsd_verify_prompt(phase.name, plan.name)
            result = _run_gsd_command(prompt, plan, dry_run)

            if dry_run:
                break

            passed, gaps = _parse_verify_output(result.stdout)
            if passed:
                gap_report.verify_gaps = []
                break

            gap_report.verify_gaps = gaps

            if iteration < max_fix_iterations:
                # Attempt fix
                fix_prompt = (
                    f"Fix the following gaps found by verification in phase: {phase.name}\n\n"
                    f"Gaps:\n" + '\n'.join(f"- {g}" for g in gaps) + '\n\n'
                    f"Fix these issues and run tests to confirm."
                )
                _run_gsd_command(fix_prompt, plan, dry_run)

    # UI review (only for matching phases)
    if phase.name in plan.gsd.ui_review:
        for iteration in range(1, max_fix_iterations + 1):
            prompt = build_gsd_ui_review_prompt(phase.name, plan.name)
            result = _run_gsd_command(prompt, plan, dry_run)

            if dry_run:
                break

            passed, findings = _parse_ui_review_output(result.stdout)
            if passed:
                gap_report.ui_review_gaps = []
                break

            gap_report.ui_review_gaps = findings

            if iteration < max_fix_iterations:
                fix_prompt = (
                    f"Fix the following UI review findings in phase: {phase.name}\n\n"
                    f"Findings:\n" + '\n'.join(f"- {f}" for f in findings) + '\n\n'
                    f"Fix these issues."
                )
                _run_gsd_command(fix_prompt, plan, dry_run)

    # Save gap report if there are gaps
    if gap_report.has_gaps:
        report_path = Path(state_dir) / f"phase_{phase_index}_gaps.json"
        gap_report.save(report_path)

    return gap_report
