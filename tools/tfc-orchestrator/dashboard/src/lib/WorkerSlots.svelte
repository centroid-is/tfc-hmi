<script>
  import { planInfo, stories, statuses } from './stores.js';

  $: maxSlots = $planInfo?.max_parallel || 1;
  $: runningStories = ($stories || []).filter(n => ($statuses || {})[n.id] === 'running');
  $: slots = Array.from({ length: maxSlots }, (_, i) => runningStories[i] || null);
</script>

<div class="worker-slots">
  <span class="slots-label">Workers</span>
  <div class="slots-row">
    {#each slots as story, i}
      <div class="slot" class:active={story !== null}>
        {#if story}
          <span class="slot-id">#{story.id}</span>
          <span class="slot-name">{story.name}</span>
        {:else}
          <span class="slot-idle">idle</span>
        {/if}
      </div>
    {/each}
  </div>
</div>

<style>
  .worker-slots {
    display: flex;
    flex-direction: row;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 1rem;
  }
  .slots-label {
    color: #888;
    font-size: 0.8rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .slots-row {
    display: flex;
    flex-direction: row;
    gap: 0.5rem;
  }
  .slot {
    background: #16213e;
    border-radius: 6px;
    padding: 0.4rem 0.8rem;
    min-width: 120px;
    border: 1px solid #333;
    font-size: 0.8rem;
  }
  .slot.active {
    border-color: #2196f3;
    background: #1a2744;
  }
  .slot-id {
    font-weight: 700;
    color: #2196f3;
    margin-right: 0.4rem;
  }
  .slot-name {
    color: #e0e0e0;
  }
  .slot-idle {
    color: #555;
    font-style: italic;
  }
</style>
