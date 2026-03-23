/**
 * Standalone script: starts MQTT broker + publisher + web server,
 * waits for data to flow, takes a screenshot, then keeps running.
 *
 * Usage: npx tsx live-preview.ts
 * Kill with Ctrl-C or `kill <pid>`
 */

import { startPublishing, stopPublishing } from './mqtt-stub';
import { chromium } from 'playwright';
import { execSync, spawn } from 'child_process';

const PORT = 8088;
const SCREENSHOT_PATH = '/tmp/flutter-live-dashboard.png';

async function main() {
  // 1. Start MQTT broker + publisher
  console.log('Starting MQTT broker + synthetic publisher on ws://localhost:9001/mqtt …');
  await startPublishing();
  console.log('MQTT publishing (every 600ms)');

  // 2. Start web server
  console.log(`Serving Flutter build on http://localhost:${PORT} …`);
  const server = spawn('npx', ['serve', '../../build/web', '-l', String(PORT), '--no-clipboard'], {
    stdio: 'ignore',
    detached: false,
  });

  // Give server time to start
  await new Promise(r => setTimeout(r, 2000));

  // 3. Take screenshot after data has flowed
  console.log('Launching browser, waiting 15s for data to accumulate…');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle' });

  // Enable Flutter semantics
  await page.evaluate(`
    (function() {
      var ph = document.querySelector('flt-semantics-placeholder');
      if (ph) ph.click();
    })()
  `);

  // Wait for MQTT data to populate the dashboard
  await page.waitForTimeout(15000);

  await page.screenshot({ path: SCREENSHOT_PATH, fullPage: false });
  console.log(`Screenshot saved to ${SCREENSHOT_PATH}`);

  await browser.close();

  // 4. Keep server + broker alive so user can open browser manually
  console.log(`\nDashboard live at http://localhost:${PORT}`);
  console.log('MQTT data publishing. Press Ctrl-C to stop.');

  process.on('SIGINT', async () => {
    console.log('\nShutting down…');
    await stopPublishing();
    server.kill();
    process.exit(0);
  });

  process.on('SIGTERM', async () => {
    await stopPublishing();
    server.kill();
    process.exit(0);
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
