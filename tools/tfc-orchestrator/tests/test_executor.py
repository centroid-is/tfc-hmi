"""Tests for executor — claude CLI invocation, dry-run, timeout handling."""
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock, call
import subprocess

from orchestrator.executor import (
    execute_story, ExecutionResult,
    run_acceptance_checks, get_git_diff_hash, execute_with_retry,
)
from orchestrator.models import Story, Plan, Phase, RetryConfig

# Shared temp dir for log files during tests
_test_tmpdir = tempfile.mkdtemp()


def _make_plan(**overrides) -> Plan:
    defaults = dict(
        name='test',
        project_dir=_test_tmpdir,
        model='sonnet',
        phases=[],
        allowed_tools='Bash,Read,Edit',
        max_turns=50,
    )
    defaults.update(overrides)
    return Plan(**defaults)


class TestExecuteStoryDryRun:
    def test_dry_run_returns_success(self):
        story = Story(id=1, name='test story', prompt='do stuff')
        plan = _make_plan()
        result = execute_story(story, plan, dry_run=True)
        assert result.success
        assert result.story_id == 1
        assert result.duration_seconds == 0.0
        assert 'DRY RUN' in result.stdout

    def test_dry_run_does_not_call_subprocess(self):
        story = Story(id=1, name='test', prompt='p')
        plan = _make_plan()
        with patch('orchestrator.executor.subprocess.run') as mock_run:
            execute_story(story, plan, dry_run=True)
            mock_run.assert_not_called()


def _mock_popen_with_output(returncode=0, stdout_text='', stderr_text=''):
    """Create a mock Popen that writes to the log files passed as stdout/stderr."""
    original_popen = subprocess.Popen.__init__

    class FakePopen:
        def __init__(self, cmd, **kwargs):
            self.pid = 12345
            self.returncode = returncode
            # Write to the file objects passed as stdout/stderr
            stdout_file = kwargs.get('stdout')
            stderr_file = kwargs.get('stderr')
            if stdout_file and hasattr(stdout_file, 'write'):
                stdout_file.write(stdout_text)
            if stderr_file and hasattr(stderr_file, 'write'):
                stderr_file.write(stderr_text)

        def wait(self, timeout=None):
            return self.returncode

        def terminate(self):
            pass

        def kill(self):
            pass

    return FakePopen


class TestExecuteStoryReal:
    def test_success_exit_code_zero(self):
        FakePopen = _mock_popen_with_output(
            returncode=0, stdout_text='All tests pass. PASS.', stderr_text='',
        )
        with patch('orchestrator.executor.subprocess.Popen', FakePopen):
            story = Story(id=1, name='test', prompt='do stuff')
            plan = _make_plan()
            result = execute_story(story, plan, dry_run=False)

        assert result.success
        assert result.exit_code == 0
        assert 'PASS' in result.stdout

    def test_failure_exit_code_nonzero(self):
        FakePopen = _mock_popen_with_output(
            returncode=1, stdout_text='', stderr_text='Error: tests failed',
        )
        with patch('orchestrator.executor.subprocess.Popen', FakePopen):
            story = Story(id=1, name='test', prompt='do stuff')
            plan = _make_plan()
            result = execute_story(story, plan, dry_run=False)

        assert not result.success
        assert result.exit_code == 1

    def test_correct_cli_args(self):
        captured_cmd = []

        class CapturePopen:
            def __init__(self, cmd, **kwargs):
                captured_cmd.extend(cmd)
                self.pid = 12345
                self.returncode = 0
                stdout_file = kwargs.get('stdout')
                stderr_file = kwargs.get('stderr')
                if stdout_file and hasattr(stdout_file, 'write'):
                    stdout_file.write('')
                if stderr_file and hasattr(stderr_file, 'write'):
                    stderr_file.write('')

            def wait(self, timeout=None):
                return self.returncode

            def terminate(self):
                pass

        with patch('orchestrator.executor.subprocess.Popen', CapturePopen):
            story = Story(id=1, name='test', prompt='execute story 1')
            plan = _make_plan(model='opus', max_turns=200, allowed_tools='Bash,Read')
            execute_story(story, plan, dry_run=False)

        assert captured_cmd[0] == 'claude'
        assert '-p' in captured_cmd
        assert '--model' in captured_cmd
        idx = captured_cmd.index('--model')
        assert captured_cmd[idx + 1] == 'opus'
        assert '--max-turns' in captured_cmd
        idx = captured_cmd.index('--max-turns')
        assert captured_cmd[idx + 1] == '200'

    def test_cwd_is_project_dir(self):
        captured_kwargs = {}

        class CapturePopen:
            def __init__(self, cmd, **kwargs):
                captured_kwargs.update(kwargs)
                self.pid = 12345
                self.returncode = 0
                stdout_file = kwargs.get('stdout')
                stderr_file = kwargs.get('stderr')
                if stdout_file and hasattr(stdout_file, 'write'):
                    stdout_file.write('')
                if stderr_file and hasattr(stderr_file, 'write'):
                    stderr_file.write('')

            def wait(self, timeout=None):
                return self.returncode

            def terminate(self):
                pass

        with patch('orchestrator.executor.subprocess.Popen', CapturePopen):
            story = Story(id=1, name='test', prompt='p')
            # Must use real tmpdir since _log_dir creates directories
            plan = _make_plan()
            execute_story(story, plan, dry_run=False)

        assert captured_kwargs['cwd'] == _test_tmpdir

    def test_timeout_raises(self):
        class TimeoutPopen:
            def __init__(self, cmd, **kwargs):
                self.pid = 12345
                self.returncode = None
                stdout_file = kwargs.get('stdout')
                stderr_file = kwargs.get('stderr')
                if stdout_file and hasattr(stdout_file, 'write'):
                    stdout_file.write('')
                if stderr_file and hasattr(stderr_file, 'write'):
                    stderr_file.write('')

            def wait(self, timeout=None):
                raise subprocess.TimeoutExpired(cmd='claude', timeout=1800)

            def terminate(self):
                pass

            def kill(self):
                pass

        with patch('orchestrator.executor.subprocess.Popen', TimeoutPopen), \
             patch('orchestrator.executor.os.killpg'):
            story = Story(id=1, name='test', prompt='p')
            plan = _make_plan()
            result = execute_story(story, plan, dry_run=False)

        assert not result.success
        assert 'timeout' in result.stderr.lower()


