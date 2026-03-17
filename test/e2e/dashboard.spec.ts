/**
 * Playwright E2E tests for the Flutter web inference dashboard.
 *
 * These tests validate the full stack: Flutter web app ↔ MQTT (WebSocket) ↔
 * Mosquitto broker ↔ MQTT stub publisher.
 *
 * IMPORTANT: The Flutter web build must use `--web-renderer html` so that
 * Playwright can query real DOM elements. CanvasKit renders to <canvas>.
 */

import { test, expect, type Page } from '@playwright/test';
import { startPublishing, stopPublishing } from './mqtt-stub';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Wait for the Flutter app to finish initialising.
 *
 * The HTML renderer emits real DOM elements. We wait for the main content
 * to appear by looking for text rendered by the Flutter app.
 * Flutter's HTML renderer creates actual DOM text nodes that Playwright
 * can find with text selectors.
 */
async function waitForFlutterReady(page: Page): Promise<void> {
  // Flutter web apps show a loading indicator, then render the app.
  // Wait for any meaningful text from the app's menu/scaffold to appear.
  // The app title is "CentroidX" set in MaterialApp.
  // We also accept any menu item text as proof the app has loaded.
  await page.waitForFunction(
    () => {
      // Flutter HTML renderer: look for rendered text in the body.
      const body = document.body.innerText;
      return (
        body.includes('Home') ||
        body.includes('Inference Monitor') ||
        body.includes('CentroidX')
      );
    },
    { timeout: 20_000 },
  );
}

// ---------------------------------------------------------------------------
// Test 1: App loads and renders dashboard
// ---------------------------------------------------------------------------

