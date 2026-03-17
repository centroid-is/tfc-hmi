import { planList, activePlan, dashboardData } from './stores.js';

let eventSource = null;
let currentPlan = null;

export async function fetchPlans() {
  try {
    const res = await fetch('/api/plans');
    if (!res.ok) return;
    const plans = await res.json();
    planList.set(plans);
    // Auto-select first plan if none selected
    activePlan.update(current => current || (plans.length > 0 ? plans[0].name : null));
  } catch (e) {
    console.warn('Failed to fetch plans:', e);
  }
}

export function connectPlan(planName) {
  if (eventSource) {
    eventSource.close();
    eventSource = null;
  }
  currentPlan = planName;
  if (!planName) {
    dashboardData.set(null);
    return;
  }

  fetch(`/api/${planName}/state`)
    .then(r => r.json())
    .then(data => {
      if (currentPlan === planName) dashboardData.set(data);
    })
    .catch(() => dashboardData.set(null));

  eventSource = new EventSource(`/api/${planName}/events`);
  eventSource.onmessage = (event) => {
    if (currentPlan !== planName) return;
    try {
      const data = JSON.parse(event.data);
      dashboardData.update(current => ({ ...current, ...data }));
    } catch (e) {
      console.warn('SSE parse error:', e);
    }
  };
}

export function disconnect() {
  if (eventSource) eventSource.close();
  eventSource = null;
  currentPlan = null;
}
