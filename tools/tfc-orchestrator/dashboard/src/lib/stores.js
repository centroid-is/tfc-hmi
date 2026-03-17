import { writable, derived } from 'svelte/store';

export const dashboardData = writable(null);  // full /api/state response
export const selectedStory = writable(null);   // story ID for log viewer

export const stories = derived(dashboardData, $d => {
  if (!$d) return [];
  return $d.dag?.nodes || [];
});

export const statuses = derived(dashboardData, $d => {
  if (!$d) return {};
  return $d.statuses || {};
});

export const planInfo = derived(dashboardData, $d => {
  if (!$d) return null;
  return $d.plan || null;
});
