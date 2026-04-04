import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.ts',
  timeout: 30_000,
  expect: {
    timeout: 10_000,
  },
  use: {
    baseURL: 'http://localhost:8080',
    // Flutter HTML renderer produces real DOM elements
    // that Playwright can query with standard selectors.
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' },
    },
  ],
  webServer: {
    command: 'python3 -m http.server 8080 -d ../../build/web',
    port: 8080,
    reuseExistingServer: true,
    timeout: 10_000,
  },
});
