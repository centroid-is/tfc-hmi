"""Tests for dashboard — pure functions and aiohttp route handlers."""
import json
import os
import time
from pathlib import Path

import pytest
from aiohttp import web
from aiohttp.test_utils import AioHTTPTestCase, TestClient, TestServer

from orchestrator.dashboard import (
    build_dag_info,
    create_app,
    derive_node_statuses,
    discover_plans,
    read_state,
)
from orchestrator.models import Phase, Plan, Story, WorkersConfig


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _minimal_plan(**overrides) -> Plan:
    """Create a minimal Plan for testing."""
    defaults = dict(
        name='test-plan',
        project_dir='/tmp/test',
        model='sonnet',
        phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p1'),
                Story(id=2, name='Story 2', prompt='p2', depends_on=[1]),
            ]),
            Phase(name='P2', stories=[
                Story(id=3, name='Story 3', prompt='p3', depends_on=[2]),
            ]),
        ],
    )
    defaults.update(overrides)
    return Plan(**defaults)


def _write_state(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def _write_plan_yaml(path: Path, plan_name: str = 'test-plan',
                     project_dir: str | None = None) -> Path:
    """Write a minimal plan YAML and return its path."""
    if project_dir is None:
        project_dir = str(path)
    yaml_content = f"""\
name: {plan_name}
project_dir: {project_dir}
model: sonnet
workers:
  max_parallel: 2
phases:
  - name: P1
    stories:
      - id: 1
        name: Story 1
        prompt: do thing 1
      - id: 2
        name: Story 2
        prompt: do thing 2
        depends_on: [1]
  - name: P2
    stories:
      - id: 3
        name: Story 3
        prompt: do thing 3
        depends_on: [2]
"""
    plan_path = path / f'{plan_name}.yaml'
    plan_path.write_text(yaml_content)
    return plan_path


def _setup_env(tmp_path: Path) -> dict:
    """Set up a temp environment with plan YAML files, state, and logs."""
    # Write plan YAML into a plans directory
    plans_dir = tmp_path / 'plans'
    plans_dir.mkdir()
    _write_plan_yaml(plans_dir, 'test-plan', project_dir=str(tmp_path))

    state_dir = tmp_path / '.orchestrator'
    state_dir.mkdir()
    state_data = {
        'version': 3,
        'plan_name': 'test-plan',
        'current_phase': 0,
        'started_at': '2026-01-01T00:00:00',
        'results': [
            {
                'story_id': 1,
                'story_name': 'Story 1',
                'status': 'pass',
                'duration_seconds': 10.5,
                'error': '',
                'timestamp': '2026-01-01T00:01:00',
            },
        ],
    }
    _write_state(state_dir / 'test-plan.state.json', state_data)

    log_dir = state_dir / 'logs' / 'test-plan'
    log_dir.mkdir(parents=True)
    (log_dir / 'story_1.stdout.log').write_text('line1\nline2\nline3\n')
    (log_dir / 'story_1.stderr.log').write_text('warn1\n')

    return {
        'plans_dir': str(plans_dir),
        'state_dir': str(state_dir),
        'log_dir': str(log_dir),
    }


# ===========================================================================
# Pure function tests
# ===========================================================================


class TestReadState:
    def test_file_not_found_returns_empty(self, tmp_path):
        result = read_state(tmp_path / 'nonexistent.json')
        assert result == {'results': []}

    def test_valid_file(self, tmp_path):
        state_data = {
            'version': 3,
            'plan_name': 'test',
            'current_phase': 0,
            'started_at': '2026-01-01T00:00:00',
            'results': [
                {
                    'story_id': 1,
                    'story_name': 'Story 1',
                    'status': 'pass',
                    'duration_seconds': 42.5,
                    'error': '',
                    'timestamp': '2026-01-01T00:01:00',
                },
            ],
        }
        state_path = tmp_path / 'state.json'
        _write_state(state_path, state_data)

        result = read_state(state_path)
        assert result['plan_name'] == 'test'
        assert len(result['results']) == 1
        assert result['results'][0]['story_id'] == 1


class TestBuildDagInfo:
    def test_nodes_and_edges(self):
        plan = _minimal_plan()
        dag_info = build_dag_info(plan)

        # Should have 3 nodes
        assert len(dag_info['nodes']) == 3
        node_ids = {n['id'] for n in dag_info['nodes']}
        assert node_ids == {1, 2, 3}

        # Check node names
        id_to_name = {n['id']: n['name'] for n in dag_info['nodes']}
        assert id_to_name[1] == 'Story 1'
        assert id_to_name[3] == 'Story 3'

        # Should have edges: 1->2, 2->3
        edges = dag_info['edges']
        assert [1, 2] in edges
        assert [2, 3] in edges
        assert len(edges) == 2

    def test_independent_stories_no_edges(self):
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='A', prompt='p'),
                Story(id=2, name='B', prompt='p'),
            ]),
        ])
        dag_info = build_dag_info(plan)
        assert len(dag_info['nodes']) == 2
        assert dag_info['edges'] == []

    def test_nodes_include_depends_on(self):
        """Bug 1: Nodes must include depends_on for frontend DAG rendering."""
        plan = _minimal_plan()
        dag_info = build_dag_info(plan)

        node_by_id = {n['id']: n for n in dag_info['nodes']}
        # Story 1 has no deps
        assert node_by_id[1]['depends_on'] == []
        # Story 2 depends on 1
        assert node_by_id[2]['depends_on'] == [1]
        # Story 3 depends on 2
        assert node_by_id[3]['depends_on'] == [2]


