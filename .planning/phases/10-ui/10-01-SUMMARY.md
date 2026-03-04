---
phase: 10-ui
plan: 01
subsystem: server-config-ui
tags: [flutter, ui, m2400, server-config, jbtm]
dependency_graph:
  requires: [phase-9-config-models]
  provides: [jbtm-server-config-ui]
  affects: [lib/pages/server_config.dart]
tech_stack:
  added: []
  patterns: [ConsumerStatefulWidget, LayoutBuilder-responsive, JSON-comparison-unsaved-changes]
key_files:
  created: []
  modified:
    - lib/pages/server_config.dart
decisions:
  - Used scaleBalanced icon for JBTM section (weighing device context)
  - Followed identical patterns to _OpcUAServersSection for consistency
  - Simpler card than OPC UA (no SSL certs, username/password fields)
metrics:
  duration: ~3 minutes
  completed: 2026-03-04
---

# Phase 10 Plan 01: JBTM Server Config Section Summary

JBTM M2400 server configuration section added to server config page with add/edit/remove cards, responsive layout, and save/load via StateManConfig.

## What Was Done

### Task 1: Add _JbtmServersSection to server config page

Added three new widgets to `lib/pages/server_config.dart`:

1. **_JbtmServersSection** (ConsumerStatefulWidget): Manages JBTM/M2400 server configuration. Follows the exact same pattern as `_OpcUAServersSection`:
   - Loads `StateManConfig` from preferences in `initState`
   - Tracks `_config`, `_savedConfig`, `_isLoading`, `_error` state
   - `_addServer()` appends M2400Config with defaults (host: 'localhost', port: 52211)
   - `_updateServer(index, server)` and `_removeServer(index)` for editing/deleting
   - `_saveConfig()` writes to preferences, invalidates stateManProvider, shows SnackBar
   - `_hasUnsavedChanges` via JSON comparison (same pattern as OPC UA)
   - Header with scaleBalanced icon, title, unsaved badge, Add Server button
   - Responsive narrow/wide layout via LayoutBuilder
   - Save button shows only when changes are unsaved

2. **_EmptyJbtmServersWidget**: Empty state with scale icon and "No JBTM servers configured" text.

3. **_JbtmServerConfigCard** (StatefulWidget): ExpansionTile card for each M2400 server entry:
   - Host TextField (default 'localhost')
   - Port TextField with number keyboard (default 52211)
   - Server Alias TextField (optional)
   - Responsive host+port row layout (LayoutBuilder, narrow=column, wide=row with 3:1 flex)
   - Delete button with confirmation dialog
   - Title shows alias (or host:port fallback), subtitle shows host:port

## Deviations from Plan

None - plan executed exactly as written.

## Verification

- `dart analyze lib/pages/server_config.dart` -- No issues found
- Server config page renders both OPC UA and JBTM sections in its Column
- JBTM section has independent add/save/delete controls

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 98b7e1d | feat(10-01): add JBTM M2400 Servers section to server configuration page |
