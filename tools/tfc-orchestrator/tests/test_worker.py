"""Tests for worker pool — worktree lifecycle, merge, cleanup."""
import asyncio
import io
import json
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock, AsyncMock

import pytest

from orchestrator.worker import WorkerPool, WorkerResult, _story_with_prompt, _stream_json_to_log
from orchestrator.models import Story, Plan, Phase, RetryConfig


def _simple_plan(project_dir: str) -> Plan:
    return Plan(
        name='test',
        project_dir=project_dir,
        model='sonnet',
        phases=[Phase(name='P1', stories=[
            Story(id=1, name='s1', prompt='p'),
        ])],
    )


class TestWorkerResult:
    def test_success_result(self):
        r = WorkerResult(
            story_id=1, exit_code=0, duration=120.5,
            worktree_branch='orchestrator/story-1',
        )
        assert r.success
        assert r.story_id == 1
        assert r.worktree_branch == 'orchestrator/story-1'

    def test_failure_result(self):
        r = WorkerResult(
            story_id=1, exit_code=1, duration=30.0, error='compile error',
        )
        assert not r.success
        assert r.error == 'compile error'

    def test_defaults(self):
        r = WorkerResult(story_id=5, exit_code=0, duration=0.0)
        assert r.worktree_branch == ''
        assert r.merge_commit == ''
        assert r.error == ''
        assert r.events == []


class TestWorkerPoolCreation:
    def test_pool_creation(self):
        pool = WorkerPool(
            max_workers=3,
            project_dir='/tmp/test',
        )
        assert pool.max_workers == 3
        assert pool.project_dir == '/tmp/test'


class TestWorkerPoolWorktreeLifecycle:
    @patch('orchestrator.worker.subprocess.run')
    def test_create_worktree(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout='')
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        branch, path = pool._create_worktree(1)
        assert branch == 'orchestrator/story-1'
        assert 'story-1' in path
        mock_run.assert_called()

    @patch('orchestrator.worker.subprocess.run')
    def test_cleanup_worktree(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0)
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        pool._cleanup_worktree('/tmp/test/.orchestrator/worktrees/story-1')
        mock_run.assert_called()

    @patch('orchestrator.worker.subprocess.run')
    def test_merge_worktree(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout='abc1234\n')
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        commit = pool._merge_branch('orchestrator/story-1')
        assert commit is not None

    @patch('orchestrator.worker.subprocess.run')
    def test_merge_conflict_returns_none_with_details(self, mock_run):
        mock_run.side_effect = [
            MagicMock(returncode=0),  # git add -A (pre-merge auto-commit check)
            MagicMock(returncode=0),  # git diff --cached --quiet (clean)
            MagicMock(returncode=1, stdout='CONFLICT (content)', stderr=''),  # merge fails
            MagicMock(returncode=0),  # abort succeeds
        ]
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        commit, error = pool._merge_branch('orchestrator/story-1')
        assert commit is None
        assert 'CONFLICT' in error


class TestWorkerPoolExecution:
    @patch('orchestrator.worker.subprocess.run')
    @patch('orchestrator.worker.subprocess.Popen')
    def test_run_story_dry_run(self, mock_popen, mock_run):
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        result = asyncio.run(
            pool.run_story(
                story=Story(id=1, name='s1', prompt='p'),
                plan=_simple_plan('/tmp/test'),
                validate_cmds=['dart test'],
                dry_run=True,
            )
        )
        assert result.success
        assert result.story_id == 1
        mock_popen.assert_not_called()

    @patch('orchestrator.worker.subprocess.run')
    @patch('orchestrator.worker.subprocess.Popen')
    def test_run_story_real_execution(self, mock_popen, mock_run):
        """Mock full lifecycle: create worktree, run claude, merge, cleanup."""
        mock_run.return_value = MagicMock(returncode=0, stdout='abc1234\n')

        mock_proc = MagicMock()
        mock_proc.wait.return_value = None
        mock_proc.returncode = 0
        mock_proc.pid = 12345
        mock_proc.stdout = iter([])  # Empty stream for reader thread
        mock_popen.return_value = mock_proc

        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        result = asyncio.run(
            pool.run_story(
                story=Story(id=1, name='s1', prompt='p'),
                plan=_simple_plan('/tmp/test'),
                validate_cmds=[],
                dry_run=False,
            )
        )
        assert result.success
        assert result.worktree_branch == 'orchestrator/story-1'


