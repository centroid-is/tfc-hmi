"""Tests for reviewer — review system core: ledger, parsing, convergence, cycle."""
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

from orchestrator.reviewer import (
    ReviewComment,
    ReviewLedger,
    parse_reviewer_output,
    check_convergence,
    run_review_cycle,
    run_single_reviewer,
    run_fixer,
    get_git_diff,
)
from orchestrator.models import (
    Story, Plan, Phase, ReviewConfig, ReviewerDef,
)
from orchestrator.executor import ExecutionResult


def _make_plan(**overrides) -> Plan:
    defaults = dict(
        name='test',
        project_dir='/tmp/test',
        model='sonnet',
        phases=[],
        allowed_tools='Bash,Read,Edit',
        max_turns=50,
    )
    defaults.update(overrides)
    return Plan(**defaults)


# ---------------------------------------------------------------------------
# TestReviewComment (3 tests)
# ---------------------------------------------------------------------------
class TestReviewComment:
    def test_make_id_deterministic(self):
        """Same file+message produces the same id every time."""
        id1 = ReviewComment.make_id('src/foo.dart', 'Missing null check')
        id2 = ReviewComment.make_id('src/foo.dart', 'Missing null check')
        assert id1 == id2
        assert len(id1) == 12  # 12-char hex prefix

    def test_make_id_different_for_different_input(self):
        """Different file or message produces a different id."""
        id1 = ReviewComment.make_id('src/foo.dart', 'Missing null check')
        id2 = ReviewComment.make_id('src/bar.dart', 'Missing null check')
        id3 = ReviewComment.make_id('src/foo.dart', 'Unused import')
        assert id1 != id2
        assert id1 != id3

    def test_default_status_is_open(self):
        """A newly-created ReviewComment has status 'open'."""
        comment = ReviewComment(
            id='abc123',
            severity='blocker',
            file='foo.dart',
            line=10,
            message='Something is wrong',
        )
        assert comment.status == 'open'
        assert comment.fix_attempts == 0


