# UAT Report: Config + Integration Tests (Stories 4-5)

**Plan:** mqtt-web
**Phase:** 2 — Config + Integration Tests
**Date:** 2026-03-17 (final re-verification)
**Branch:** mqtt
**Verdict:** PASS

---

## Summary

Stories 4 and 5 are complete. All files exist, all unit tests pass (473 total, 0 failures), static analysis is clean. All 3 minor gaps from the prior UAT (G1–G3) have been resolved.

---

## Story 4: Mosquitto Dart test helpers + integration tests — PASS

### Files Delivered
| File | Status |
|------|--------|
| `packages/tfc_dart/test/integration/mosquitto.conf` | PASS |
| `packages/tfc_dart/test/integration/mosquitto_helpers.dart` | PASS |
| `packages/tfc_dart/test/integration/mqtt_integration_test.dart` | PASS |
| `packages/tfc_dart/test/integration/docker-compose.yml` (modified) | PASS |

### Acceptance Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `mosquitto.conf`: listener 1883, listener 9001 WS, allow_anonymous true | PASS |
| 2 | docker-compose.yml: mosquitto service (eclipse-mosquitto:2, ports 1883+9001, volume) | PASS |
| 3 | `mosquitto_helpers.dart`: startMosquitto/stopMosquitto/waitForMosquittoReady | PASS |
| 4 | `MOSQUITTO_EXTERNAL=1` env var support (skip Docker lifecycle) | PASS |
| 5 | Tests tagged `@Tags(['integration'])` with `@Timeout(60s)` | PASS |
| 6 | Test: TCP connect localhost:1883, verify connected status | PASS |
| 7 | Test: Subscribe + publish JSON payload, verify DynamicValue received | PASS |
| 8 | Test: Write DynamicValue, verify via second client | PASS |
| 9 | Test: Disconnect/reconnect status verification | PASS |
| 10 | Test: WebSocket connect ws://localhost:9001/mqtt | PASS |
| 11 | Test: Multiple keys on different topics, independent streams | PASS |
| 12 | setUpAll starts mosquitto, tearDownAll stops it | PASS |
| 13 | 10-second timeouts on async operations | PASS |
| 14 | `dart test --exclude-tags=integration` — existing tests still pass | PASS |

**Commit:** `7108362 feat(mqtt): Story 4 — Mosquitto Dart test helpers + integration tests`

---

## Story 5: Static config loading — fromString + ConfigSource — PASS

### Files Delivered
| File | Status |
|------|--------|
| `packages/tfc_dart/lib/core/config_source.dart` | PASS |
| `packages/tfc_dart/lib/core/config_source_native.dart` | PASS |
| `packages/tfc_dart/test/core/config_source_test.dart` | PASS |
| `packages/tfc_dart/lib/core/state_man.dart` (modified) | PASS |

### Acceptance Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `StateManConfig.fromString(jsonString)` convenience method | PASS |
| 2 | `KeyMappings.fromString(jsonString)` static method | PASS |
| 3 | `KeyMappings.fromFile(path)` following `StateManConfig.fromFile` pattern | PASS |
| 4 | `StaticConfig` class with stateManConfig, keyMappings, pageEditorJson | PASS |
| 5 | `StaticConfig.fromStrings()` factory (platform-agnostic) | PASS |
| 6 | `staticConfigFromDirectory()` loads 3 files from directory | PASS |
| 7 | `staticConfigFromDirectory()` handles optional page-editor.json | PASS |
| 8 | `config_source.dart` is dart:io-free (web-safe) | PASS |
| 9 | Test: `StateManConfig.fromString` parses JSON with mqtt config | PASS |
| 10 | Test: `KeyMappings.fromString` parses JSON with mqtt_node entries | PASS |
| 11 | Test: `KeyMappings.fromFile` reads from temp file | PASS |
| 12 | Test: `KeyMappings.fromFile` throws on missing file | PASS |
| 13 | Test: `StaticConfig.fromStrings` creates valid config | PASS |
| 14 | Test: `staticConfigFromDirectory` loads all 3 files | PASS |
| 15 | Test: `staticConfigFromDirectory` works when page-editor.json missing | PASS |
| 16 | Test: `stateManConfig.mqtt` populated correctly | PASS |
| 17 | Test: `keyMappings.nodes` contains expected mqtt entries | PASS |
| 18 | REFACTOR: consistent error handling across fromFile/fromString | PASS |
| 19 | `dart test` — all tests pass | PASS |
| 20 | `dart analyze --fatal-infos` — no issues | PASS |

### Intentional Deviation (Acceptable)
- `StaticConfig.fromDirectory` → top-level `staticConfigFromDirectory()` function in `config_source_native.dart` to keep `dart:io` out of `config_source.dart` (web-safe split). Correct architectural decision.

**Commit:** `f4c57ed feat(mqtt): Story 5 — Static config loading — fromString + ConfigSource`

---

## Prior Gaps — All Resolved

| # | Gap (from prior UAT) | Resolution |
|---|----------------------|------------|
| G1 | `KeyMappings.fromFile` lacked FormatException wrapping | Fixed: `state_man.dart:622-627` now catches `FormatException` and re-throws with file path context, consistent with `StateManConfig.fromFile` |
| G2 | No error-handling tests for `fromString` with malformed JSON | Fixed: `config_source_test.dart` lines 112-142 — 4 tests for malformed JSON (2 per fromString method) |
| G3 | No `fromDirectory` test for missing required files | Fixed: `config_source_test.dart` lines 381-421 — tests for missing config.json and missing keymappings.json |

---

## Validation Results

| Check | Result |
|-------|--------|
| `dart run build_runner build` | OK — 111 outputs, no errors |
| `dart analyze --fatal-infos` | No issues found |
| `dart test --exclude-tags=integration` | **473 passed**, 18 skipped, 0 failures |
| Config source tests (`config_source_test.dart`) | **19/19 passed** |
| MQTT unit tests (config + device_client + routing) | **60/60 passed** |

---

## Gaps Found

**None.** All acceptance criteria for Stories 4 and 5 are fully met. All prior gaps resolved.
