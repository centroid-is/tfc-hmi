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
                'depends_on': list(story.depends_on),
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
    - Has result with status 'running' + log mtime > 120s → "interrupted"
    - Has result with status 'running' + log mtime < 120s → "running"
    - No result but log file mtime < 120s ago → "running"
    - Otherwise → "pending"
    """
    results = state_data.get('results', [])
    result_map: dict[int, str] = {}
    for r in results:
        result_map[r['story_id']] = r['status']

    # Use DAGScheduler to compute cascade skips
    dag = DAGScheduler.from_plan(plan)

    # First pass: identify stale running stories so we can mark them as failed
    # in the DAG (for cascade purposes) but display them as "interrupted"
    now = time.time()
    interrupted_ids: set[int] = set()

    for sid, status in result_map.items():
        if status == 'running':
            log_file = log_dir / f'story_{sid}.stdout.log'
            if log_file.exists():
                mtime = log_file.stat().st_mtime
                if now - mtime > 120:
                    interrupted_ids.add(sid)

    for sid, status in result_map.items():
        try:
            if status == 'pass':
                dag.mark_running(sid)
                dag.mark_passed(sid)
            elif status == 'running':
                if sid in interrupted_ids:
                    # Stale running — treat as failed for DAG cascade
                    dag.mark_running(sid)
                    dag.mark_failed(sid)
                else:
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

    statuses: dict[int, str] = {}
    for phase in plan.phases:
        for story in phase.stories:
            sid = story.id
            dag_status = dag.get_status(sid)

            if dag_status == NodeStatus.PASSED:
                statuses[sid] = 'passed'
            elif dag_status == NodeStatus.FAILED:
                # Check if this was an interrupted story
                if sid in interrupted_ids:
                    statuses[sid] = 'interrupted'
                else:
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


def discover_plans(plans_dir: Path) -> dict[str, Plan]:
    """Scan directory for *.yaml plan files, return {plan_name: Plan}."""
    plans = {}
    for f in sorted(plans_dir.glob('*.yaml')):
        try:
            plan = Plan.from_yaml(str(f))
            plans[plan.name] = plan
        except Exception:
            pass
    return plans


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _plan_paths(app, plan_name):
    """Look up plan, state_path, and log_dir for a plan-scoped route."""
    plan = app['plans'].get(plan_name)
    if not plan:
        raise web.HTTPNotFound(text=f'Plan not found: {plan_name}')
    state_dir = Path(app['state_dir'])
    state_path = state_dir / f'{plan_name}.state.json'
    log_dir = state_dir / 'logs' / plan_name
    return plan, state_path, log_dir


# ---------------------------------------------------------------------------
# aiohttp app
# ---------------------------------------------------------------------------

def create_app(
    plans_dir: str,
    state_dir: str | None = None,
    poll_interval: float = 2.0,
) -> web.Application:
    plans = discover_plans(Path(plans_dir))
    if not plans:
        raise ValueError(f'No valid plan files found in {plans_dir}')

    # Determine state_dir from first plan's project_dir if not given
    if state_dir is None:
        first_plan = next(iter(plans.values()))
        state_dir = str(Path(first_plan.project_dir) / '.orchestrator')

    app = web.Application()
    app['plans'] = plans
    app['plans_dir'] = plans_dir
    app['state_dir'] = state_dir
    app['poll_interval'] = poll_interval

    # Multi-plan routes
    app.router.add_get('/api/plans', _handle_plans)
    app.router.add_get('/api/{plan_name}/state', _handle_state)
    app.router.add_get('/api/{plan_name}/events', _handle_events)
    app.router.add_get('/api/{plan_name}/logs/{story_id}/{stream}', _handle_logs)
    app.router.add_get('/api/{plan_name}/logs/{story_id}/{stream}/tail', _handle_log_tail)

    # Static file serving for Svelte frontend
    if _DIST_DIR.is_dir():
        app.router.add_get('/', _handle_index)
        app.router.add_static('/assets', _DIST_DIR / 'assets')

    return app


async def _handle_plans(request: web.Request) -> web.Response:
    plans = request.app['plans']
    state_dir = Path(request.app['state_dir'])

    result = []
    for name, plan in plans.items():
        state_path = state_dir / f'{name}.state.json'
        log_dir = state_dir / 'logs' / name
        state_data = read_state(state_path)
        statuses = derive_node_statuses(plan, state_data, log_dir)
        total = sum(len(p.stories) for p in plan.phases)
        passed = sum(1 for s in statuses.values() if s == 'passed')
        failed = sum(1 for s in statuses.values() if s in ('failed', 'interrupted'))
        running = sum(1 for s in statuses.values() if s == 'running')
        status = (
            'complete' if passed == total
            else 'failed' if failed > 0
            else 'running' if running > 0
            else 'pending'
        )
        result.append({
            'name': name,
            'status': status,
            'passed': passed,
            'failed': failed,
            'running': running,
            'total': total,
        })
    return web.json_response(result)


async def _handle_state(request: web.Request) -> web.Response:
    plan_name = request.match_info['plan_name']
    plan, state_path, log_dir = _plan_paths(request.app, plan_name)

    state_data = read_state(state_path)
    dag_info = build_dag_info(plan)
    statuses = derive_node_statuses(plan, state_data, log_dir)

    return web.json_response({
        'plan': {
            'name': plan.name,
            'model': plan.model,
            'max_parallel': plan.workers.max_parallel if plan.workers else 1,
            'total_stories': sum(len(p.stories) for p in plan.phases),
            'execution_mode': plan.execution_mode or 'sequential',
        },
        'dag': dag_info,
        'state': state_data,
        'statuses': {str(k): v for k, v in statuses.items()},
    })


async def _handle_events(request: web.Request) -> web.StreamResponse:
    plan_name = request.match_info['plan_name']
    plan, state_path, log_dir = _plan_paths(request.app, plan_name)
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
                dag_info = build_dag_info(plan)
                statuses = derive_node_statuses(plan, state_data, log_dir)
                payload = json.dumps({
                    'state': state_data,
                    'statuses': {str(k): v for k, v in statuses.items()},
                    'dag': dag_info,
                })
                await resp.write(f'data: {payload}\n\n'.encode())

            now = time.time()
            if now - last_keepalive >= 15:
                await resp.write(b': keepalive\n\n')
                last_keepalive = now

            await asyncio.sleep(poll_interval)
    except Exception:
        # Client disconnected — silently stop streaming
        pass

    return resp


async def _handle_logs(request: web.Request) -> web.Response:
    plan_name = request.match_info['plan_name']
    _, _, log_dir = _plan_paths(request.app, plan_name)
    story_id = request.match_info['story_id']
    stream = request.match_info['stream']

    if stream not in ('stdout', 'stderr'):
        raise web.HTTPNotFound(text=f'Invalid stream: {stream}')

    log_file = log_dir / f'story_{story_id}.{stream}.log'
    if not log_file.exists():
        return web.Response(text='', content_type='text/plain')

    lines_param = int(request.query.get('lines', '200'))
    content = log_file.read_text()
    all_lines = content.splitlines()
    tail_lines = all_lines[-lines_param:] if len(all_lines) > lines_param else all_lines

    return web.Response(text='\n'.join(tail_lines) + '\n', content_type='text/plain')


async def _handle_log_tail(request: web.Request) -> web.StreamResponse:
    plan_name = request.match_info['plan_name']
    _, _, log_dir = _plan_paths(request.app, plan_name)
    story_id = request.match_info['story_id']
    stream = request.match_info['stream']

    if stream not in ('stdout', 'stderr'):
        raise web.HTTPNotFound(text=f'Invalid stream: {stream}')

    log_file = log_dir / f'story_{story_id}.{stream}.log'

    # Wait for log file to appear (up to 30s)
    for _ in range(30):
        if log_file.exists():
            break
        await asyncio.sleep(1)
    if not log_file.exists():
        return web.Response(text='', content_type='text/plain')

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
                # Send each line as a separate SSE event (no JSON wrapping)
                for line in new_data.splitlines():
                    await resp.write(f'data: {line}\n\n'.encode())

            await asyncio.sleep(1)
    except Exception:
        # Client disconnected — silently stop streaming
        pass

    return resp


async def _handle_index(request: web.Request) -> web.FileResponse:
    return web.FileResponse(_DIST_DIR / 'index.html')


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run_dashboard(plans_dir: str, host: str = '127.0.0.1', port: int = 8080):
    app = create_app(plans_dir)
    print(f'Dashboard: http://{host}:{port}')
    web.run_app(app, host=host, port=port, print=None)