class TestDeriveNodeStatuses:
    def test_all_pending(self, tmp_path):
        plan = _minimal_plan()
        state_data = {'results': []}
        statuses = derive_node_statuses(plan, state_data, tmp_path)
        assert statuses == {1: 'pending', 2: 'pending', 3: 'pending'}

    def test_with_completed(self, tmp_path):
        plan = _minimal_plan()
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'pass', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        statuses = derive_node_statuses(plan, state_data, tmp_path)
        assert statuses[1] == 'passed'
        assert statuses[2] == 'pending'

    def test_with_failed_cascade(self, tmp_path):
        plan = _minimal_plan()
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'fail', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        statuses = derive_node_statuses(plan, state_data, tmp_path)
        assert statuses[1] == 'failed'
        # Story 2 depends on 1, should be skipped
        assert statuses[2] == 'skipped'
        # Story 3 depends on 2, should also be skipped
        assert statuses[3] == 'skipped'

    def test_running_detected_by_log_mtime(self, tmp_path):
        """A story with no result but a recent log file is 'running'."""
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p'),
            ]),
        ])
        state_data = {'results': []}
        log_dir = tmp_path / 'logs'
        log_dir.mkdir()
        log_file = log_dir / 'story_1.stdout.log'
        log_file.write_text('some output')
        # mtime is now, which is < 120s ago

        statuses = derive_node_statuses(plan, state_data, log_dir)
        assert statuses[1] == 'running'

    def test_stale_log_not_running(self, tmp_path):
        """A story with a log file older than 120s is not 'running'."""
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p'),
            ]),
        ])
        state_data = {'results': []}
        log_dir = tmp_path / 'logs'
        log_dir.mkdir()
        log_file = log_dir / 'story_1.stdout.log'
        log_file.write_text('some output')
        # Set mtime to 300s ago
        old_time = time.time() - 300
        os.utime(log_file, (old_time, old_time))

        statuses = derive_node_statuses(plan, state_data, log_dir)
        assert statuses[1] == 'pending'

    def test_running_result_status(self, tmp_path):
        """A story with result status 'running' maps to DAG RUNNING, dependents stay pending."""
        plan = _minimal_plan()
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'running', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        statuses = derive_node_statuses(plan, state_data, tmp_path)
        assert statuses[1] == 'running'
        # Dependents must remain pending, not skipped
        assert statuses[2] == 'pending'
        assert statuses[3] == 'pending'

    def test_unknown_status_treated_as_failure(self, tmp_path):
        """An unknown result status string (e.g., 'timeout') is treated as failed."""
        plan = _minimal_plan()
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'timeout', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        statuses = derive_node_statuses(plan, state_data, tmp_path)
        assert statuses[1] == 'failed'
        # Dependents should cascade to skipped
        assert statuses[2] == 'skipped'
        assert statuses[3] == 'skipped'

    def test_unknown_status_logs_warning(self, tmp_path, caplog):
        """Unknown status string emits a warning log."""
        import logging
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p'),
            ]),
        ])
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'bogus', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        with caplog.at_level(logging.WARNING, logger='orchestrator.dashboard'):
            derive_node_statuses(plan, state_data, tmp_path)
        assert any('Unknown result status' in msg for msg in caplog.messages)

    def test_stale_running_marked_interrupted(self, tmp_path):
        """Bug 6: A story with 'running' status and stale log (>120s) should be 'interrupted'."""
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p'),
                Story(id=2, name='Story 2', prompt='p', depends_on=[1]),
            ]),
        ])
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'running', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        log_dir = tmp_path / 'logs'
        log_dir.mkdir()
        log_file = log_dir / 'story_1.stdout.log'
        log_file.write_text('some output')
        # Set mtime to 300s ago — stale
        old_time = time.time() - 300
        os.utime(log_file, (old_time, old_time))

        statuses = derive_node_statuses(plan, state_data, log_dir)
        assert statuses[1] == 'interrupted'
        # Dependents should be skipped (interrupted treated like failed for DAG)
        assert statuses[2] == 'skipped'

    def test_fresh_running_stays_running(self, tmp_path):
        """Bug 6: A story with 'running' status and fresh log stays 'running'."""
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p'),
            ]),
        ])
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'running', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        log_dir = tmp_path / 'logs'
        log_dir.mkdir()
        log_file = log_dir / 'story_1.stdout.log'
        log_file.write_text('some output')
        # mtime is now — fresh

        statuses = derive_node_statuses(plan, state_data, log_dir)
        assert statuses[1] == 'running'

    def test_running_no_log_stays_running(self, tmp_path):
        """Bug 6: A story with 'running' status and no log file stays 'running'."""
        plan = _minimal_plan(phases=[
            Phase(name='P1', stories=[
                Story(id=1, name='Story 1', prompt='p'),
            ]),
        ])
        state_data = {
            'results': [
                {'story_id': 1, 'status': 'running', 'timestamp': '2026-01-01T00:01:00'},
            ],
        }
        statuses = derive_node_statuses(plan, state_data, tmp_path)
        assert statuses[1] == 'running'


