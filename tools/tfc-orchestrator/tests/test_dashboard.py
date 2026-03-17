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
    read_state,
)
from orchestrator.models import Phase, Plan, Story


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


def _write_plan_yaml(path: Path, plan_name: str = 'test-plan') -> Path:
    """Write a minimal plan YAML and return its path."""
    yaml_content = f"""\
name: {plan_name}
project_dir: /tmp/test
model: sonnet
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
    plan_path = path / 'plan.yaml'
    plan_path.write_text(yaml_content)
    return plan_path


def _setup_env(tmp_path: Path) -> dict:
    """Set up a temp environment with plan YAML, state, and logs."""
    plan_path = _write_plan_yaml(tmp_path)

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
        'plan_path': str(plan_path),
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


# ===========================================================================
# Route handler tests (aiohttp TestClient, no pytest-aiohttp plugin)
# ===========================================================================


class TestApiState(AioHTTPTestCase):
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
            plan_path=self._env['plan_path'],
            state_dir=self._env['state_dir'],
        )

    async def test_api_state_returns_json(self):
        resp = await self.client.get('/api/state')
        assert resp.status == 200
        assert resp.content_type == 'application/json'
        data = await resp.json()
        assert 'plan' in data
        assert 'dag' in data
        assert 'state' in data
        assert 'statuses' in data

    async def test_api_state_includes_dag(self):
        resp = await self.client.get('/api/state')
        data = await resp.json()
        dag = data['dag']
        assert 'nodes' in dag
        assert 'edges' in dag
        assert len(dag['nodes']) == 3


class TestApiLogs(AioHTTPTestCase):
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
            plan_path=self._env['plan_path'],
            state_dir=self._env['state_dir'],
        )

    async def test_api_logs_returns_content(self):
        resp = await self.client.get('/api/logs/1/stdout')
        assert resp.status == 200
        text = await resp.text()
        assert 'line1' in text

    async def test_api_logs_missing_returns_404(self):
        resp = await self.client.get('/api/logs/99/stdout')
        assert resp.status == 404

    async def test_api_logs_with_lines_param(self):
        resp = await self.client.get('/api/logs/1/stdout?lines=2')
        assert resp.status == 200
        text = await resp.text()
        lines = text.strip().split('\n')
        assert len(lines) == 2  # last 2 lines

    async def test_api_logs_stderr(self):
        resp = await self.client.get('/api/logs/1/stderr')
        assert resp.status == 200
        text = await resp.text()
        assert 'warn1' in text

    async def test_api_logs_invalid_stream_returns_404(self):
        resp = await self.client.get('/api/logs/1/invalid')
        assert resp.status == 404


class TestApiEvents(AioHTTPTestCase):
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
            plan_path=self._env['plan_path'],
            state_dir=self._env['state_dir'],
            poll_interval=0.1,
        )

    async def test_events_stream_content_type(self):
        resp = await self.client.get('/api/events')
        assert resp.status == 200
        assert 'text/event-stream' in resp.headers.get('Content-Type', '')
        # Read at least one chunk then close
        chunk = await resp.content.readline()
        assert chunk  # Should get something (data or keepalive)
        resp.close()


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
            plan_path=env['plan_path'],
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
            plan_path=env['plan_path'],
            state_dir=env['state_dir'],
        )

        js_name = js_files[0].name

        async with TestClient(TestServer(app)) as client:
            resp = await client.get(f'/assets/{js_name}')
            assert resp.status == 200
            assert 'javascript' in resp.content_type

    async def test_full_api_state_with_real_plan(self, tmp_path):
        """Test /api/state with the actual mqtt_web.yaml plan."""
        plan_path = Path(__file__).parent.parent / 'plans' / 'mqtt_web.yaml'
        if not plan_path.exists():
            pytest.skip("mqtt_web.yaml not found")

        state_dir = str(tmp_path / '.orchestrator')

        app = create_app(
            plan_path=str(plan_path),
            state_dir=state_dir,
        )

        async with TestClient(TestServer(app)) as client:
            resp = await client.get('/api/state')
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
