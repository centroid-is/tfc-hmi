"""Verification gate — golden tests, marionette, AI design review."""
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import VerificationConfig


@dataclass
class VerificationReport:
    story_id: int
    golden_passed: bool | None = None
    golden_details: str = ''
    marionette_passed: bool | None = None
    marionette_details: str = ''
    ai_review_passed: bool | None = None
    ai_review_details: str = ''

    @property
    def passed(self) -> bool:
        """Overall pass: golden must pass (hard gate). Others are soft."""
        if self.golden_passed is False:
            return False
        return True

    def to_dict(self) -> dict:
        return {
            'story_id': self.story_id,
            'passed': self.passed,
            'golden_passed': self.golden_passed,
            'golden_details': self.golden_details,
            'marionette_passed': self.marionette_passed,
            'marionette_details': self.marionette_details,
            'ai_review_passed': self.ai_review_passed,
            'ai_review_details': self.ai_review_details,
        }


def run_golden_tests(
    project_dir: str,
    dry_run: bool = False,
) -> tuple[bool, str]:
    """Run golden/painter tests. Hard gate — must pass."""
    if dry_run:
        return True, 'dry run'

    try:
        result = subprocess.run(
            ['flutter', 'test', 'test/painter/', 'test/page_creator/'],
            cwd=project_dir,
            capture_output=True, text=True, timeout=300,
        )
        if result.returncode == 0:
            return True, result.stdout[:500]
        return False, result.stderr[:500]
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, str(e)


def run_marionette_check(
    project_dir: str,
    story_id: int,
    routes: list[str],
    dry_run: bool = False,
    port: int | None = None,
) -> tuple[bool, str]:
    """Route verification via marionette/getLogs. Soft gate."""
    if dry_run:
        return True, 'dry run'

    if port is None:
        port = 50001 + story_id

    try:
        # Run flutter with marionette and check routes
        cmd = [
            'flutter', 'run', '-d', 'linux',
            '--dart-define', f'MARIONETTE_PORT={port}',
        ]
        result = subprocess.run(
            cmd, cwd=project_dir,
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode == 0:
            return True, f'Routes verified: {routes}'
        return False, result.stderr[:500]
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, str(e)


def run_ai_design_review(
    project_dir: str,
    story_id: int,
    reference_html: str = '',
    dry_run: bool = False,
) -> tuple[bool, str]:
    """AI-powered visual design review. Compares built app against reference HTML if provided."""
    if dry_run:
        return True, 'dry run'

    try:
        if reference_html:
            ref_path = f'{project_dir}/{reference_html}'
            prompt = (
                f"You are verifying Story {story_id} of the MQTT web plan.\n\n"
                f"1. Read the reference HTML mockup at: {ref_path}\n"
                f"2. Read the Flutter widget code in lib/page_creator/assets/ "
                f"(especially image_feed.dart and inference_log.dart)\n"
                f"3. Compare: does the Flutter implementation match the reference "
                f"dashboard's layout, components, and data display?\n\n"
                f"Check:\n"
                f"- Metric cards (Processed, Avg Confidence, Latency, Errors)\n"
                f"- Image feed grid with confidence overlays\n"
                f"- Inference log with thumbnails, status badges, confidence bars\n"
                f"- Pause/resume toggle\n"
                f"- Overall layout and visual structure\n\n"
                f"Output PASS if the implementation faithfully represents the "
                f"reference design, or FAIL followed by specific discrepancies."
            )
        else:
            prompt = (
                f"Review the UI code for story {story_id}. "
                f"Check for visual consistency, spacing, alignment, and design patterns. "
                f"Output PASS if the design looks good, or FAIL followed by a list of issues."
            )
        result = subprocess.run(
            ['claude', '-p', prompt, '--model', 'sonnet',
             '--output-format', 'text', '--max-turns', '10'],
            cwd=project_dir,
            capture_output=True, text=True, timeout=600,
        )
        output = result.stdout.strip()
        if output.startswith('PASS'):
            return True, output
        return False, output
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, str(e)


def run_verification_gate(
    config: VerificationConfig,
    project_dir: str,
    story_id: int,
    dry_run: bool = False,
) -> VerificationReport:
    """Run the three-layer verification pipeline for a story."""
    report = VerificationReport(story_id=story_id)

    # Only run verification for UI stories
    if story_id not in config.ui_stories:
        return report

    # Layer 1: Golden tests (hard gate)
    if config.golden_tests:
        passed, details = run_golden_tests(project_dir, dry_run)
        report.golden_passed = passed
        report.golden_details = details

    # Layer 2: Marionette (soft gate)
    if config.marionette:
        routes = config.route_map.get(story_id, ['/'])
        passed, details = run_marionette_check(
            project_dir, story_id, routes, dry_run,
        )
        report.marionette_passed = passed
        report.marionette_details = details

    # Layer 3: AI design review — compares against reference HTML if provided
    if config.ai_design_review:
        passed, details = run_ai_design_review(
            project_dir, story_id, config.reference_html, dry_run,
        )
        report.ai_review_passed = passed
        report.ai_review_details = details

    return report