class TestDiscoverPlans:
    def test_finds_yaml_files(self, tmp_path):
        """discover_plans finds valid YAML plan files."""
        _write_plan_yaml(tmp_path, 'plan-a', project_dir=str(tmp_path))
        _write_plan_yaml(tmp_path, 'plan-b', project_dir=str(tmp_path))

        plans = discover_plans(tmp_path)
        assert 'plan-a' in plans
        assert 'plan-b' in plans
        assert len(plans) == 2

    def test_ignores_invalid_yaml(self, tmp_path):
        """discover_plans skips files that fail to parse."""
        _write_plan_yaml(tmp_path, 'good-plan', project_dir=str(tmp_path))
        (tmp_path / 'bad.yaml').write_text('not: valid: yaml: [[[')

        plans = discover_plans(tmp_path)
        assert 'good-plan' in plans
        assert len(plans) == 1

    def test_empty_directory(self, tmp_path):
        """discover_plans returns empty dict for directory with no YAML files."""
        plans = discover_plans(tmp_path)
        assert plans == {}


# ===========================================================================
# Route handler tests (aiohttp TestClient — multi-plan API)
# ===========================================================================


class TestApiPlans(AioHTTPTestCase):
    def setUp(self):
        import tempfile
        self._tmpdir = tempfile.TemporaryDirectory()
        self._env = _setup_env(Path(self._tmpdir.name))
        super().setUp()

    def tearDown(self):
        super().tearDown()
        self._tmpdir.cleanup()

    async def get_application(self):
        return create_app(
            plans_dir=self._env['plans_dir'],
            state_dir=self._env['state_dir'],
        )

    async def test_api_plans_returns_list(self):
        """GET /api/plans returns a list of plan summaries."""
        resp = await self.client.get('/api/plans')
        assert resp.status == 200
        data = await resp.json()
        assert isinstance(data, list)
        assert len(data) >= 1

        plan_info = data[0]
        assert 'name' in plan_info
        assert 'status' in plan_info
        assert 'passed' in plan_info
        assert 'failed' in plan_info
        assert 'running' in plan_info
        assert 'total' in plan_info

    async def test_api_plans_counts(self):
        """Plan summary has correct passed/total counts."""
        resp = await self.client.get('/api/plans')
        data = await resp.json()
        plan_info = next(p for p in data if p['name'] == 'test-plan')
        assert plan_info['total'] == 3
        assert plan_info['passed'] >= 1  # Story 1 is passed


