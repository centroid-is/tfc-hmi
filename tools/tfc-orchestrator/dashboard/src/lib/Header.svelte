<script>
  import { onDestroy } from 'svelte';
  import { dashboardData, planInfo, statuses } from './stores.js';

  let elapsed = '';
  let interval;

  function formatElapsed(startedAt) {
    if (!startedAt) return '--';
    const diff = Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000);
    if (diff < 0) return '--';
    const h = Math.floor(diff / 3600);
    const m = Math.floor((diff % 3600) / 60);
    const s = diff % 60;
    if (h > 0) return `${h}h ${m}m ${s}s`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  }

  function updateElapsed() {
    const startedAt = $dashboardData?.state?.started_at;
    elapsed = formatElapsed(startedAt);
  }

  interval = setInterval(updateElapsed, 1000);
  $: $dashboardData, updateElapsed();
  onDestroy(() => clearInterval(interval));

  $: counts = (() => {
    const s = $statuses;
    const result = { passed: 0, failed: 0, skipped: 0, pending: 0, running: 0 };
    for (const v of Object.values(s)) {
      if (result[v] !== undefined) result[v]++;
    }
    return result;
  })();

  $: overallStatus = (() => {
    if (counts.failed > 0) return 'failed';
    if (counts.running > 0) return 'running';
    if (counts.pending > 0 && counts.passed > 0) return 'running';
    if (counts.passed > 0 && counts.pending === 0 && counts.running === 0) return 'complete';
    return 'pending';
  })();
</script>

<header class="header">
  <div class="plan-name">{$planInfo?.name || 'orchestrator'}</div>
  <div class="badge badge-{overallStatus}">
    {overallStatus === 'running' ? 'Running' : overallStatus === 'complete' ? 'Complete' : overallStatus === 'failed' ? 'Failed' : 'Pending'}
  </div>
  <div class="elapsed">{elapsed}</div>
  <div class="counters">
    {#if counts.passed}<span class="counter passed">{counts.passed} passed</span>{/if}
    {#if counts.failed}<span class="counter failed">{counts.failed} failed</span>{/if}
    {#if counts.running}<span class="counter running">{counts.running} running</span>{/if}
    {#if counts.skipped}<span class="counter skipped">{counts.skipped} skipped</span>{/if}
    {#if counts.pending}<span class="counter pending">{counts.pending} pending</span>{/if}
  </div>
</header>

<style>
  .header {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 0.75rem 1rem;
    background: #16213e;
    border-radius: 8px;
    margin-bottom: 1rem;
    flex-wrap: wrap;
  }
  .plan-name {
    font-size: 1.4rem;
    font-weight: 700;
    color: #fff;
  }
  .badge {
    padding: 0.25rem 0.75rem;
    border-radius: 12px;
    font-size: 0.8rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .badge-running {
    background: #2196f3;
    color: #fff;
    animation: pulse 2s ease-in-out infinite;
  }
  .badge-complete { background: #4caf50; color: #fff; }
  .badge-failed { background: #f44336; color: #fff; }
  .badge-pending { background: #555; color: #ccc; }
  .elapsed {
    font-size: 1.1rem;
    color: #888;
    font-variant-numeric: tabular-nums;
  }
  .counters {
    display: flex;
    gap: 0.75rem;
    margin-left: auto;
    flex-wrap: wrap;
  }
  .counter {
    font-size: 0.85rem;
    font-weight: 500;
  }
  .counter.passed { color: #4caf50; }
  .counter.failed { color: #f44336; }
  .counter.running { color: #2196f3; }
  .counter.skipped { color: #ff9800; }
  .counter.pending { color: #888; }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.6; }
  }
</style>
