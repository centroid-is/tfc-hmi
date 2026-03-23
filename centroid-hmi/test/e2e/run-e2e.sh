#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 1. Build Flutter web
echo "==> Building Flutter web..."
cd "$APP_ROOT" && flutter build web

# 2. Copy config
echo "==> Copying config..."
cp -r "$APP_ROOT/web/config" "$APP_ROOT/build/web/config"

# 3. Install playwright
echo "==> Installing Playwright..."
cd "$SCRIPT_DIR" && npm install && npx playwright install chromium

# 4. Run tests (in-process MQTT broker, no Docker needed)
echo "==> Running E2E tests..."
set +e; npm test; TEST_EXIT=$?; set -e

exit $TEST_EXIT
