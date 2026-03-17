"""Dashboard — aiohttp web server for monitoring orchestrator runs."""
import asyncio
import json
import logging
import time
from pathlib import Path

from aiohttp import web

from .dag import DAGScheduler, NodeStatus
from .models import Plan

_log = logging.getLogger(__name__)

_DIST_DIR = Path(__file__).parent.parent / 'dashboard' / 'dist'


# ---------------------------------------------------------------------------
# Pure functions
# ---------------------------------------------------------------------------

def read_state(state_path: Path) -> dict:
    """Read state JSON file. Returns ``{"results": []}`` if missing."""
    try:
        return json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {'results': []}


def build_dag_info(plan: Plan) -> dict:
    """Return ``{"nodes": [...], "edges": [[from, to], ...]}`` from plan."""
    nodes = []
    edges = []
    for phase in plan.phases:
        for story in phase.stories:
            nodes.append({
                'id': story.id,
                'name': story.name,
                'phase': phase.name,
            })
            for dep in story.depends_on:
                edges.append([dep, story.id])
    return {'nodes': nodes, 'edges': edges}


def derive_node_statuses(
    plan: Plan, state_data: dict, log_dir: Path,
) -> dict[int, str]:
    """Map story IDs to status strings.

    Logic:
    - Has result with status 'pass' → "passed"
    - Has result with status 'fail' → "failed"
    - Dependency failed → "skipped" (uses DAGScheduler cascade logic)
    - No result but log file mtime < 120s ago → "running"
    - Otherwise → "pending"
    """
    results = state_data.get('results', [])
    result_map: dict[int, str] = {}
    for r in results:
        result_map[r['story_id']] = r['status']

    # Use DAGScheduler to compute cascade skips
    dag = DAGScheduler.from_plan(plan)
    for sid, status in result_map.items():
        try:
            if status == 'pass':
                dag.mark_running(sid)
                dag.mark_passed(sid)
            elif status == 'running':
                dag.mark_running(sid)
                # Leave as RUNNING — don't mark failed
            elif status == 'fail':
                dag.mark_running(sid)
                dag.mark_failed(sid)
            else:
                _log.warning('Unknown result status %r for story %s', status, sid)
                dag.mark_running(sid)
                dag.mark_failed(sid)
        except KeyError:
            pass

    now = time.time()
    statuses: dict[int, str] = {}
    for phase in plan.phases:
        for story in phase.stories:
            sid = story.id
            dag_status = dag.get_status(sid)

            if dag_status == NodeStatus.PASSED:
                statuses[sid] = 'passed'
            elif dag_status == NodeStatus.FAILED:
                statuses[sid] = 'failed'
            elif dag_status == NodeStatus.SKIPPED:
                statuses[sid] = 'skipped'
            elif dag_status == NodeStatus.RUNNING:
                statuses[sid] = 'running'
            elif dag_status == NodeStatus.PENDING:
                # Check for running via log file mtime
                log_file = log_dir / f'story_{sid}.stdout.log'
                if log_file.exists():
                    mtime = log_file.stat().st_mtime
                    if now - mtime < 120:
                        statuses[sid] = 'running'
                    else:
                        statuses[sid] = 'pending'
                else:
                    statuses[sid] = 'pending'
            else:
                statuses[sid] = dag_status.value

    return statuses


# ---------------------------------------------------------------------------
# aiohttp app
# ---------------------------------------------------------------------------

def create_app(
    plan_path: str,
    state_dir: str | None = None,
    poll_interval: float = 2.0,
) -> web.Application:
    plan = Plan.from_yaml(plan_path)
    if state_dir is None:
        state_dir = str(Path(plan.project_dir) / '.orchestrator')
    state_path = Path(state_dir) / f'{plan.name}.state.json'
    log_dir = Path(state_dir) / 'logs' / plan.name

    app = web.Application()
    app['plan'] = plan
    app['state_path'] = state_path
    app['log_dir'] = log_dir
    app['poll_interval'] = poll_interval

    app.router.add_get('/api/state', _handle_state)
    app.router.add_get('/api/events', _handle_events)
    app.router.add_get('/api/logs/{story_id}/{stream}', _handle_logs)
    app.router.add_get('/api/logs/{story_id}/{stream}/tail', _handle_log_tail)

    # Static file serving for Svelte frontend
    if _DIST_DIR.is_dir():
        app.router.add_get('/', _handle_index)
        app.router.add_static('/assets', _DIST_DIR / 'assets')

    return app