class TestWorkerPoolConcurrency:
    def test_semaphore_limits_concurrency(self):
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        assert pool._semaphore._value == 2

    @patch('orchestrator.worker.subprocess.run')
    @patch('orchestrator.worker.subprocess.Popen')
    def test_multiple_stories_parallel(self, mock_popen, mock_run):
        """Run multiple stories through the pool in parallel."""
        mock_run.return_value = MagicMock(returncode=0, stdout='abc\n')

        mock_proc = MagicMock()
        mock_proc.wait.return_value = None
        mock_proc.returncode = 0
        mock_proc.pid = 12345
        mock_proc.stdout = iter([])  # Empty stream for reader thread
        mock_popen.return_value = mock_proc

        pool = WorkerPool(max_workers=3, project_dir='/tmp/test')
        plan = _simple_plan('/tmp/test')

        async def run_all():
            tasks = [
                pool.run_story(
                    Story(id=i, name=f's{i}', prompt='p'),
                    plan, [], dry_run=False,
                )
                for i in [1, 2, 3]
            ]
            return await asyncio.gather(*tasks)

        results = asyncio.run(run_all())  # noqa
        assert len(results) == 3
        assert all(r.success for r in results)


class TestRetryLoop:
    """Tests for the validation-failure retry loop in _run_story_sync."""

    @patch('orchestrator.worker.subprocess.run')
    @patch('orchestrator.worker.subprocess.Popen')
    def test_retry_on_validation_failure(self, mock_popen, mock_run):
        """When validation fails, claude should be re-invoked with error context."""
        validation_fail = MagicMock(returncode=1, stdout='', stderr='analyzer: 5 issues')
        validation_pass = MagicMock(returncode=0, stdout='', stderr='')
        git_ok = MagicMock(returncode=0, stdout='abc1234\n')
        no_changes = MagicMock(returncode=0, stdout='')

        mock_run.side_effect = [
            git_ok,                  # snapshot: git add -A
            no_changes,              # snapshot: git status (clean)
            git_ok, git_ok,          # create worktree (branch + add)
            validation_fail,         # attempt 1 validation fails
            validation_pass,         # attempt 2 validation passes
            git_ok,                  # git add -A (commit_worktree)
            no_changes,              # git status --porcelain
            git_ok,                  # pre-merge: git add -A
            no_changes,              # pre-merge: git diff --cached --quiet (clean)
            git_ok,                  # merge
            git_ok,                  # rev-parse HEAD
            git_ok,                  # cleanup worktree
        ]

        mock_proc = MagicMock()
        mock_proc.wait.return_value = None
        mock_proc.returncode = 0
        mock_proc.pid = 12345
        mock_proc.stdout = iter([])  # Empty stream for reader thread
        mock_popen.return_value = mock_proc

        plan = Plan(
            name='test', project_dir='/tmp/test', model='sonnet',
            retry=RetryConfig(max_attempts=3),
            phases=[Phase(name='P1', stories=[Story(id=1, name='s1', prompt='do stuff')])],
        )
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        result = asyncio.run(
            pool.run_story(Story(id=1, name='s1', prompt='do stuff'), plan, ['analyze'], dry_run=False)
        )
        assert result.success
        assert result.retry_count == 1
        # Claude was invoked twice (initial + retry)
        assert mock_popen.call_count == 2
        assert any('validation_failed' in e for e in result.events)
        assert any('retry:' in e for e in result.events)

    @patch('orchestrator.worker.subprocess.run')
    @patch('orchestrator.worker.subprocess.Popen')
    def test_all_retries_exhausted(self, mock_popen, mock_run):
        """When all retry attempts fail, result should be failure."""
        validation_fail = MagicMock(returncode=1, stdout='', stderr='still broken')
        git_ok = MagicMock(returncode=0, stdout='abc\n')
        no_changes = MagicMock(returncode=0, stdout='')

        mock_run.side_effect = [
            git_ok,              # snapshot: git add -A
            no_changes,          # snapshot: git status (clean)
            git_ok, git_ok,      # create worktree
            validation_fail,     # attempt 1
            validation_fail,     # attempt 2
            git_ok,              # cleanup
        ]

        mock_proc = MagicMock()
        mock_proc.wait.return_value = None
        mock_proc.returncode = 0
        mock_proc.pid = 12345
        mock_proc.stdout = iter([])  # Empty stream for reader thread
        mock_popen.return_value = mock_proc

        plan = Plan(
            name='test', project_dir='/tmp/test', model='sonnet',
            retry=RetryConfig(max_attempts=2),
            phases=[Phase(name='P1', stories=[Story(id=1, name='s1', prompt='p')])],
        )
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        result = asyncio.run(
            pool.run_story(Story(id=1, name='s1', prompt='p'), plan, ['test'], dry_run=False)
        )
        assert not result.success
        assert result.retry_count == 1
        assert 'Validation failed' in result.error

    @patch('orchestrator.worker.subprocess.run')
    @patch('orchestrator.worker.subprocess.Popen')
    def test_no_retry_on_first_success(self, mock_popen, mock_run):
        """Successful first attempt should not trigger retries."""
        git_ok = MagicMock(returncode=0, stdout='abc1234\n')
        validation_ok = MagicMock(returncode=0, stdout='', stderr='')
        no_changes = MagicMock(returncode=0, stdout='')  # git status --porcelain

        mock_run.side_effect = [
            git_ok,             # snapshot: git add -A
            no_changes,         # snapshot: git status (clean)
            git_ok, git_ok,     # create worktree
            validation_ok,      # validation passes first time
            git_ok,             # git add -A (commit_worktree)
            no_changes,         # git status --porcelain (nothing to commit)
            git_ok,             # pre-merge: git add -A
            no_changes,         # pre-merge: git diff --cached --quiet (clean)
            git_ok,             # merge
            git_ok,             # rev-parse
            git_ok,             # cleanup
        ]

        mock_proc = MagicMock()
        mock_proc.wait.return_value = None
        mock_proc.returncode = 0
        mock_proc.pid = 12345
        mock_proc.stdout = iter([])  # Empty stream for reader thread
        mock_popen.return_value = mock_proc

        plan = Plan(
            name='test', project_dir='/tmp/test', model='sonnet',
            retry=RetryConfig(max_attempts=3),
            phases=[Phase(name='P1', stories=[Story(id=1, name='s1', prompt='p')])],
        )
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        result = asyncio.run(
            pool.run_story(Story(id=1, name='s1', prompt='p'), plan, ['test'], dry_run=False)
        )
        assert result.success
        assert result.retry_count == 0
        assert mock_popen.call_count == 1  # Claude called once

    def test_story_with_prompt_helper(self):
        """_story_with_prompt creates a copy with a different prompt."""
        original = Story(id=5, name='test', prompt='original', depends_on=[1, 2])
        modified = _story_with_prompt(original, 'new prompt')
        assert modified.id == 5
        assert modified.name == 'test'
        assert modified.prompt == 'new prompt'
        assert modified.depends_on == [1, 2]
        assert original.prompt == 'original'  # original unchanged


