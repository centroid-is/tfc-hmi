import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.ts',
  timeout: 120_000,
  expect: { timeout: 30_000 },
  retries: 1,
  workers: 1,
  use: {
    baseURL: 'http://localhost:8088',
    viewport: { width: 1280, height: 720 },
    launchOptions: {
      args: ['--force-renderer-accessibility'],
    },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'npx serve ../../build/web -l 8088 --no-clipboard',
    port: 8088,
    reuseExistingServer: !process.env.CI,
    timeout: 15_000,
  },
});
