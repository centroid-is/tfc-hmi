"""Prompt templates for all claude -p invocations."""


def build_reviewer_prompt(
    role: str,
    focus: str,
    git_diff: str,
    story_name: str,
    story_prompt: str,
    ledger_json: str = '[]',
) -> str:
    """Build prompt for a read-only code reviewer.

    The reviewer must output JSON array of findings with this schema:
    [{"id": "<content_hash>", "severity": "blocker|should_fix|note", "file": "...", "line": N, "message": "..."}]
    """
    return (
        f"You are a senior code reviewer with role: {role}.\n"
        f"Focus areas: {focus}\n\n"
        f"## Story Being Reviewed\n"
        f"**{story_name}**: {story_prompt}\n\n"
        f"## Git Diff to Review\n"
        f"```diff\n{git_diff}\n```\n\n"
        f"## Existing Review Comments (avoid duplicates)\n"
        f"```json\n{ledger_json}\n```\n\n"
        f"## Output Format\n"
        f"You MUST output ONLY a JSON array of findings. Each finding:\n"
        f'{{"id": "<short_hash_of_content>", "severity": "blocker|should_fix|note", '
        f'"file": "path/to/file", "line": 0, "message": "description"}}\n\n'
        f"If no issues found, output: []\n"
        f"Do NOT output anything other than the JSON array."
    )


def build_fixer_prompt(
    actionable_comments: str,
    story_name: str,
    story_prompt: str,
) -> str:
    """Build prompt for a fixer agent that addresses review comments.

    Only receives blocker and should_fix comments (not notes).
    """
    return (
        f"You are fixing code review findings for story: {story_name}\n"
        f"Original story intent: {story_prompt}\n\n"
        f"## Review Comments to Address\n"
        f"```json\n{actionable_comments}\n```\n\n"
        f"Fix ONLY the listed issues. Do NOT:\n"
        f"- Refactor unrelated code\n"
        f"- Add features not in the original story\n"
        f"- Change code style unless specifically flagged\n\n"
        f"After fixing, run relevant tests to confirm nothing is broken.\n"
        f"Report which comments you addressed and the result."
    )


def build_retry_prompt(
    original_prompt: str,
    error_output: str,
    attempt: int,
) -> str:
    """Build prompt for retrying a failed story execution."""
    return (
        f"You are retrying a failed story execution (attempt {attempt}).\n\n"
        f"## Original Task\n{original_prompt}\n\n"
        f"## Previous Attempt Failed With\n"
        f"```\n{error_output}\n```\n\n"
        f"Analyze the error, fix the issue, and complete the original task.\n"
        f"Do NOT start from scratch — the previous attempt may have made partial progress.\n"
        f"Check the current state of the code first, then fix what's broken."
    )


def build_gsd_discuss_prompt(phase_name: str, plan_name: str) -> str:
    """Build prompt for GSD discuss-phase (pre-phase context gathering)."""
    return (
        f"You are preparing context for phase: {phase_name}\n"
        f"Plan: {plan_name}\n\n"
        f"Analyze the codebase and create a CONTEXT.md document that captures:\n"
        f"- Current state of relevant code\n"
        f"- Key patterns and conventions in use\n"
        f"- Dependencies and integration points\n"
        f"- Potential risks or concerns for this phase\n\n"
        f"Save the output to .orchestrator/CONTEXT.md"
    )


def build_gsd_plan_prompt(phase_name: str, plan_name: str) -> str:
    """Build prompt for GSD plan-phase (pre-phase planning)."""
    return (
        f"You are planning the implementation for phase: {phase_name}\n"
        f"Plan: {plan_name}\n\n"
        f"Read .orchestrator/CONTEXT.md if it exists for context.\n"
        f"Create a detailed PLAN.md that includes:\n"
        f"- Implementation order and approach\n"
        f"- Key files to modify\n"
        f"- Testing strategy\n"
        f"- Risk mitigation steps\n\n"
        f"Save the output to .orchestrator/PLAN.md"
    )


def build_gsd_verify_prompt(phase_name: str, plan_name: str) -> str:
    """Build prompt for GSD verify-work (post-phase verification)."""
    return (
        f"You are verifying the work completed in phase: {phase_name}\n"
        f"Plan: {plan_name}\n\n"
        f"Perform goal-backward verification:\n"
        f"1. Review what the phase was supposed to deliver\n"
        f"2. Check if all acceptance criteria are met\n"
        f"3. Run tests and validation commands\n"
        f"4. Identify any gaps\n\n"
        f"Output format:\n"
        f"- Start with PASS or GAPS_FOUND\n"
        f"- List each gap with details if any found\n\n"
        f"Save the output to .orchestrator/UAT.md"
    )


def build_gsd_ui_review_prompt(phase_name: str, plan_name: str) -> str:
    """Build prompt for GSD UI review (frontend phases)."""
    return (
        f"You are reviewing the UI implementation for phase: {phase_name}\n"
        f"Plan: {plan_name}\n\n"
        f"Review the UI changes for:\n"
        f"- Visual consistency and design patterns\n"
        f"- Responsive layout behavior\n"
        f"- Accessibility concerns\n"
        f"- Widget composition and reuse\n\n"
        f"Output format:\n"
        f"- Start with PASS or FINDINGS\n"
        f"- List each finding with severity and details\n\n"
        f"Save the output to .orchestrator/UI-REVIEW.md"
    )


def build_worktree_story_prompt(
    story_id: int,
    story_name: str,
    story_prompt: str,
    worktree_branch: str,
) -> str:
    """Build prompt for worktree-isolated story execution.

    Adds context about the worktree environment and TDD instructions.
    The prompt is designed for a fresh claude -p session in the worktree directory.
    """
    return (
        f"You are implementing Story {story_id}: {story_name}\n"
        f"Working in an isolated git worktree on branch: {worktree_branch}\n\n"
        f"## Task\n{story_prompt}\n\n"
        f"## Instructions\n"
        f"1. Follow TDD: write tests FIRST (RED), then implement (GREEN), then refactor.\n"
        f"2. All work happens in this worktree — your changes will be merged back automatically.\n"
        f"3. Do NOT switch branches or modify git state.\n"
        f"4. Commit your changes when done: `git add -A && git commit -m 'feat(mqtt): Story {story_id} — {story_name}'`\n\n"
        f"## Output Format\n"
        f"At the end of your response, output exactly one of:\n"
        f"- RESULT: PASS — if all acceptance criteria are met and tests pass\n"
        f"- RESULT: FAIL — followed by the reason for failure\n"
    )