class TestApiPlanState(AioHTTPTestCase):
    def setUp(self):
        import tempfile
        self._tmpdir = tempfile.TemporaryDirectory()
        self._env = _setup_env(Path(self._tmpdir.name))
        super().setUp()

    def tearDown(self):
        super().tearDown()
        self._tmpdir.cleanup()

    async def get_application(self):
        return create_app(
            plans_dir=self._env['plans_dir'],
            state_dir=self._env['state_dir'],
        )

    async def test_api_plan_state_returns_json(self):
        """GET /api/{plan}/state returns full state."""
        resp = await self.client.get('/api/test-plan/state')
        assert resp.status == 200
        assert resp.content_type == 'application/json'
        data = await resp.json()
        assert 'plan' in data
        assert 'dag' in data
        assert 'state' in data
        assert 'statuses' in data

    async def test_api_plan_state_includes_dag(self):
        resp = await self.client.get('/api/test-plan/state')
        data = await resp.json()
        dag = data['dag']
        assert 'nodes' in dag
        assert 'edges' in dag
        assert len(dag['nodes']) == 3

    async def test_api_plan_state_includes_plan_info(self):
        """Bug 5b: Plan info includes max_parallel, total_stories, execution_mode."""
        resp = await self.client.get('/api/test-plan/state')
        data = await resp.json()
        plan_info = data['plan']
        assert 'max_parallel' in plan_info
        assert 'total_stories' in plan_info
        assert 'execution_mode' in plan_info
        assert plan_info['total_stories'] == 3
        assert plan_info['max_parallel'] == 2  # from our YAML fixture

    async def test_api_plan_not_found(self):
        """GET /api/nonexistent/state returns 404."""
        resp = await self.client.get('/api/nonexistent/state')
        assert resp.status == 404


class TestApiPlanLogs(AioHTTPTestCase):
    def setUp(self):
        import tempfile
        self._tmpdir = tempfile.TemporaryDirectory()
        self._env = _setup_env(Path(self._tmpdir.name))
        super().setUp()

    def tearDown(self):
        super().tearDown()
        self._tmpdir.cleanup()

    async def get_application(self):
        return create_app(
            plans_dir=self._env['plans_dir'],
            state_dir=self._env['state_dir'],
        )

    async def test_api_logs_returns_content(self):
        resp = await self.client.get('/api/test-plan/logs/1/stdout')
        assert resp.status == 200
        text = await resp.text()
        assert 'line1' in text

    async def test_api_logs_missing_returns_empty_200(self):
        """Bug 5a: Missing log for any story returns empty 200, not 404."""
        resp = await self.client.get('/api/test-plan/logs/99/stdout')
        assert resp.status == 200
        text = await resp.text()
        assert text == ''

    async def test_api_logs_with_lines_param(self):
        resp = await self.client.get('/api/test-plan/logs/1/stdout?lines=2')
        assert resp.status == 200
        text = await resp.text()
        lines = text.strip().split('\n')
        assert len(lines) == 2  # last 2 lines

    async def test_api_logs_stderr(self):
        resp = await self.client.get('/api/test-plan/logs/1/stderr')
        assert resp.status == 200
        text = await resp.text()
        assert 'warn1' in text

    async def test_api_logs_invalid_stream_returns_404(self):
        resp = await self.client.get('/api/test-plan/logs/1/invalid')
        assert resp.status == 404


