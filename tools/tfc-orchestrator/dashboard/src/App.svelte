<script>
  import { onMount, onDestroy } from 'svelte';
  import { connectSSE, disconnectSSE } from './lib/sse.js';
  import { dashboardData } from './lib/stores.js';
  import Header from './lib/Header.svelte';
  import WorkerSlots from './lib/WorkerSlots.svelte';
  import DagGraph from './lib/DagGraph.svelte';
  import StoryTable from './lib/StoryTable.svelte';
  import LogViewer from './lib/LogViewer.svelte';

  onMount(() => connectSSE());
  onDestroy(() => disconnectSSE());
</script>

<main>
  {#if $dashboardData}
    <Header />
    <WorkerSlots />
    <div class="content">
      <DagGraph />
      <StoryTable />
    </div>
    <LogViewer />
  {:else}
    <div class="loading">Connecting to orchestrator...</div>
  {/if}
</main>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    background: #1a1a2e;
    color: #e0e0e0;
    font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
  }
  :global(*, *::before, *::after) {
    box-sizing: border-box;
  }
  main {
    max-width: 1400px;
    margin: 0 auto;
    padding: 1rem;
  }
  .content {
    display: grid;
    grid-template-columns: 2fr 3fr;
    gap: 1rem;
  }
  @media (max-width: 900px) {
    .content {
      grid-template-columns: 1fr;
    }
  }
  .loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 60vh;
    color: #888;
    font-size: 1.1rem;
  }
</style>
