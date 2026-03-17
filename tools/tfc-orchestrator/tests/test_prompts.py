"""Tests for prompt template builders."""

from orchestrator.prompts import (
    build_reviewer_prompt,
    build_fixer_prompt,
    build_retry_prompt,
    build_gsd_discuss_prompt,
    build_gsd_plan_prompt,
    build_gsd_verify_prompt,
    build_gsd_ui_review_prompt,
    build_worktree_story_prompt,
)


class TestPromptBuilders:
    def test_reviewer_prompt_includes_role_and_focus(self):
        result = build_reviewer_prompt(
            role="flutter_architect",
            focus="code quality",
            git_diff="--- a/foo.dart\n+++ b/foo.dart\n+print('hi');",
            story_name="Add MQTT adapter",
            story_prompt="Implement MQTT adapter with TDD",
        )
        assert "flutter_architect" in result
        assert "code quality" in result
        assert "JSON" in result
        assert "print('hi')" in result
        assert "Add MQTT adapter" in result

    def test_reviewer_prompt_includes_output_schema(self):
        result = build_reviewer_prompt(
            role="test_engineer",
            focus="test coverage",
            git_diff="diff content",
            story_name="story1",
            story_prompt="do stuff",
        )
        assert "severity" in result
        assert "blocker|should_fix|note" in result
        assert "file" in result
        assert "message" in result

    def test_fixer_prompt_includes_actionable_comments(self):
        comments = '[{"id": "abc", "severity": "blocker", "message": "missing null check"}]'
        result = build_fixer_prompt(
            actionable_comments=comments,
            story_name="Add MQTT adapter",
            story_prompt="Implement MQTT adapter with TDD",
        )
        assert comments in result
        assert "Add MQTT adapter" in result
        assert "Do NOT" in result

    def test_retry_prompt_includes_error_and_attempt(self):
        result = build_retry_prompt(
            original_prompt="Implement the widget",
            error_output="CompileError: undefined variable 'foo'",
            attempt=2,
        )
        assert "CompileError: undefined variable 'foo'" in result
        assert "2" in result

    def test_gsd_discuss_prompt_includes_phase_name(self):
        result = build_gsd_discuss_prompt(
            phase_name="Phase 1: MQTT Core",
            plan_name="mqtt_web",
        )
        assert "Phase 1: MQTT Core" in result
        assert "CONTEXT.md" in result

    def test_gsd_verify_prompt_includes_pass_gaps_format(self):
        result = build_gsd_verify_prompt(
            phase_name="Phase 2: Web Dashboard",
            plan_name="mqtt_web",
        )
        assert "PASS" in result
        assert "GAPS_FOUND" in result
        assert "UAT.md" in result

    def test_worktree_story_prompt_includes_tdd(self):
        result = build_worktree_story_prompt(
            story_id=3,
            story_name="StateMan MQTT integration",
            story_prompt="Implement the adapter",
            worktree_branch="orchestrator/story-3",
        )
        assert "Story 3" in result
        assert "StateMan MQTT integration" in result
        assert "TDD" in result
        assert "orchestrator/story-3" in result
        assert "RESULT: PASS" in result
        assert "RESULT: FAIL" in result

    def test_worktree_story_prompt_isolation_warning(self):
        result = build_worktree_story_prompt(
            story_id=1,
            story_name="Test",
            story_prompt="Do stuff",
            worktree_branch="orchestrator/story-1",
        )
        assert "Do NOT switch branches" in result
        assert "worktree" in result.lower()
