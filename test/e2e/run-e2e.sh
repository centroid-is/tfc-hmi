#!/bin/bash
# ---------------------------------------------------------------------------
# E2E test orchestrator for the Flutter web inference dashboard.
#
# Steps:
#   1. Start Mosquitto broker (via docker compose)
#   2. Build Flutter web app (HTML renderer — NOT CanvasKit)
#   3. Copy static config into the build output
#   4. Install Playwright + deps
#   5. Run Playwright tests
#   6. Cleanup (stop Mosquitto)
#
# Usage:
#   ./test/e2e/run-e2e.sh          # from repo root
#   cd test/e2e && ./run-e2e.sh    # from test/e2e/
# ---------------------------------------------------------------------------

set -e

# Resolve repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Ensure Mosquitto is stopped on exit (even if set -e triggers an early abort).
trap 'echo "=== Stopping Mosquitto (cleanup) ===" && cd "$REPO_ROOT/packages/tfc_dart/test/integration" && docker compose down' EXIT

echo "=== Repo root: $REPO_ROOT ==="

# 1. Start Mosquitto (and TimescaleDB, though E2E tests don't need it)
echo "=== Starting Mosquitto broker ==="
cd "$REPO_ROOT/packages/tfc_dart/test/integration"
docker compose up -d mosquitto
# Give Mosquitto a moment to start accepting connections.
sleep 2

# 2. Build Flutter web (HTML renderer — produces real DOM elements)
echo "=== Building Flutter web (HTML renderer) ==="
cd "$REPO_ROOT"
flutter build web

# 3. Copy static config files into the build output.
# The web app fetches these via HTTP at runtime.
echo "=== Copying config files ==="
cp -r "$REPO_ROOT/web/config" "$REPO_ROOT/build/web/config"

# 4. Install Playwright and npm deps
echo "=== Installing Playwright deps ==="
cd "$SCRIPT_DIR"
npm install
npx playwright install chromium

# 5. Run Playwright tests
echo "=== Running Playwright E2E tests ==="
set +e
npm test
TEST_EXIT=$?
set -e

# 6. Cleanup is handled by the EXIT trap (docker compose down).
exit $TEST_EXIT