class TestWorkerPoolCleanupStale:
    @patch('orchestrator.worker.subprocess.run')
    def test_cleanup_stale_worktrees(self, mock_run):
        """cleanup_stale() should recover and remove worktrees from prior crashed runs."""
        with tempfile.TemporaryDirectory() as tmpdir:
            wt_dir = Path(tmpdir) / '.orchestrator' / 'worktrees'
            wt_dir.mkdir(parents=True)
            (wt_dir / 'story-1').mkdir()
            (wt_dir / 'story-2').mkdir()

            mock_run.return_value = MagicMock(returncode=0, stdout='0\n')
            pool = WorkerPool(max_workers=2, project_dir=tmpdir)
            pool.cleanup_stale()
            # subprocess.run called for: status check, rev-list, cleanup per worktree
            assert mock_run.call_count >= 2

    @patch('orchestrator.worker.subprocess.run')
    def test_cleanup_recovers_uncommitted_work(self, mock_run):
        """cleanup_stale() should commit+merge uncommitted work before removing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            wt_dir = Path(tmpdir) / '.orchestrator' / 'worktrees'
            wt_dir.mkdir(parents=True)
            (wt_dir / 'story-1').mkdir()

            # Sequence: status (dirty), add, commit, rev-list (1 ahead),
            # pre-merge auto-commit, merge, rev-parse, cleanup
            mock_run.side_effect = [
                MagicMock(returncode=0, stdout='M file.txt\n'),  # status: dirty
                MagicMock(returncode=0),  # git add -A
                MagicMock(returncode=0),  # git commit
                MagicMock(returncode=0, stdout='1\n'),  # rev-list: 1 commit ahead
                MagicMock(returncode=0),  # pre-merge: git add -A
                MagicMock(returncode=0),  # pre-merge: git diff --cached --quiet (clean)
                MagicMock(returncode=0, stdout='merged\n'),  # merge
                MagicMock(returncode=0, stdout='abc123\n'),  # rev-parse HEAD
                MagicMock(returncode=0),  # cleanup worktree
            ]

            pool = WorkerPool(max_workers=2, project_dir=tmpdir)
            pool.cleanup_stale()

            # Verify commit was called (3rd call)
            commit_calls = [
                c for c in mock_run.call_args_list
                if any('commit' in str(a) for a in c[0])
            ]
            assert len(commit_calls) >= 1


class TestSnapshotWorkingTree:
    @patch('orchestrator.worker.subprocess.run')
    def test_snapshot_commits_outstanding_changes(self, mock_run):
        """snapshot_working_tree should stage+commit untracked files."""
        mock_run.side_effect = [
            MagicMock(returncode=0),  # git add -A
            MagicMock(returncode=0, stdout='?? new_file.txt\nM changed.txt\n'),  # status
            MagicMock(returncode=0),  # git commit
        ]
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        pool.snapshot_working_tree()

        assert mock_run.call_count == 3
        # Verify commit message mentions snapshot
        commit_call = mock_run.call_args_list[2]
        assert 'snapshot' in str(commit_call).lower()

    @patch('orchestrator.worker.subprocess.run')
    def test_snapshot_noops_when_clean(self, mock_run):
        """snapshot_working_tree should not commit when tree is clean."""
        mock_run.side_effect = [
            MagicMock(returncode=0),  # git add -A
            MagicMock(returncode=0, stdout=''),  # status: clean
        ]
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        pool.snapshot_working_tree()

        assert mock_run.call_count == 2  # add + status only, no commit

    @patch('orchestrator.worker.subprocess.run')
    def test_snapshot_only_runs_once(self, mock_run):
        """snapshot_working_tree should no-op on second call."""
        mock_run.return_value = MagicMock(returncode=0, stdout='')
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        pool.snapshot_working_tree()
        call_count_after_first = mock_run.call_count

        pool.snapshot_working_tree()
        assert mock_run.call_count == call_count_after_first  # No new calls


class TestMergeLock:
    @patch('orchestrator.worker.subprocess.run')
    def test_merge_sync_acquires_lock(self, mock_run):
        """_merge_sync should serialize concurrent merges via threading lock."""
        import threading

        mock_run.return_value = MagicMock(returncode=0, stdout='abc123\n')
        pool = WorkerPool(max_workers=4, project_dir='/tmp/test')

        assert isinstance(pool._merge_lock, threading.Lock)

        # Verify merge works through the lock
        commit, error = pool._merge_sync('test-branch')
        assert commit is not None

    @patch('orchestrator.worker.subprocess.run')
    def test_concurrent_merges_serialized(self, mock_run):
        """Multiple merges from threads should be serialized."""
        import threading

        merge_order = []
        original_merge = WorkerPool._merge_branch

        def tracking_merge(self, branch, plan=None):
            merge_order.append(f'start:{branch}')
            result = (f'commit-{branch}', '')
            merge_order.append(f'end:{branch}')
            return result

        mock_run.return_value = MagicMock(returncode=0, stdout='abc\n')
        pool = WorkerPool(max_workers=4, project_dir='/tmp/test')

        with patch.object(WorkerPool, '_merge_branch', tracking_merge):
            threads = []
            for i in range(3):
                t = threading.Thread(
                    target=pool._merge_sync,
                    args=(f'branch-{i}',),
                )
                threads.append(t)

            for t in threads:
                t.start()
            for t in threads:
                t.join()

        # With proper locking, merges should not interleave
        # Each start should be immediately followed by its end
        for i in range(0, len(merge_order), 2):
            branch = merge_order[i].split(':')[1]
            assert merge_order[i + 1] == f'end:{branch}'


class TestCreateWorktreeVerification:
    @patch('orchestrator.worker.subprocess.run')
    def test_create_worktree_raises_on_branch_failure(self, mock_run):
        """_create_worktree should raise if git branch fails."""
        mock_run.side_effect = [
            MagicMock(returncode=0),  # git add -A (snapshot)
            MagicMock(returncode=0, stdout=''),  # git status (snapshot, clean)
            MagicMock(returncode=1, stderr='fatal: bad ref'),  # git branch fails
        ]
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')

        with pytest.raises(RuntimeError, match='Failed to create branch'):
            pool._create_worktree(99)

    @patch('orchestrator.worker.subprocess.run')
    def test_create_worktree_raises_on_worktree_failure(self, mock_run):
        """_create_worktree should raise if git worktree add fails."""
        mock_run.side_effect = [
            MagicMock(returncode=0),  # git add -A (snapshot)
            MagicMock(returncode=0, stdout=''),  # git status (snapshot, clean)
            MagicMock(returncode=0, stdout=''),  # git branch succeeds
            MagicMock(returncode=1, stderr='fatal: already exists'),  # worktree fails
        ]
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')

        with pytest.raises(RuntimeError, match='Failed to create worktree'):
            pool._create_worktree(99)

    @patch('orchestrator.worker.subprocess.run')
    def test_create_worktree_calls_snapshot(self, mock_run):
        """_create_worktree should call snapshot_working_tree before branching."""
        mock_run.side_effect = [
            MagicMock(returncode=0),  # git add -A (snapshot)
            MagicMock(returncode=0, stdout='?? file\n'),  # git status (dirty)
            MagicMock(returncode=0),  # git commit (snapshot)
            MagicMock(returncode=0, stdout=''),  # git branch
            MagicMock(returncode=0, stdout=''),  # git worktree add
        ]
        pool = WorkerPool(max_workers=2, project_dir='/tmp/test')
        branch, wt_path = pool._create_worktree(1)

        assert branch == 'orchestrator/story-1'
        # Snapshot should have committed (3 calls) before branch (call 4)
        assert mock_run.call_count == 5


class TestStreamJsonToLog:
    """Tests for _stream_json_to_log — stream-json parser for live progress."""

    def test_text_output(self):
        """Text blocks from assistant messages should be written as-is."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{"type": "text", "text": "Hello world"}]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert 'Hello world\n' == log.getvalue()

    def test_tool_calls(self):
        """Tool use blocks should be formatted as [ToolName] description."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Read",
                    "input": {"file_path": "/src/main.dart"},
                }]},
            }),
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Bash",
                    "input": {"command": "dart analyze lib/"},
                }]},
            }),
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Grep",
                    "input": {"pattern": "TODO"},
                }]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        output = log.getvalue()
        assert '[Read] /src/main.dart\n' in output
        assert '[Bash] dart analyze lib/\n' in output
        assert '[Grep] TODO\n' in output

    def test_result_event(self):
        """Result events should show subtype, turns, cost, and duration."""
        events = [
            json.dumps({
                "type": "result",
                "subtype": "success",
                "cost_usd": 0.42,
                "duration_ms": 65000,
                "num_turns": 12,
                "result": "All done.",
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        output = log.getvalue()
        assert 'success' in output
        assert '12 turns' in output
        assert '$0.42' in output
        assert '65s' in output
        assert 'All done.' in output

    def test_malformed_line(self):
        """Non-JSON lines should be written to log as-is."""
        pipe = io.StringIO('not json at all\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert 'not json at all\n' == log.getvalue()

    def test_empty_lines_skipped(self):
        """Empty lines should be silently skipped."""
        pipe = io.StringIO('\n\n\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert '' == log.getvalue()

    def test_edit_and_write_tool_calls(self):
        """Edit and Write tool calls show file_path."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Edit",
                    "input": {"file_path": "/src/widget.dart", "old_string": "a", "new_string": "b"},
                }]},
            }),
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Write",
                    "input": {"file_path": "/src/new.dart", "content": "code"},
                }]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        output = log.getvalue()
        assert '[Edit] /src/widget.dart\n' in output
        assert '[Write] /src/new.dart\n' in output

    def test_glob_tool_call(self):
        """Glob tool calls show the pattern."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "Glob",
                    "input": {"pattern": "**/*.dart"},
                }]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert '[Glob] **/*.dart\n' in log.getvalue()

    def test_unknown_tool_shows_truncated_input(self):
        """Unknown tool names should show truncated input dict."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{
                    "type": "tool_use", "name": "CustomTool",
                    "input": {"key": "value"},
                }]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert '[CustomTool]' in log.getvalue()

    def test_unknown_event_type_logged(self):
        """Unrecognized event types should be logged as [unknown: type]."""
        events = [
            json.dumps({"type": "system", "subtype": "init", "session_id": "abc"}),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert '[system]' in log.getvalue()

    def test_multiple_content_blocks(self):
        """Assistant message with multiple content blocks should handle all."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [
                    {"type": "text", "text": "Reading file..."},
                    {"type": "tool_use", "name": "Read", "input": {"file_path": "/a.txt"}},
                ]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        output = log.getvalue()
        assert 'Reading file...\n' in output
        assert '[Read] /a.txt\n' in output

    def test_text_with_trailing_newline_not_doubled(self):
        """Text that already ends with newline shouldn't get double newline."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{"type": "text", "text": "line\n"}]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert log.getvalue() == 'line\n'

    def test_empty_text_skipped(self):
        """Empty/whitespace-only text blocks should be skipped."""
        events = [
            json.dumps({
                "type": "assistant",
                "message": {"content": [{"type": "text", "text": "   "}]},
            }),
        ]
        pipe = io.StringIO('\n'.join(events) + '\n')
        log = io.StringIO()
        _stream_json_to_log(pipe, log)
        assert log.getvalue() == ''