class TestApiPlanEvents(AioHTTPTestCase):
    def setUp(self):
        import tempfile
        self._tmpdir = tempfile.TemporaryDirectory()
        self._env = _setup_env(Path(self._tmpdir.name))
        super().setUp()

    def tearDown(self):
        super().tearDown()
        self._tmpdir.cleanup()

    async def get_application(self):
        return create_app(
            plans_dir=self._env['plans_dir'],
            state_dir=self._env['state_dir'],
            poll_interval=0.1,
        )

    async def test_events_stream_content_type(self):
        resp = await self.client.get('/api/test-plan/events')
        assert resp.status == 200
        assert 'text/event-stream' in resp.headers.get('Content-Type', '')
        # Read at least one chunk then close
        chunk = await resp.content.readline()
        assert chunk  # Should get something (data or keepalive)
        resp.close()

    async def test_events_include_statuses_and_dag(self):
        """Bug 2: SSE events must include statuses and dag, not just raw state."""
        resp = await self.client.get('/api/test-plan/events')
        assert resp.status == 200
        # Read the first data line
        line = b''
        while True:
            chunk = await resp.content.readline()
            if chunk.startswith(b'data:'):
                line = chunk
                break
            if not chunk:
                break
        resp.close()

        assert line.startswith(b'data:')
        payload = json.loads(line[len(b'data:'):].strip())
        assert 'state' in payload
        assert 'statuses' in payload
        assert 'dag' in payload


# ===========================================================================
# Integration tests
# ===========================================================================


@pytest.mark.asyncio
class TestDashboardIntegration:
    async def test_index_serves_svelte_app(self, tmp_path):
        """GET / should return the built Svelte index.html."""
        dist_dir = Path(__file__).parent.parent / 'dashboard' / 'dist'
        if not dist_dir.exists():
            pytest.skip("dashboard not built")

        env = _setup_env(tmp_path)
        app = create_app(
            plans_dir=env['plans_dir'],
            state_dir=env['state_dir'],
        )

        async with TestClient(TestServer(app)) as client:
            resp = await client.get('/')
            assert resp.status == 200
            text = await resp.text()
            assert '<div id="app">' in text
            assert resp.content_type == 'text/html'

    async def test_assets_serve_js(self, tmp_path):
        """GET /assets/*.js should return built JS bundle."""
        dist_dir = Path(__file__).parent.parent / 'dashboard' / 'dist'
        assets_dir = dist_dir / 'assets'
        if not assets_dir.exists():
            pytest.skip("dashboard not built")

        js_files = list(assets_dir.glob('*.js'))
        if not js_files:
            pytest.skip("no JS assets found")

        env = _setup_env(tmp_path)
        app = create_app(
            plans_dir=env['plans_dir'],
            state_dir=env['state_dir'],
        )

        js_name = js_files[0].name

        async with TestClient(TestServer(app)) as client:
            resp = await client.get(f'/assets/{js_name}')
            assert resp.status == 200
            assert 'javascript' in resp.content_type

    async def test_full_api_state_with_real_plan(self, tmp_path):
        """Test /api/{plan}/state with the actual mqtt_web.yaml plan."""
        plan_path = Path(__file__).parent.parent / 'plans' / 'mqtt_web.yaml'
        if not plan_path.exists():
            pytest.skip("mqtt_web.yaml not found")

        plans_dir = str(plan_path.parent)
        state_dir = str(tmp_path / '.orchestrator')

        app = create_app(
            plans_dir=plans_dir,
            state_dir=state_dir,
        )

        async with TestClient(TestServer(app)) as client:
            resp = await client.get('/api/mqtt-web/state')
            assert resp.status == 200
            data = await resp.json()

            assert 'plan' in data
            assert data['plan']['name'] == 'mqtt-web'
            assert 'dag' in data
            assert len(data['dag']['nodes']) > 0
            assert 'statuses' in data
            # All stories should be pending (no state file)
            for status in data['statuses'].values():
                assert status == 'pending'