test.describe('Inference Dashboard E2E', () => {
  test.afterEach(() => {
    stopPublishing();
  });

  test('Test 1: App loads and renders dashboard', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);

    // The "Inference Monitor" page should appear in the navigation menu
    // (it is a dynamic page loaded from page-editor.json).
    const body = page.locator('body');
    await expect(body).toContainText('Inference Monitor', { timeout: 15_000 });

    // Verify 4 metric card labels are present.
    // NumberConfig assets render their label text ("Processed", "Avg Confidence", etc.)
    // as BaseAsset text overlays.
    await expect(body).toContainText('Processed');
    await expect(body).toContainText('Avg Confidence');
    await expect(body).toContainText('Latency');
    await expect(body).toContainText('Errors');
  });

  // ---------------------------------------------------------------------------
  // Test 2: MQTT data updates metric cards
  // ---------------------------------------------------------------------------

  test('Test 2: MQTT data updates metric cards', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);

    // Navigate to Inference Monitor
    const inferenceLink = page.getByText('Inference Monitor');
    await expect(inferenceLink).toBeVisible({ timeout: 15_000 });
    await inferenceLink.click();

    // Start the MQTT stub publisher
    await startPublishing();

    // Wait for data to flow (3 seconds at 600ms interval = ~5 messages)
    await page.waitForTimeout(3_000);

    const bodyText = await page.locator('body').innerText();

    // "Processed" metric should show a number > 0
    // Extract lines near "Processed" and look for a positive integer
    const processedMatch = bodyText.match(/Processed[\s\S]{0,50}?(\d+)/);
    expect(processedMatch).not.toBeNull();
    expect(Number(processedMatch![1])).toBeGreaterThan(0);

    // "Avg Confidence" metric should show a percentage (e.g. "75%") or decimal
    const confidenceMatch = bodyText.match(/Avg Confidence[\s\S]{0,50}?(\d+\.?\d*)\s*%?/);
    expect(confidenceMatch).not.toBeNull();
    expect(Number(confidenceMatch![1])).toBeGreaterThan(0);

    // "Latency" metric should show a number
    const latencyMatch = bodyText.match(/Latency[\s\S]{0,50}?(\d+)/);
    expect(latencyMatch).not.toBeNull();
    expect(Number(latencyMatch![1])).toBeGreaterThan(0);

    stopPublishing();
  });

  // ---------------------------------------------------------------------------
  // Test 3: Image feed shows images
  // ---------------------------------------------------------------------------

  test('Test 3: Image feed shows images', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);

    // Navigate to the inference monitor page
    const inferenceLink = page.getByText('Inference Monitor');
    await expect(inferenceLink).toBeVisible({ timeout: 15_000 });
    await inferenceLink.click();

    await startPublishing();

    // Wait long enough for > 9 messages to exceed maxImages cap
    // (9 * 600ms = 5.4s + buffer)
    await page.waitForTimeout(7_000);

    const bodyText = await page.locator('body').innerText();

    // At least one class label should be visible in the image grid
    const hasClassLabel = [
      'cat', 'dog', 'car', 'person', 'bird',
      'truck', 'bicycle', 'horse', 'sheep', 'bottle',
    ].some((cls) => bodyText.includes(cls));
    expect(hasClassLabel).toBe(true);

    // Confidence percentages should be visible (e.g. "92%", "78%")
    expect(bodyText).toMatch(/\d+%/);

    // Verify image elements are rendered (Flutter HTML renderer outputs
    // Image.memory as <img> tags).
    const imageCount = await page.locator('img').count();
    expect(imageCount).toBeGreaterThanOrEqual(3);

    // Verify grid image count <= maxImages (9) by scoping to the
    // image-feed-grid Semantics container. Flutter HTML renderer emits
    // aria-label attributes from Semantics widgets.
    const gridImages = await page
      .locator('[aria-label="image-feed-grid"] img')
      .count();
    expect(gridImages).toBeLessThanOrEqual(9);

    stopPublishing();
  });

  // ---------------------------------------------------------------------------
  // Test 4: Inference log shows entries
  // ---------------------------------------------------------------------------

  test('Test 4: Inference log shows entries', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);

    const inferenceLink = page.getByText('Inference Monitor');
    await expect(inferenceLink).toBeVisible({ timeout: 15_000 });
    await inferenceLink.click();

    await startPublishing();

    // Wait for at least 5 log entries (5 * 600ms + buffer)
    await page.waitForTimeout(4_000);

    const bodyText = await page.locator('body').innerText();

    // InferenceLogConfig renders class labels in bold text
    const hasClassLabel = [
      'cat', 'dog', 'car', 'person', 'bird',
      'truck', 'bicycle', 'horse', 'sheep', 'bottle',
    ].some((cls) => bodyText.includes(cls));
    expect(hasClassLabel).toBe(true);

    // Each log entry has a status badge ("ok", "low", or "error")
    const hasStatusBadge =
      bodyText.includes('ok') ||
      bodyText.includes('low') ||
      bodyText.includes('error');
    expect(hasStatusBadge).toBe(true);

    // Confidence bars show percentages
    expect(bodyText).toMatch(/\d+%/);

    // Latency values are shown (e.g., "45ms")
    expect(bodyText).toMatch(/\d+ms/);

    // Verify newest entry is at the top: the log shows "#N" IDs from the
    // MQTT stub's monotonically increasing totalProcessed counter.
    // Entries are inserted at index 0 (newest first), so IDs should appear
    // in descending order in the page text.
    const ids = [...bodyText.matchAll(/#(\d+)/g)].map((m) => Number(m[1]));
    expect(ids.length).toBeGreaterThanOrEqual(2);
    // First visible ID should be >= second visible ID (descending order)
    for (let i = 0; i < ids.length - 1; i++) {
      expect(ids[i]).toBeGreaterThanOrEqual(ids[i + 1]);
    }

    stopPublishing();
  });

  // ---------------------------------------------------------------------------
  // Test 5: Pause button stops the feed
  // ---------------------------------------------------------------------------

  test('Test 5: Pause button stops the feed', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);

    const inferenceLink = page.getByText('Inference Monitor');
    await expect(inferenceLink).toBeVisible({ timeout: 15_000 });
    await inferenceLink.click();

    await startPublishing();

    // Wait for initial data to appear
    await page.waitForTimeout(2_000);

    // Click the "Pause Feed" toggle button
    const pauseButton = page.getByText('Pause Feed');
    await expect(pauseButton).toBeVisible({ timeout: 5_000 });
    await pauseButton.click();

    // Record current state: count class labels visible
    await page.waitForTimeout(500); // Let the pause propagate
    const textBeforePause = await page.locator('body').innerText();
    const countBefore = (textBeforePause.match(/\d+%/g) || []).length;

    // Wait 3 seconds — feed should be paused, count should not increase
    await page.waitForTimeout(3_000);
    const textDuringPause = await page.locator('body').innerText();
    const countDuring = (textDuringPause.match(/\d+%/g) || []).length;

    // Paused: the confidence percentage count should NOT have increased
    // (or increased very minimally due to existing buffered messages)
    expect(countDuring).toBeLessThanOrEqual(countBefore + 1);

    // The "PAUSED" overlay text should be visible
    expect(textDuringPause).toContain('PAUSED');

    // Click pause button again to resume
    await pauseButton.click();

    // Wait for new data
    await page.waitForTimeout(2_000);
    const textAfterResume = await page.locator('body').innerText();
    const countAfter = (textAfterResume.match(/\d+%/g) || []).length;

    // Resumed: count should have increased
    expect(countAfter).toBeGreaterThan(countDuring);

    stopPublishing();
  });

  // ---------------------------------------------------------------------------
  // Test 6: Config pages are hidden on web
  // ---------------------------------------------------------------------------

  test('Test 6: Config pages are hidden on web', async ({ page }) => {
    await page.goto('/');
    await waitForFlutterReady(page);

    const bodyText = await page.locator('body').innerText();

    // In static mode (web), these config pages should NOT appear in the menu:
    // Server Config, Key Repository, and Page Editor are hidden when isStaticMode
    expect(bodyText).not.toContain('Server Config');
    expect(bodyText).not.toContain('Key Repository');
    // Page Editor is also gated behind environmentVariableIsGod (TFC_GOD=true),
    // which is never set on web, so it should not appear.
    expect(bodyText).not.toContain('Page Editor');

    // But standard pages should still be visible
    expect(bodyText).toContain('Home');
    expect(bodyText).toContain('Alarm View');
  });
});
