/**
 * In-process MQTT broker + synthetic data publisher.
 *
 * Uses `aedes` (in-memory MQTT broker) with a WebSocket listener on port 9001
 * so the Flutter web app can connect via ws://localhost:9001/mqtt.
 *
 * No Docker / external Mosquitto required — keeps the feedback loop fast.
 */

import Aedes from 'aedes';
import { createServer as createHttpServer, type Server } from 'http';
import { WebSocketServer, createWebSocketStream } from 'ws';

const CLASSES = [
  'cat', 'dog', 'car', 'person', 'bird',
  'bicycle', 'traffic light', 'truck', 'airplane', 'laptop',
];

// Tiny 1x1 red PNG pixel as base64
const TINY_IMAGE =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

let aedesInstance: InstanceType<typeof Aedes> | null = null;
let httpServer: Server | null = null;
let publishTimer: ReturnType<typeof setInterval> | null = null;
let paused = false;
let total = 0;
let errors = 0;
let confidences: number[] = [];
let latencies: number[] = [];

function rnd(a: number, b: number): number {
  return Math.random() * (b - a) + a;
}
function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/** Publish a message through the in-process broker. */
function brokerPublish(topic: string, payload: string): void {
  aedesInstance?.publish(
    {
      topic,
      payload: Buffer.from(payload),
      cmd: 'publish',
      qos: 0 as const,
      dup: false,
      retain: false,
    },
    () => {},
  );
}

/**
 * Start the in-process MQTT broker on WebSocket port 9001 and begin
 * publishing synthetic inference data every 600 ms.
 */
export async function startPublishing(): Promise<void> {
  // --- broker ---
  aedesInstance = new Aedes();

  httpServer = createHttpServer();
  const wss = new WebSocketServer({ server: httpServer, path: '/mqtt' });

  wss.on('connection', (ws) => {
    const stream = createWebSocketStream(ws);
    aedesInstance!.handle(stream as any);
  });

  await new Promise<void>((resolve, reject) => {
    httpServer!.on('error', reject);
    httpServer!.listen(9001, resolve);
  });

  // --- listen for pause control from Flutter UI ---
  aedesInstance.on('publish', (packet) => {
    if (packet.topic === 'inference/control/pause') {
      const val = packet.payload.toString();
      paused = val === 'true' || val === '1';
    }
  });

  // --- publisher loop ---
  publishTimer = setInterval(() => {
    if (paused) return;

    const label = pick(CLASSES);
    const isErr = Math.random() < 0.04;
    const confidence = isErr ? rnd(0.05, 0.3) : rnd(0.55, 0.99);
    const latency_ms = isErr ? rnd(200, 600) : rnd(18, 95);

    total++;
    if (isErr) errors++;
    confidences.push(confidence);
    if (confidences.length > 100) confidences.shift();
    latencies.push(latency_ms);
    if (latencies.length > 100) latencies.shift();

    brokerPublish(
      'inference/result',
      JSON.stringify({
        image: TINY_IMAGE,
        label,
        confidence: parseFloat(confidence.toFixed(3)),
        latency_ms: parseFloat(latency_ms.toFixed(1)),
      }),
    );

    const avgConf =
      confidences.reduce((a, b) => a + b, 0) / confidences.length;
    const avgLat =
      latencies.reduce((a, b) => a + b, 0) / latencies.length;

    brokerPublish('inference/stats/processed', JSON.stringify(total));
    brokerPublish(
      'inference/stats/avg_confidence',
      JSON.stringify(parseFloat((avgConf * 100).toFixed(2))),
    );
    brokerPublish(
      'inference/stats/latency_ms',
      JSON.stringify(parseFloat(avgLat.toFixed(1))),
    );
    brokerPublish('inference/stats/errors', JSON.stringify(errors));
  }, 600);
}

/** Publish to the control topic to pause/resume the stub. */
export function setPaused(value: boolean): void {
  brokerPublish('inference/control/pause', String(value));
  paused = value;
}

/** Stop everything and release ports. */
export async function stopPublishing(): Promise<void> {
  if (publishTimer) {
    clearInterval(publishTimer);
    publishTimer = null;
  }
  if (httpServer) {
    await new Promise<void>((r) => httpServer!.close(() => r()));
    httpServer = null;
  }
  if (aedesInstance) {
    aedesInstance.close();
    aedesInstance = null;
  }
  total = 0;
  errors = 0;
  confidences = [];
  latencies = [];
  paused = false;
}