# ---------------------------------------------------------------------------
# TestReviewLedger (8 tests)
# ---------------------------------------------------------------------------
class TestReviewLedger:
    def test_empty_ledger(self, tmp_path):
        """A new ledger has 0 comments and 0 open_count."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        assert len(ledger.comments) == 0
        assert ledger.open_count == 0

    def test_add_comments(self, tmp_path):
        """Adding 2 comments results in len(comments) == 2."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        c1 = ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1')
        c2 = ReviewComment(id='bbb', severity='note', file='b.dart', line=2, message='m2')
        ledger.add_comments([c1, c2])
        assert len(ledger.comments) == 2

    def test_dedup_by_id(self, tmp_path):
        """Adding the same comment twice results in only 1 entry."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        c1 = ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1')
        c2 = ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1')
        ledger.add_comments([c1])
        ledger.add_comments([c2])
        assert len(ledger.comments) == 1

    def test_save_and_load(self, tmp_path):
        """Save ledger, create a new one from same path — comments match."""
        path = tmp_path / 'review.json'
        ledger1 = ReviewLedger(path)
        c1 = ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1')
        c2 = ReviewComment(id='bbb', severity='note', file='b.dart', line=2, message='m2')
        ledger1.add_comments([c1, c2])
        ledger1.save()

        ledger2 = ReviewLedger(path)
        assert len(ledger2.comments) == 2
        assert ledger2.comments[0].id == 'aaa'
        assert ledger2.comments[1].id == 'bbb'

    def test_open_blockers(self, tmp_path):
        """open_blockers returns only blocker-severity open comments."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        blocker = ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1')
        note = ReviewComment(id='bbb', severity='note', file='b.dart', line=2, message='m2')
        ledger.add_comments([blocker, note])
        assert len(ledger.open_blockers) == 1
        assert ledger.open_blockers[0].id == 'aaa'

    def test_actionable(self, tmp_path):
        """actionable returns blockers + should_fix, not notes."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        blocker = ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1')
        should_fix = ReviewComment(id='bbb', severity='should_fix', file='b.dart', line=2, message='m2')
        note = ReviewComment(id='ccc', severity='note', file='c.dart', line=3, message='m3')
        ledger.add_comments([blocker, should_fix, note])
        actionable = ledger.actionable
        assert len(actionable) == 2
        ids = {c.id for c in actionable}
        assert ids == {'aaa', 'bbb'}

    def test_auto_downgrade(self, tmp_path):
        """should_fix with fix_attempts >= 2 and status 'open' becomes note+downgraded."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        comment = ReviewComment(
            id='aaa', severity='should_fix', file='a.dart',
            line=1, message='m1', fix_attempts=2,
        )
        ledger.add_comments([comment])
        ledger.auto_downgrade()
        assert ledger.comments[0].severity == 'note'
        assert ledger.comments[0].status == 'downgraded'

    def test_oscillation_detection(self, tmp_path):
        """Mark a comment fixed, then re-add it — has_oscillation is True."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        comment = ReviewComment(id='aaa', severity='should_fix', file='a.dart', line=1, message='m1')
        ledger.add_comments([comment])
        ledger.mark_fixed('aaa')
        assert ledger.comments[0].status == 'fixed'

        # Re-add same comment (simulating reviewer finding it again)
        same_comment = ReviewComment(id='aaa', severity='should_fix', file='a.dart', line=1, message='m1')
        ledger.add_comments([same_comment])
        assert ledger.has_oscillation is True


# ---------------------------------------------------------------------------
# TestParseReviewerOutput (3 tests)
# ---------------------------------------------------------------------------
class TestParseReviewerOutput:
    def test_valid_json_array(self):
        """Parse a valid JSON array of findings into ReviewComment list."""
        output = json.dumps([
            {'id': 'abc', 'severity': 'blocker', 'file': 'foo.dart', 'line': 10, 'message': 'Bad code'},
            {'severity': 'should_fix', 'file': 'bar.dart', 'line': 20, 'message': 'Missing test'},
        ])
        comments = parse_reviewer_output(output)
        assert len(comments) == 2
        assert comments[0].id == 'abc'
        assert comments[0].severity == 'blocker'
        assert comments[1].severity == 'should_fix'
        # Second comment should get auto-generated id since none provided
        assert len(comments[1].id) == 12

    def test_empty_array(self):
        """Parse '[]' returns empty list."""
        comments = parse_reviewer_output('[]')
        assert comments == []

    def test_invalid_json(self):
        """Parse garbage returns empty list."""
        comments = parse_reviewer_output('this is not json at all!!!')
        assert comments == []


# ---------------------------------------------------------------------------
# TestCheckConvergence (4 tests)
# ---------------------------------------------------------------------------
class TestCheckConvergence:
    def test_stop_at_max_iterations(self, tmp_path):
        """Should stop when iteration == max_iterations."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        # Add an open blocker so it wouldn't stop for "all resolved"
        ledger.add_comments([
            ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m'),
        ])
        should_stop, reason = check_convergence(ledger, iteration=3, max_iterations=3, prev_open_count=1)
        assert should_stop is True
        assert 'Max iterations' in reason

    def test_stop_all_resolved(self, tmp_path):
        """Should stop when open_count == 0."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        # Empty ledger — nothing actionable
        should_stop, reason = check_convergence(ledger, iteration=1, max_iterations=3, prev_open_count=0)
        assert should_stop is True
        assert 'All issues resolved' in reason

    def test_stop_on_divergence(self, tmp_path):
        """Should stop when findings increased from previous iteration."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        # 5 open actionable items
        for i in range(5):
            ledger.add_comments([
                ReviewComment(id=f'c{i}', severity='blocker', file='a.dart', line=i, message=f'm{i}'),
            ])
        should_stop, reason = check_convergence(ledger, iteration=2, max_iterations=5, prev_open_count=2)
        assert should_stop is True
        assert 'Divergence' in reason

    def test_continue_when_improving(self, tmp_path):
        """Should continue when iteration < max, open_count > 0, and decreasing."""
        ledger = ReviewLedger(tmp_path / 'review.json')
        # 2 open actionable items
        ledger.add_comments([
            ReviewComment(id='aaa', severity='blocker', file='a.dart', line=1, message='m1'),
            ReviewComment(id='bbb', severity='should_fix', file='b.dart', line=2, message='m2'),
        ])
        should_stop, reason = check_convergence(ledger, iteration=1, max_iterations=3, prev_open_count=3)
        assert should_stop is False
        assert reason == ''


# ---------------------------------------------------------------------------
# TestRunReviewCycle (2 tests)
# ---------------------------------------------------------------------------
class TestRunReviewCycle:
    def test_review_disabled_returns_empty(self, tmp_path):
        """When review is disabled, returns empty ledger and 0 iterations."""
        story = Story(id=1, name='test story', prompt='do stuff')
        plan = _make_plan(review=ReviewConfig(enabled=False))
        ledger, iterations = run_review_cycle(story, plan, ledger_dir=str(tmp_path))
        assert len(ledger.comments) == 0
        assert iterations == 0

    @patch('orchestrator.reviewer.run_fixer')
    @patch('orchestrator.reviewer.run_single_reviewer')
    @patch('orchestrator.reviewer.get_git_diff')
    def test_dry_run_returns_empty(self, mock_diff, mock_reviewer, mock_fixer, tmp_path):
        """dry_run=True: reviewers return empty, so cycle ends quickly."""
        mock_diff.return_value = ''
        mock_reviewer.return_value = []
        mock_fixer.return_value = ExecutionResult(
            story_id=1, exit_code=0, stdout='', stderr='', duration_seconds=0,
        )
        story = Story(id=1, name='test story', prompt='do stuff')
        plan = _make_plan(
            review=ReviewConfig(
                enabled=True,
                max_iterations=3,
                reviewers=[ReviewerDef(role='arch', focus='quality')],
            ),
        )
        ledger, iterations = run_review_cycle(story, plan, ledger_dir=str(tmp_path), dry_run=True)
        # Reviewers return [] in dry_run, so open_count=0, converges immediately
        assert ledger.open_count == 0
        assert iterations >= 1  # At least one iteration ran
