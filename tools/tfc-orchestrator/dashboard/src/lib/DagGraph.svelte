<script>
  import { dashboardData, statuses, selectedStory } from './stores.js';

  const NODE_W = 120;
  const NODE_H = 40;
  const LAYER_GAP = 160;
  const NODE_GAP = 56;
  const PAD = 20;

  const STATUS_COLORS = {
    passed: '#4caf50',
    failed: '#f44336',
    running: '#2196f3',
    skipped: '#ff9800',
    pending: '#555',
  };

  $: nodes = $dashboardData?.dag?.nodes || [];
  $: edges = $dashboardData?.dag?.edges || [];
  $: st = $statuses;

  $: layout = (() => {
    if (!nodes.length) return { positioned: [], svgW: 0, svgH: 0 };

    const byId = {};
    for (const n of nodes) byId[n.id] = n;

    // Compute layers
    const layerOf = {};
    function getLayer(id) {
      if (layerOf[id] !== undefined) return layerOf[id];
      const node = byId[id];
      if (!node || !node.depends_on || node.depends_on.length === 0) {
        layerOf[id] = 0;
        return 0;
      }
      let maxDep = 0;
      for (const dep of node.depends_on) {
        maxDep = Math.max(maxDep, getLayer(dep));
      }
      layerOf[id] = maxDep + 1;
      return layerOf[id];
    }
    for (const n of nodes) getLayer(n.id);

    // Group by layer
    const layers = {};
    for (const n of nodes) {
      const l = layerOf[n.id];
      if (!layers[l]) layers[l] = [];
      layers[l].push(n);
    }

    const maxLayer = Math.max(...Object.keys(layers).map(Number));
    const maxNodesInLayer = Math.max(...Object.values(layers).map(l => l.length));

    const positioned = [];
    const posMap = {};
    for (let l = 0; l <= maxLayer; l++) {
      const layerNodes = layers[l] || [];
      const layerHeight = layerNodes.length * (NODE_H + NODE_GAP) - NODE_GAP;
      const totalHeight = maxNodesInLayer * (NODE_H + NODE_GAP) - NODE_GAP;
      const offsetY = (totalHeight - layerHeight) / 2;
      for (let i = 0; i < layerNodes.length; i++) {
        const n = layerNodes[i];
        const x = PAD + l * LAYER_GAP;
        const y = PAD + offsetY + i * (NODE_H + NODE_GAP);
        const pos = { ...n, x, y, status: st[n.id] || 'pending' };
        positioned.push(pos);
        posMap[n.id] = pos;
      }
    }

    const svgW = PAD * 2 + (maxLayer + 1) * LAYER_GAP - (LAYER_GAP - NODE_W);
    const svgH = PAD * 2 + maxNodesInLayer * (NODE_H + NODE_GAP) - NODE_GAP;

    return { positioned, posMap, svgW, svgH };
  })();

  $: edgePaths = (() => {
    if (!layout.posMap) return [];
    return edges.map(([from, to]) => {
      const a = layout.posMap[from];
      const b = layout.posMap[to];
      if (!a || !b) return null;
      const x1 = a.x + NODE_W;
      const y1 = a.y + NODE_H / 2;
      const x2 = b.x;
      const y2 = b.y + NODE_H / 2;
      const cx = (x1 + x2) / 2;
      return { from, to, d: `M${x1},${y1} C${cx},${y1} ${cx},${y2} ${x2},${y2}` };
    }).filter(Boolean);
  })();

  function truncName(name, max = 12) {
    if (!name) return '';
    return name.length > max ? name.slice(0, max) + '...' : name;
  }

  function handleClick(id) {
    selectedStory.update(v => v === id ? null : id);
  }
</script>

<div class="dag-container">
  {#if layout.svgW > 0}
    <svg viewBox="0 0 {layout.svgW} {layout.svgH}" class="dag-svg">
      <defs>
        <marker id="arrow" viewBox="0 0 10 7" refX="10" refY="3.5"
                markerWidth="8" markerHeight="6" orient="auto-start-reverse">
          <path d="M0,0 L10,3.5 L0,7 Z" fill="#666" />
        </marker>
      </defs>

      {#each edgePaths as edge}
        <path d={edge.d} fill="none" stroke="#666" stroke-width="1.5"
              marker-end="url(#arrow)" />
      {/each}

      {#each layout.positioned as node}
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <!-- svelte-ignore a11y-no-static-element-interactions -->
        <g class="node" class:node-running={node.status === 'running'}
           on:click={() => handleClick(node.id)}
           style="cursor: pointer;">
          <rect x={node.x} y={node.y} width={NODE_W} height={NODE_H}
                rx="6" ry="6"
                fill={STATUS_COLORS[node.status] || STATUS_COLORS.pending}
                stroke={$selectedStory === node.id ? '#fff' : 'none'}
                stroke-width="2"
                opacity="0.9" />
          <text x={node.x + NODE_W / 2} y={node.y + 15}
                text-anchor="middle" fill="#fff" font-size="11" font-weight="700">
            #{node.id}
          </text>
          <text x={node.x + NODE_W / 2} y={node.y + 30}
                text-anchor="middle" fill="#ddd" font-size="9">
            {truncName(node.name)}
          </text>
        </g>
      {/each}
    </svg>
  {:else}
    <div class="dag-empty">No DAG data</div>
  {/if}
</div>

<style>
  .dag-container {
    background: #16213e;
    border-radius: 8px;
    padding: 0.75rem;
    overflow-x: auto;
  }
  .dag-svg {
    width: 100%;
    height: auto;
    display: block;
  }
  .node:hover rect {
    opacity: 1;
    stroke: #fff;
    stroke-width: 2;
  }
  .node-running rect {
    animation: node-pulse 2s ease-in-out infinite;
  }
  .dag-empty {
    color: #666;
    text-align: center;
    padding: 2rem;
  }
  @keyframes node-pulse {
    0%, 100% { opacity: 0.9; }
    50% { opacity: 0.5; }
  }
</style>
