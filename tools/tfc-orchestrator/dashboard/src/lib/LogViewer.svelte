<script>
  import { onDestroy } from 'svelte';
  import { selectedStory, stories } from './stores.js';

  let activeTab = 'stdout';
  let logContent = '';
  let logEl;
  let eventSource = null;

  $: storyNode = $stories.find(n => n.id === $selectedStory);
  $: storyId = $selectedStory;

  // React to story or tab changes
  $: if (storyId !== null) {
    loadLogs(storyId, activeTab);
  } else {
    cleanup();
  }

  function cleanup() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }
    logContent = '';
  }

  async function loadLogs(id, tab) {
    cleanup();
    if (id === null) return;

    try {
      const res = await fetch(`/api/logs/${id}/${tab}`);
      logContent = res.ok ? await res.text() : '';
    } catch {
      logContent = '(failed to load logs)';
    }

    // Connect SSE for live tail
    eventSource = new EventSource(`/api/logs/${id}/${tab}/tail`);
    eventSource.onmessage = (event) => {
      logContent += event.data + '\n';
      scrollToBottom();
    };
    eventSource.onerror = () => {
      // SSE auto-reconnects
    };

    scrollToBottom();
  }

  function scrollToBottom() {
    requestAnimationFrame(() => {
      if (logEl) logEl.scrollTop = logEl.scrollHeight;
    });
  }

  function close() {
    selectedStory.set(null);
  }

  function switchTab(tab) {
    activeTab = tab;
  }

  onDestroy(() => cleanup());
</script>

{#if $selectedStory !== null}
  <div class="log-viewer">
    <div class="log-header">
      <span class="log-title">Story {$selectedStory}: {storyNode?.name || ''}</span>
      <div class="tabs">
        <button class="tab" class:active={activeTab === 'stdout'}
                on:click={() => switchTab('stdout')}>stdout</button>
        <button class="tab" class:active={activeTab === 'stderr'}
                on:click={() => switchTab('stderr')}>stderr</button>
      </div>
      <button class="close-btn" on:click={close}>&times;</button>
    </div>
    <pre class="log-content" bind:this={logEl}>{logContent}</pre>
  </div>
{/if}

<style>
  .log-viewer {
    margin-top: 1rem;
    background: #0d1117;
    border-radius: 8px;
    border: 1px solid #333;
    display: flex;
    flex-direction: column;
    max-height: 400px;
  }
  .log-header {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 0.5rem 0.75rem;
    background: #161b22;
    border-bottom: 1px solid #333;
    border-radius: 8px 8px 0 0;
  }
  .log-title {
    font-weight: 700;
    font-size: 0.9rem;
    color: #e0e0e0;
  }
  .tabs {
    display: flex;
    gap: 0;
    margin-left: auto;
  }
  .tab {
    background: transparent;
    border: 1px solid #444;
    color: #888;
    padding: 0.25rem 0.75rem;
    font-family: inherit;
    font-size: 0.75rem;
    cursor: pointer;
    transition: all 0.15s;
  }
  .tab:first-child { border-radius: 4px 0 0 4px; }
  .tab:last-child { border-radius: 0 4px 4px 0; }
  .tab.active {
    background: #2196f3;
    border-color: #2196f3;
    color: #fff;
  }
  .close-btn {
    background: transparent;
    border: none;
    color: #888;
    font-size: 1.4rem;
    cursor: pointer;
    padding: 0 0.25rem;
    line-height: 1;
  }
  .close-btn:hover { color: #f44336; }
  .log-content {
    margin: 0;
    padding: 0.75rem;
    font-size: 0.8rem;
    line-height: 1.5;
    color: #c9d1d9;
    overflow: auto;
    flex: 1;
    white-space: pre-wrap;
    word-break: break-all;
  }
</style>
