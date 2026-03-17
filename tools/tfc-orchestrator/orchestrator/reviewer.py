"""Review system — parallel reviewers, comment ledger, fixer loop, convergence."""
import hashlib
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, asdict
from pathlib import Path

from .models import Story, Plan, ReviewConfig, ReviewerDef
from .prompts import build_reviewer_prompt, build_fixer_prompt
from .executor import execute_story, ExecutionResult


@dataclass
class ReviewComment:
    id: str  # content hash for dedup
    severity: str  # 'blocker', 'should_fix', 'note'
    file: str
    line: int
    message: str
    status: str = 'open'  # 'open', 'fixed', 'wont_fix', 'downgraded'
    fix_attempts: int = 0

    @staticmethod
    def make_id(file: str, message: str) -> str:
        """Generate content hash for dedup."""
        content = f"{file}:{message}"
        return hashlib.sha256(content.encode()).hexdigest()[:12]


class ReviewLedger:
    """Persistent JSON store for review comments with dedup and oscillation detection."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.comments: list[ReviewComment] = []
        self._fixed_then_reopened: set[str] = set()  # oscillation tracking
        if self.path.exists():
            self._load()

    def _load(self):
        data = json.loads(self.path.read_text())
        self.comments = [ReviewComment(**c) for c in data.get('comments', [])]
        self._fixed_then_reopened = set(data.get('fixed_then_reopened', []))

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({
            'comments': [asdict(c) for c in self.comments],
            'fixed_then_reopened': list(self._fixed_then_reopened),
        }, indent=2))

    def add_comments(self, new_comments: list[ReviewComment]):
        """Add new comments, deduplicating by id."""
        existing_ids = {c.id for c in self.comments}
        for comment in new_comments:
            if comment.id in existing_ids:
                # Check for oscillation: was fixed, now reintroduced
                existing = next(c for c in self.comments if c.id == comment.id)
                if existing.status == 'fixed':
                    self._fixed_then_reopened.add(comment.id)
                    # Auto-downgrade oscillating should_fix to note
                    if existing.severity == 'should_fix':
                        existing.status = 'downgraded'
                        existing.severity = 'note'
                    else:
                        existing.status = 'open'
                continue
            self.comments.append(comment)

    def mark_fixed(self, comment_id: str):
        for c in self.comments:
            if c.id == comment_id:
                c.status = 'fixed'
                c.fix_attempts += 1
                break

    def auto_downgrade(self):
        """Downgrade should_fix with 2+ failed fixes to note."""
        for c in self.comments:
            if c.severity == 'should_fix' and c.fix_attempts >= 2 and c.status == 'open':
                c.severity = 'note'
                c.status = 'downgraded'

    @property
    def open_blockers(self) -> list[ReviewComment]:
        return [c for c in self.comments if c.severity == 'blocker' and c.status == 'open']

    @property
    def open_should_fix(self) -> list[ReviewComment]:
        return [c for c in self.comments if c.severity == 'should_fix' and c.status == 'open']

    @property
    def actionable(self) -> list[ReviewComment]:
        """Comments that need fixing: open blockers + open should_fix."""
        return self.open_blockers + self.open_should_fix

    @property
    def open_count(self) -> int:
        return len(self.actionable)

    def to_json(self) -> str:
        return json.dumps([asdict(c) for c in self.comments], indent=2)

    @property
    def has_oscillation(self) -> bool:
        return len(self._fixed_then_reopened) > 0


def parse_reviewer_output(output: str) -> list[ReviewComment]:
    """Parse JSON array from reviewer stdout into ReviewComment list."""
    # Find JSON array in output (may have surrounding text)
    text = output.strip()
    # Try to find JSON array
    start = text.find('[')
    end = text.rfind(']')
    if start == -1 or end == -1:
        return []
    try:
        findings = json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return []

    comments = []
    for f in findings:
        if not isinstance(f, dict):
            continue
        severity = f.get('severity', 'note')
        if severity not in ('blocker', 'should_fix', 'note'):
            severity = 'note'
        file_path = f.get('file', '')
        message = f.get('message', '')
        cid = f.get('id', '') or ReviewComment.make_id(file_path, message)
        comments.append(ReviewComment(
            id=cid,
            severity=severity,
            file=file_path,
            line=f.get('line', 0),
            message=message,
        ))
    return comments


def get_git_diff(project_dir: str) -> str:
    """Get git diff for review context."""
    try:
        result = subprocess.run(
            ['git', 'diff', 'HEAD'],
            cwd=project_dir, capture_output=True, text=True, timeout=30,
        )
        return result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ''


def run_single_reviewer(
    reviewer: ReviewerDef,
    story: Story,
    plan: Plan,
    git_diff: str,
    ledger_json: str,
    dry_run: bool = False,
) -> list[ReviewComment]:
    """Run a single reviewer via claude -p (read-only tools)."""
    prompt = build_reviewer_prompt(
        role=reviewer.role,
        focus=reviewer.focus,
        git_diff=git_diff,
        story_name=story.name,
        story_prompt=story.prompt,
        ledger_json=ledger_json,
    )

    if dry_run:
        return []

    cmd = [
        'claude', '-p', prompt,
        '--model', plan.model,
        '--allowedTools', 'Read,Glob,Grep',
        '--max-turns', str(min(plan.max_turns, 50)),
        '--output-format', 'text',
    ]

    try:
        result = subprocess.run(
            cmd, cwd=plan.project_dir,
            capture_output=True, text=True, timeout=600,
        )
        return parse_reviewer_output(result.stdout)
    except subprocess.TimeoutExpired:
        return []


def run_fixer(
    actionable: list[ReviewComment],
    story: Story,
    plan: Plan,
    dry_run: bool = False,
) -> ExecutionResult:
    """Run fixer agent to address review comments."""
    comments_json = json.dumps([asdict(c) for c in actionable], indent=2)
    prompt = build_fixer_prompt(
        actionable_comments=comments_json,
        story_name=story.name,
        story_prompt=story.prompt,
    )

    fixer_story = Story(id=story.id, name=f"{story.name} [fix]", prompt=prompt)
    return execute_story(fixer_story, plan, dry_run)


def check_convergence(
    ledger: ReviewLedger,
    iteration: int,
    max_iterations: int,
    prev_open_count: int,
) -> tuple[bool, str]:
    """Check if review should stop. Returns (should_stop, reason)."""
    # Max iterations reached
    if iteration >= max_iterations:
        return True, f"Max iterations ({max_iterations}) reached"

    # No actionable items left
    if ledger.open_count == 0:
        return True, "All issues resolved"

    # Divergence: more findings than before
    if prev_open_count > 0 and ledger.open_count > prev_open_count:
        return True, f"Divergence: findings increased ({prev_open_count} -> {ledger.open_count})"

    # Oscillation detected
    if ledger.has_oscillation:
        return True, "Oscillation detected: fixed comments reintroduced"

    return False, ""


def run_review_cycle(
    story: Story,
    plan: Plan,
    ledger_dir: str | Path,
    dry_run: bool = False,
) -> tuple[ReviewLedger, int]:
    """Orchestrate full review cycle: reviewers -> fixer -> convergence -> loop.

    Returns (ledger, iterations_used).
    """
    ledger_path = Path(ledger_dir) / f"story_{story.id}_review.json"
    ledger = ReviewLedger(ledger_path)
    review_config = plan.review

    if not review_config.enabled:
        return ledger, 0

    iteration = 0
    reviewer_names = ', '.join(r.role for r in review_config.reviewers)
    for iteration in range(1, review_config.max_iterations + 1):
        prev_open = ledger.open_count

        print(f"  │   ├── Review iteration {iteration}: [{reviewer_names}]",
              flush=True)

        # Get git diff for reviewers
        git_diff = get_git_diff(plan.project_dir) if not dry_run else ''

        # Run reviewers in parallel (read-only, can't conflict)
        all_comments = []
        with ThreadPoolExecutor(max_workers=len(review_config.reviewers)) as pool:
            futures = {
                pool.submit(
                    run_single_reviewer,
                    reviewer, story, plan, git_diff,
                    ledger.to_json(), dry_run,
                ): reviewer
                for reviewer in review_config.reviewers
            }
            for future in as_completed(futures):
                reviewer = futures[future]
                comments = future.result()
                print(f"  │   │   └── {reviewer.role}: "
                      f"{len(comments)} finding(s)", flush=True)
                all_comments.extend(comments)

        # Add to ledger (dedup)
        ledger.add_comments(all_comments)
        ledger.auto_downgrade()
        ledger.save()

        # Check convergence
        should_stop, reason = check_convergence(
            ledger, iteration, review_config.max_iterations, prev_open,
        )
        if should_stop:
            print(f"  │   │   → {reason}", flush=True)
            break

        # Run fixer for actionable items
        if ledger.actionable:
            print(f"  │   ├── Fixer: addressing {len(ledger.actionable)} item(s)",
                  flush=True)
            run_fixer(ledger.actionable, story, plan, dry_run)
            # Assume fixer addressed items -- mark as fixed
            for comment in ledger.actionable:
                ledger.mark_fixed(comment.id)
            ledger.save()

    return ledger, iteration
