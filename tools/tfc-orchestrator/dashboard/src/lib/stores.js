import { writable, derived } from 'svelte/store';

// All plans summary (from /api/plans)
export const planList = writable([]);

// Currently selected plan name
export const activePlan = writable(null);

// Full state for the active plan
export const dashboardData = writable(null);

// Selected story ID for log viewer
export const selectedStory = writable(null);

// Derived (unchanged — still derive from dashboardData)
export const stories = derived(dashboardData, $d => $d?.dag?.nodes || []);
export const statuses = derived(dashboardData, $d => $d?.statuses || {});
export const planInfo = derived(dashboardData, $d => $d?.plan || null);
