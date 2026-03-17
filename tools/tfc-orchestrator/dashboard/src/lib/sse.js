import { dashboardData } from './stores.js';

let eventSource = null;

export function connectSSE() {
  // Initial fetch
  fetch('/api/state')
    .then(r => r.json())
    .then(data => dashboardData.set(data));

  // SSE stream
  eventSource = new EventSource('/api/events');
  eventSource.onmessage = (event) => {
    const data = JSON.parse(event.data);
    dashboardData.update(current => ({
      ...current,
      ...data,
    }));
  };
  eventSource.onerror = () => {
    // Auto-reconnect is built into EventSource
    console.warn('SSE connection lost, reconnecting...');
  };
}

export function disconnectSSE() {
  if (eventSource) eventSource.close();
}
