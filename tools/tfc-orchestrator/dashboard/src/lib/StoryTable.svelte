<script>
  import { onDestroy } from 'svelte';
  import { dashboardData, stories, statuses, selectedStory } from './stores.js';

  const STATUS_COLORS = {
    passed: '#4caf50',
    failed: '#f44336',
    running: '#2196f3',
    skipped: '#ff9800',
    pending: '#555',
    interrupted: '#9e9e9e',
  };

  $: results = $dashboardData?.state?.results || [];
  $: resultMap = (() => {
    const m = {};
    for (const r of results) {
      m[r.story_id ?? r.id] = r;
    }
    return m;
  })();

  let now = Date.now();
  const interval = setInterval(() => { now = Date.now(); }, 1000);
  onDestroy(() => clearInterval(interval));

  function formatDuration(result, status, _now) {
    if (!result) return status === 'running' ? '...' : '--';

    // Completed: use duration_seconds
    if (result.duration_seconds && result.duration_seconds > 0) {
      const secs = Math.floor(result.duration_seconds);
      const m = Math.floor(secs / 60);
      const s = secs % 60;
      return m > 0 ? `${m}m ${s}s` : `${s}s`;
    }

    // Running: compute from started_at
    if (result.started_at && status === 'running') {
      const startMs = new Date(result.started_at).getTime();
      const secs = Math.floor((_now - startMs) / 1000);
      if (secs < 0) return '...';
      const m = Math.floor(secs / 60);
      const s = secs % 60;
      return m > 0 ? `${m}m ${s}s` : `${s}s`;
    }

    return '--';
  }

  function handleRowClick(id) {
    selectedStory.update(v => v === id ? null : id);
  }
</script>

<div class="table-container">
  <table>
    <thead>
      <tr>
        <th>ID</th>
        <th>Name</th>
        <th>Status</th>
        <th>Duration</th>
        <th>Retries</th>
        <th>Review</th>
        <th>Verify</th>
      </tr>
    </thead>
    <tbody>
      {#each $stories as node}
        {@const status = $statuses[node.id] || 'pending'}
        {@const result = resultMap[node.id]}
        <tr class:selected={$selectedStory === node.id}
            on:click={() => handleRowClick(node.id)}>
          <td class="id-cell">{node.id}</td>
          <td class="name-cell">{node.name}</td>
          <td>
            <span class="status-badge" style="background: {STATUS_COLORS[status] || STATUS_COLORS.pending}">
              {status}
            </span>
          </td>
          <td class="mono">{formatDuration(result, status, now)}</td>
          <td class="mono">{result?.retry_count ?? '--'}</td>
          <td class="mono">{result?.review_iterations ?? '--'}</td>
          <td class="mono">
            {#if result?.verification_passed === true}
              <span style="color: #4caf50">✓</span>
            {:else if result?.verification_passed === false}
              <span style="color: #f44336">✗</span>
            {:else}
              --
            {/if}
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .table-container {
    background: #16213e;
    border-radius: 8px;
    overflow-x: auto;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.85rem;
  }
  thead {
    position: sticky;
    top: 0;
  }
  th {
    text-align: left;
    padding: 0.6rem 0.75rem;
    background: #1a2744;
    color: #888;
    font-weight: 600;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-bottom: 1px solid #333;
  }
  td {
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid #222;
    color: #e0e0e0;
  }
  tr {
    cursor: pointer;
    transition: background 0.15s;
  }
  tr:hover { background: #1e2d4a; }
  tr.selected { background: #253a5c; }
  .id-cell { font-weight: 700; color: #aaa; }
  .name-cell { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .mono { font-variant-numeric: tabular-nums; color: #aaa; }
  .status-badge {
    display: inline-block;
    padding: 0.15rem 0.5rem;
    border-radius: 10px;
    font-size: 0.75rem;
    font-weight: 600;
    color: #fff;
    text-transform: uppercase;
  }
</style>