async def _handle_state(request: web.Request) -> web.Response:
    plan: Plan = request.app['plan']
    state_path: Path = request.app['state_path']
    log_dir: Path = request.app['log_dir']

    state_data = read_state(state_path)
    dag_info = build_dag_info(plan)
    statuses = derive_node_statuses(plan, state_data, log_dir)

    return web.json_response({
        'plan': {'name': plan.name, 'model': plan.model},
        'dag': dag_info,
        'state': state_data,
        'statuses': {str(k): v for k, v in statuses.items()},
    })


async def _handle_events(request: web.Request) -> web.StreamResponse:
    state_path: Path = request.app['state_path']
    poll_interval: float = request.app['poll_interval']

    resp = web.StreamResponse()
    resp.content_type = 'text/event-stream'
    resp.headers['Cache-Control'] = 'no-cache'
    resp.headers['X-Accel-Buffering'] = 'no'
    await resp.prepare(request)

    last_count = -1
    last_ts = ''
    last_keepalive = time.time()

    try:
        while True:
            state_data = read_state(state_path)
            results = state_data.get('results', [])
            count = len(results)
            ts = results[-1].get('timestamp', '') if results else ''

            if count != last_count or ts != last_ts:
                last_count = count
                last_ts = ts
                payload = json.dumps(state_data)
                await resp.write(f'data: {payload}\n\n'.encode())

            now = time.time()
            if now - last_keepalive >= 15:
                await resp.write(b': keepalive\n\n')
                last_keepalive = now

            await asyncio.sleep(poll_interval)
    except (ConnectionResetError, ConnectionAbortedError, asyncio.CancelledError, OSError):
        # Client disconnected — silently stop streaming
        pass

    return resp


async def _handle_logs(request: web.Request) -> web.Response:
    log_dir: Path = request.app['log_dir']
    story_id = request.match_info['story_id']
    stream = request.match_info['stream']

    if stream not in ('stdout', 'stderr'):
        raise web.HTTPNotFound(text=f'Invalid stream: {stream}')

    log_file = log_dir / f'story_{story_id}.{stream}.log'
    if not log_file.exists():
        raise web.HTTPNotFound(text=f'Log not found: story_{story_id}.{stream}.log')

    lines_param = int(request.query.get('lines', '200'))
    content = log_file.read_text()
    all_lines = content.splitlines()
    tail_lines = all_lines[-lines_param:] if len(all_lines) > lines_param else all_lines

    return web.Response(text='\n'.join(tail_lines) + '\n', content_type='text/plain')


async def _handle_log_tail(request: web.Request) -> web.StreamResponse:
    log_dir: Path = request.app['log_dir']
    story_id = request.match_info['story_id']
    stream = request.match_info['stream']

    if stream not in ('stdout', 'stderr'):
        raise web.HTTPNotFound(text=f'Invalid stream: {stream}')

    log_file = log_dir / f'story_{story_id}.{stream}.log'
    if not log_file.exists():
        raise web.HTTPNotFound(text=f'Log not found')

    resp = web.StreamResponse()
    resp.content_type = 'text/event-stream'
    resp.headers['Cache-Control'] = 'no-cache'
    await resp.prepare(request)

    offset = log_file.stat().st_size

    try:
        while True:
            size = log_file.stat().st_size
            if size > offset:
                with open(log_file) as f:
                    f.seek(offset)
                    new_data = f.read()
                offset = size
                payload = json.dumps(new_data)
                await resp.write(f'data: {payload}\n\n'.encode())

            await asyncio.sleep(1)
    except (ConnectionResetError, ConnectionAbortedError, asyncio.CancelledError, OSError):
        # Client disconnected — silently stop streaming
        pass

    return resp


async def _handle_index(request: web.Request) -> web.FileResponse:
    return web.FileResponse(_DIST_DIR / 'index.html')


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run_dashboard(plan_path: str, host: str = '127.0.0.1', port: int = 8080):
    app = create_app(plan_path)
    print(f'Dashboard: http://{host}:{port}')
    web.run_app(app, host=host, port=port, print=None)