class TestExecutionResult:
    def test_success_when_exit_zero(self):
        r = ExecutionResult(story_id=1, exit_code=0, stdout='ok', stderr='', duration_seconds=10)
        assert r.success

    def test_failure_when_exit_nonzero(self):
        r = ExecutionResult(story_id=1, exit_code=1, stdout='', stderr='err', duration_seconds=10)
        assert not r.success


class TestAcceptanceChecks:
    @patch('orchestrator.executor.subprocess.run')
    def test_acceptance_checks_pass(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout='ok', stderr='')
        passed, error_output = run_acceptance_checks(
            ['dart test', 'dart analyze'], '/tmp/project',
        )
        assert passed is True
        assert error_output == ''
        assert mock_run.call_count == 2

    @patch('orchestrator.executor.subprocess.run')
    def test_acceptance_checks_fail(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=1, stdout='', stderr='some test failed',
        )
        passed, error_output = run_acceptance_checks(
            ['dart test'], '/tmp/project',
        )
        assert passed is False
        assert 'Check failed' in error_output
        assert 'dart test' in error_output

    def test_acceptance_checks_dry_run(self):
        with patch('orchestrator.executor.subprocess.run') as mock_run:
            passed, error_output = run_acceptance_checks(
                ['dart test'], '/tmp/project', dry_run=True,
            )
            assert passed is True
            assert error_output == ''
            mock_run.assert_not_called()


class TestGetGitDiffHash:
    @patch('orchestrator.executor.subprocess.run')
    def test_git_diff_hash_returns_hex(self, mock_run):
        mock_run.return_value = MagicMock(
            stdout='diff --git a/foo.py b/foo.py\n+hello\n',
        )
        result = get_git_diff_hash('/tmp/project')
        assert len(result) == 16
        assert all(c in '0123456789abcdef' for c in result)


class TestExecuteWithRetry:
    @patch('orchestrator.executor.run_acceptance_checks', return_value=(True, ''))
    @patch('orchestrator.executor.execute_story')
    def test_first_attempt_success(self, mock_exec, mock_checks):
        mock_exec.return_value = ExecutionResult(
            story_id=1, exit_code=0, stdout='done', stderr='',
            duration_seconds=5.0,
        )
        story = Story(id=1, name='test', prompt='do stuff')
        plan = _make_plan()
        result = execute_with_retry(story, plan, phase_validate=[])
        assert result.success
        assert mock_exec.call_count == 1

    @patch('orchestrator.executor.run_acceptance_checks', return_value=(True, ''))
    @patch('orchestrator.executor.execute_story')
    def test_retry_on_failure(self, mock_exec, mock_checks):
        fail_result = ExecutionResult(
            story_id=1, exit_code=1, stdout='', stderr='error',
            duration_seconds=5.0,
        )
        success_result = ExecutionResult(
            story_id=1, exit_code=0, stdout='done', stderr='',
            duration_seconds=5.0,
        )
        mock_exec.side_effect = [fail_result, success_result]
        story = Story(id=1, name='test', prompt='do stuff')
        plan = _make_plan()
        result = execute_with_retry(story, plan, phase_validate=[])
        assert result.success
        assert mock_exec.call_count == 2

    @patch('orchestrator.executor.execute_story')
    def test_max_retries_exhausted(self, mock_exec):
        fail_result = ExecutionResult(
            story_id=1, exit_code=1, stdout='', stderr='error',
            duration_seconds=5.0,
        )
        mock_exec.return_value = fail_result
        story = Story(id=1, name='test', prompt='do stuff')
        plan = _make_plan(retry=RetryConfig(max_attempts=3))
        result = execute_with_retry(story, plan, phase_validate=[])
        assert not result.success
        assert mock_exec.call_count == 3

    @patch('orchestrator.executor.get_git_diff_hash', return_value='abcdef1234567890')
    @patch('orchestrator.executor.run_acceptance_checks',
           return_value=(False, 'test failed'))
    @patch('orchestrator.executor.execute_story')
    def test_circuit_breaker_stops_retry(self, mock_exec, mock_checks, mock_hash):
        mock_exec.return_value = ExecutionResult(
            story_id=1, exit_code=0, stdout='done', stderr='',
            duration_seconds=5.0,
        )
        story = Story(id=1, name='test', prompt='do stuff')
        plan = _make_plan(retry=RetryConfig(max_attempts=5, circuit_breaker=True))
        result = execute_with_retry(story, plan, phase_validate=['dart test'])
        assert not result.success
        assert 'Circuit breaker' in result.stderr
        # Should stop after 2 attempts (1st sets hash, 2nd sees same hash)
        assert mock_exec.call_count == 2
