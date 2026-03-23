/**
 * MQTT stub publisher for E2E tests.
 *
 * Connects to Mosquitto on localhost:1883 and publishes synthetic inference
 * data that the Flutter web app subscribes to via WebSocket on port 9001.
 *
 * Usage:
 *   npx tsx mqtt-stub.ts          # standalone mode (publishes until Ctrl-C)
 *   import { start, stop } from './mqtt-stub'  # programmatic from tests
 */

import mqtt from 'mqtt';

const BROKER_URL = 'mqtt://localhost:1883';

const CLASSES = [
  'cat', 'dog', 'car', 'person', 'bird',
  'truck', 'bicycle', 'horse', 'sheep', 'bottle',
];

// Generate a small coloured PNG-like base64 string.
// Real images are not needed — Flutter's Image.memory will show a broken icon
// but the entry still appears in the feed, which is what the test verifies.
function makeColoredSquare(): string {
  // 1x1 pixel PNG in various colours (pre-generated, valid PNGs)
  const pixels: string[] = [
    // Red 1x1 PNG
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
    // Green 1x1 PNG
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    // Blue 1x1 PNG
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBwIAMCbHYQAAAABJRU5ErkJggg==',
  ];
  return pixels[Math.floor(Math.random() * pixels.length)];
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let client: mqtt.MqttClient | null = null;
let interval: ReturnType<typeof setInterval> | null = null;
let paused = false;
let totalProcessed = 0;
let totalConfidence = 0;
let totalLatency = 0;
let errorCount = 0;

// ---------------------------------------------------------------------------
// Publishing logic
// ---------------------------------------------------------------------------

function publishTick() {
  if (!client || paused) return;

  const label = CLASSES[Math.floor(Math.random() * CLASSES.length)];
  const confidence = 0.5 + Math.random() * 0.5; // 0.50 – 1.00
  const latencyMs = Math.floor(20 + Math.random() * 80); // 20 – 100 ms
  const image = makeColoredSquare();

  totalProcessed++;
  totalConfidence += confidence;
  totalLatency += latencyMs;

  const result = JSON.stringify({
    image,
    label,
    confidence: Math.round(confidence * 100) / 100,
    latency_ms: latencyMs,
    id: totalProcessed,
  });

  client.publish('inference/result', result, { qos: 0 });
  client.publish('inference/stats/processed', JSON.stringify(totalProcessed), { qos: 0 });
  client.publish(
    'inference/stats/avg_confidence',
    JSON.stringify(Math.round((totalConfidence / totalProcessed) * 100) / 100),
    { qos: 0 },
  );
  client.publish(
    'inference/stats/latency_ms',
    JSON.stringify(Math.round(totalLatency / totalProcessed)),
    { qos: 0 },
  );
  client.publish('inference/stats/errors', JSON.stringify(errorCount), { qos: 0 });
}

// ---------------------------------------------------------------------------
// Public API (programmatic control from Playwright tests)
// ---------------------------------------------------------------------------

export async function startPublishing(): Promise<void> {
  if (client) return; // Already running

  // Reset stats
  totalProcessed = 0;
  totalConfidence = 0;
  totalLatency = 0;
  errorCount = 0;
  paused = false;

  return new Promise<void>((resolve, reject) => {
    client = mqtt.connect(BROKER_URL, { clientId: `e2e-stub-${Date.now()}` });

    client.on('connect', () => {
      // Subscribe to control topic so tests can pause/resume via MQTT
      client!.subscribe('inference/control/pause', { qos: 1 });

      // Start publishing every 600ms
      interval = setInterval(publishTick, 600);
      resolve();
    });

    client.on('message', (topic: string, payload: Buffer) => {
      if (topic === 'inference/control/pause') {
        const val = payload.toString().trim();
        // "true" or "1" means pause requested
        paused = val === 'true' || val === '1';
      }
    });

    client.on('error', (err: Error) => {
      reject(err);
    });
  });
}

export function stopPublishing(): void {
  if (interval) {
    clearInterval(interval);
    interval = null;
  }
  if (client) {
    client.end(true);
    client = null;
  }
  paused = false;
}

// ---------------------------------------------------------------------------
// Standalone mode (run directly with `npx tsx mqtt-stub.ts`)
// ---------------------------------------------------------------------------

const isMain = process.argv[1]?.endsWith('mqtt-stub.ts') ||
               process.argv[1]?.endsWith('mqtt-stub');

if (isMain) {
  console.log('Starting MQTT stub publisher (standalone mode)...');
  startPublishing()
    .then(() => console.log('Connected to broker, publishing every 600ms'))
    .catch((err) => {
      console.error('Failed to connect:', err);
      process.exit(1);
    });

  process.on('SIGINT', () => {
    console.log('\nStopping...');
    stopPublishing();
    process.exit(0);
  });
}
