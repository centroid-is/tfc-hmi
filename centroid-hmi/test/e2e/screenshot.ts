import { chromium } from '@playwright/test';
import { startPublishing, stopPublishing } from './mqtt-stub';

(async () => {
  await startPublishing();

  const browser = await chromium.launch({
    args: ['--force-renderer-accessibility'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  await page.goto('http://localhost:8088/');

  // Wait for Flutter to load
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60_000 });
  await page.evaluate(`
    (function() {
      var ph = document.querySelector('flt-semantics-placeholder');
      if (ph) ph.click();
    })()
  `);

  // Wait for MQTT data to flow
  await page.waitForTimeout(18_000);

  await page.screenshot({ path: 'screenshot-review.png', fullPage: true });
  console.log('Screenshot saved to screenshot-review.png');

  await browser.close();
  await stopPublishing();
})();
