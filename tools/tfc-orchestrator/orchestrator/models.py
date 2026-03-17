"""Plan, Phase, Story models — parsed from YAML config."""
from dataclasses import dataclass, field
from pathlib import Path

import yaml


@dataclass
class RetryConfig:
    max_attempts: int = 3
    circuit_breaker: bool = True


@dataclass
class ReviewerDef:
    role: str
    focus: str


@dataclass
class ReviewConfig:
    enabled: bool = False
    max_iterations: int = 3
    reviewers: list[ReviewerDef] = field(default_factory=lambda: [
        ReviewerDef(role='flutter_architect', focus='code quality, architecture, patterns, SOLID, widget composition'),
        ReviewerDef(role='test_engineer', focus='test completeness, coverage, edge cases, error handling'),
    ])


@dataclass
class GsdConfig:
    enabled: bool = False
    discuss: bool = True
    plan: bool = True
    verify: bool = True
    ui_review: list[str] = field(default_factory=list)


@dataclass
class WorkersConfig:
    max_parallel: int = 3
    worktree_isolation: bool = True


@dataclass
class VerificationConfig:
    golden_tests: bool = False
    marionette: bool = False
    ai_design_review: bool = False
    ui_stories: list[int] = field(default_factory=list)
    route_map: dict[int, list[str]] = field(default_factory=dict)


@dataclass
class Story:
    id: int
    name: str
    prompt: str
    depends_on: list[int] = field(default_factory=list)
    acceptance_checks: list[str] = field(default_factory=list)


@dataclass
class Phase:
    name: str
    stories: list[Story]
    validate: list[str] = field(default_factory=list)
    setup: list[str] = field(default_factory=list)

    def execution_waves(self) -> list[list[Story]]:
        """Group stories into waves based on intra-phase dependencies.

        Stories whose depends_on are all outside this phase (or already
        completed in an earlier wave) run together in the same wave.
        """
        remaining = list(self.stories)
        phase_ids = {s.id for s in self.stories}
        completed_ids: set[int] = set()
        waves: list[list[Story]] = []

        while remaining:
            wave = [
                s for s in remaining
                if all(
                    dep in completed_ids or dep not in phase_ids
                    for dep in s.depends_on
                )
            ]
            if not wave:
                raise ValueError(
                    f"Circular dependency in phase '{self.name}': "
                    f"remaining story IDs {[s.id for s in remaining]}"
                )
            waves.append(wave)
            completed_ids.update(s.id for s in wave)
            remaining = [s for s in remaining if s not in wave]

        return waves


@dataclass
class Plan:
    name: str
    project_dir: str
    model: str
    phases: list[Phase]
    allowed_tools: str = 'Bash,Read,Edit,Write,Glob,Grep,Agent,Skill'
    max_turns: int = 200
    retry: RetryConfig = field(default_factory=RetryConfig)
    review: ReviewConfig = field(default_factory=ReviewConfig)
    gsd: GsdConfig = field(default_factory=GsdConfig)
    execution_mode: str = 'dag'  # 'dag' or 'phase' (v2.1 fallback)
    workers: WorkersConfig = field(default_factory=WorkersConfig)
    verification: VerificationConfig = field(default_factory=VerificationConfig)

    @classmethod
    def from_yaml(cls, path: str | Path) -> 'Plan':
        path = Path(path)
        with open(path) as f:
            data = yaml.safe_load(f)

        phases = []
        for phase_data in data['phases']:
            stories = []
            for story_data in phase_data['stories']:
                prompt = story_data.get('prompt', '')
                if 'prompt_file' in story_data:
                    prompt_path = path.parent / story_data['prompt_file']
                    prompt = prompt_path.read_text()
                elif not prompt:
                    prompt = cls._default_prompt(
                        story_data,
                        data.get('project_dir', '.'),
                    )

                stories.append(Story(
                    id=story_data['id'],
                    name=story_data['name'],
                    prompt=prompt,
                    depends_on=story_data.get('depends_on', []),
                    acceptance_checks=story_data.get('acceptance_checks', []),
                ))
            phases.append(Phase(
                name=phase_data['name'],
                stories=stories,
                validate=phase_data.get('validate', []),
                setup=phase_data.get('setup', []),
            ))

        # Parse retry config
        retry_data = data.get('retry', {})
        retry = RetryConfig(
            max_attempts=retry_data.get('max_attempts', 3),
            circuit_breaker=retry_data.get('circuit_breaker', True),
        )

        # Parse review config
        review_data = data.get('review', {})
        reviewers = [
            ReviewerDef(role=r['role'], focus=r['focus'])
            for r in review_data.get('reviewers', [])
        ] if 'reviewers' in review_data else ReviewConfig().reviewers
        review = ReviewConfig(
            enabled=review_data.get('enabled', False),
            max_iterations=review_data.get('max_iterations', 3),
            reviewers=reviewers,
        )

        # Parse GSD config
        gsd_data = data.get('gsd', {})
        gsd = GsdConfig(
            enabled=gsd_data.get('enabled', False),
            discuss=gsd_data.get('discuss', True),
            plan=gsd_data.get('plan', True),
            verify=gsd_data.get('verify', True),
            ui_review=gsd_data.get('ui_review', []),
        )

        # Parse workers config
        workers_data = data.get('workers', {})
        workers = WorkersConfig(
            max_parallel=workers_data.get('max_parallel', 3),
            worktree_isolation=workers_data.get('worktree_isolation', True),
        )

        # Parse verification config
        verify_data = data.get('verification', {})
        route_map_raw = verify_data.get('route_map', {})
        route_map = {int(k): v for k, v in route_map_raw.items()}
        verification = VerificationConfig(
            golden_tests=verify_data.get('golden_tests', False),
            marionette=verify_data.get('marionette', False),
            ai_design_review=verify_data.get('ai_design_review', False),
            ui_stories=verify_data.get('ui_stories', []),
            route_map=route_map,
        )

        return cls(
            name=data['name'],
            project_dir=data.get('project_dir', '.'),
            model=data.get('model', 'opus'),
            phases=phases,
            allowed_tools=data.get('allowed_tools', cls.allowed_tools),
            max_turns=data.get('max_turns', cls.max_turns),
            retry=retry,
            review=review,
            gsd=gsd,
            execution_mode=data.get('execution_mode', 'dag'),
            workers=workers,
            verification=verification,
        )

    @staticmethod
    def _default_prompt(story_data: dict, project_dir: str) -> str:
        sid = story_data['id']
        name = story_data['name']
        return (
            f"You are implementing Story {sid} from ralph-plan.md.\n\n"
            f"Read ralph-plan.md and find Story {sid}: {name}.\n"
            f"Follow ALL acceptance criteria exactly.\n\n"
            f"Follow TDD: write tests FIRST (RED), then implement (GREEN), "
            f"then refactor.\n\n"
            f"After all work is done, run validation:\n"
            f"  cd packages/tfc_dart && "
            f"dart run build_runner build --delete-conflicting-outputs\n"
            f"  cd packages/tfc_dart && dart analyze --fatal-infos\n"
            f"  cd packages/tfc_dart && dart test --exclude-tags=integration\n\n"
            f"Report PASS or FAIL with details at the end of your response."
        )
