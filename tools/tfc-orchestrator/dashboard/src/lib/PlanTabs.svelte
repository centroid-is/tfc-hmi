<script>
  import { planList, activePlan, selectedStory } from './stores.js';
  import { connectPlan } from './sse.js';

  $: activePlans = $planList.filter(p => p.status === 'running' || p.status === 'pending');
  $: finishedPlans = $planList.filter(p => p.status === 'complete' || p.status === 'failed');

  function selectPlan(name) {
    activePlan.set(name);
    selectedStory.set(null);
    connectPlan(name);
  }
</script>

<nav class="plan-tabs">
  {#each activePlans as plan}
    <button class="tab" class:active={$activePlan === plan.name}
            on:click={() => selectPlan(plan.name)}>
      <span class="tab-name">{plan.name}</span>
      <span class="tab-progress">{plan.passed}/{plan.total}</span>
    </button>
  {/each}

  {#if finishedPlans.length > 0}
    <select class="finished-select"
            value={finishedPlans.some(p => p.name === $activePlan) ? $activePlan : ''}
            on:change={e => { if (e.target.value) selectPlan(e.target.value); }}>
      <option value="" disabled>Finished ({finishedPlans.length})</option>
      {#each finishedPlans as plan}
        <option value={plan.name}>
          {plan.name} — {plan.status} ({plan.passed}/{plan.total})
        </option>
      {/each}
    </select>
  {/if}
</nav>

<style>
  .plan-tabs {
    display: flex;
    flex-direction: row;
    background: #0f1829;
    padding: 0.5rem 1rem;
    gap: 0;
    border-bottom: 2px solid #16213e;
    margin-bottom: 1rem;
  }
  .tab {
    background: transparent;
    border: none;
    color: #888;
    padding: 0.6rem 1.2rem;
    font-family: inherit;
    font-size: 0.9rem;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    transition: all 0.2s;
  }
  .tab.active {
    color: #fff;
    border-bottom-color: #2196f3;
    background: #16213e;
  }
  .tab:hover {
    color: #ccc;
  }
  .tab-name {
    font-weight: 600;
  }
  .tab-progress {
    margin-left: 0.5rem;
    font-size: 0.75rem;
    opacity: 0.7;
  }
  .finished-select {
    margin-left: auto;
    background: #16213e;
    color: #e0e0e0;
    border: 1px solid #333;
    border-radius: 4px;
    padding: 0.4rem 0.6rem;
    font-family: inherit;
    font-size: 0.8rem;
    cursor: pointer;
  }
</style>
