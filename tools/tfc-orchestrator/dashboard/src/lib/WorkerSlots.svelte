<script>
  import { dashboardData, planInfo, statuses, stories } from './stores.js';

  $: maxParallel = $planInfo?.max_parallel || 4;

  $: runningStories = (() => {
    const running = [];
    const s = $statuses;
    const nodes = $stories;
    for (const [id, status] of Object.entries(s)) {
      if (status === 'running') {
        const node = nodes.find(n => String(n.id) === String(id));
        running.push({ id, name: node?.name || `Story ${id}` });
      }
    }
    return running;
  })();

  $: slots = (() => {
    const result = [];
    for (let i = 0; i < maxParallel; i++) {
      result.push(runningStories[i] || null);
    }
    return result;
  })();
</script>

<div class="workers">
  {#each slots as slot, i}
    <div class="slot" class:active={slot}>
      {#if slot}
        <span class="slot-id">#{slot.id}</span>
        <span class="slot-name">{slot.name}</span>
      {:else}
        <span class="slot-idle">idle</span>
      {/if}
    </div>
  {/each}
</div>

<style>
  .workers {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
    flex-wrap: wrap;
  }
  .slot {
    flex: 1;
    min-width: 140px;
    padding: 0.5rem 0.75rem;
    border-radius: 6px;
    background: #2a2a3e;
    border: 1px solid #333;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.85rem;
    overflow: hidden;
  }
  .slot.active {
    background: #1a3a5c;
    border-color: #2196f3;
  }
  .slot-id {
    font-weight: 700;
    color: #2196f3;
    flex-shrink: 0;
  }
  .slot-name {
    color: #e0e0e0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .slot-idle {
    color: #666;
    font-style: italic;
  }
</style>
