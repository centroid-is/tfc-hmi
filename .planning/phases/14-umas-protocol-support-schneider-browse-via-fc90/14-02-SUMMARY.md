---
phase: 14-umas-protocol-support-schneider-browse-via-fc90
plan: 02
subsystem: ui
tags: [flutter, widget, browse-panel, protocol-agnostic, adapter-pattern, tdd]

# Dependency graph
requires:
  - phase: 14-01
    provides: UmasClient for FC90 UMAS protocol
provides:
  - Protocol-agnostic BrowsePanel widget with BrowseDataSource interface
  - BrowseNode, BrowseNodeType, BrowseNodeDetail types
  - OpcUaBrowseDataSource adapter for OPC UA ClientApi
  - showBrowseDialog() convenience function
  - NodeId string round-trip parsing (parseNodeId)
affects: [14-03-umas-browse-datasource]

# Tech tracking
tech-stack:
  added: []
  patterns: [adapter-pattern, protocol-agnostic-interface, strategy-pattern]

key-files:
  created:
    - lib/widgets/browse_panel.dart
    - test/widgets/browse_panel_test.dart
  modified:
    - lib/widgets/opcua_browse.dart
    - test/widgets/opcua_browse_test.dart

key-decisions:
  - "BrowseNode.id stores NodeId.toString() for OPC UA -- enables lossless round-trip via parseNodeId"
  - "BrowseTreeEntry (public) replaces private _TreeNode to satisfy dart analyze library_private_types_in_public_api"
  - "formatDynamicValue moved to OpcUaBrowseDataSource as static method (OPC UA specific)"
  - "Breadcrumb root label changed from 'Objects' to 'Root' in generic panel (protocol-neutral)"
  - "Re-export generic types from opcua_browse.dart for backward compatibility"

patterns-established:
  - "BrowseDataSource interface: fetchRoots/fetchChildren/fetchDetail for any protocol"
  - "Adapter pattern: OpcUaBrowseDataSource adapts ClientApi to BrowseDataSource"
  - "BrowseNode.metadata for protocol-specific info (nodeId, browseName, nodeClass)"

requirements-completed: [UMAS-05, UMAS-06, TEST-11]

# Metrics
duration: 8min
completed: 2026-03-07
---

# Phase 14 Plan 02: Protocol-Agnostic Browse Panel Summary

**Extracted 775-line OPC UA browse panel into generic BrowsePanel with BrowseDataSource interface; OPC UA becomes a thin 197-line adapter via OpcUaBrowseDataSource**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-07T20:31:30Z
- **Completed:** 2026-03-07T20:39:43Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created protocol-agnostic BrowsePanel widget (780 lines) with tree view, breadcrumb, detail strip, and action buttons
- Implemented BrowseDataSource interface with fetchRoots(), fetchChildren(), fetchDetail()
- OpcUaBrowseDataSource adapter correctly bridges OPC UA ClientApi to generic interface
- browseOpcUaNode() backward compatible -- key_repository.dart needs zero changes
- 43 total tests passing (16 generic browse panel + 27 OPC UA adapter integration)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create protocol-agnostic BrowsePanel with tests** - `7f7799e` (feat)
2. **Task 2: Create OpcUaBrowseDataSource adapter** - `d58a7f7` (feat)

_Note: Task 1 was TDD -- types and widget created together since tests require the types to compile._

## Files Created/Modified
- `lib/widgets/browse_panel.dart` - Protocol-agnostic BrowseNode, BrowseNodeType, BrowseDataSource, BrowsePanel, BrowseNodeTile, VariableDetailStrip, showBrowseDialog
- `lib/widgets/opcua_browse.dart` - Thin adapter: OpcUaBrowseDataSource, browseOpcUaNode, parseNodeId, formatDynamicValue
- `test/widgets/browse_panel_test.dart` - 16 widget tests using FakeBrowseDataSource
- `test/widgets/opcua_browse_test.dart` - 27 tests: OPC UA integration, parseNodeId, formatDynamicValue

## Decisions Made
- BrowseNode.id stores the NodeId toString() format for OPC UA (ns=X;s=Y or ns=X;i=Y) enabling lossless round-trip parsing
- Renamed _TreeNode to BrowseTreeEntry (public) to satisfy dart analyze library_private_types_in_public_api lint
- Breadcrumb root label is "Root" in generic panel (was "Objects" in OPC UA-specific version) -- protocol-neutral
- opcua_browse.dart re-exports generic types from browse_panel.dart so existing importers work without changes
- formatDynamicValue is OPC UA specific (uses DynamicValue type) so it lives in OpcUaBrowseDataSource, not generic panel

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed dart analyze library_private_types_in_public_api warnings**
- **Found during:** Task 2 (after initial implementation)
- **Issue:** BrowseNodeTile (public) referenced _TreeNode (private) in its constructor
- **Fix:** Renamed _TreeNode to BrowseTreeEntry with @visibleForTesting annotation
- **Files modified:** lib/widgets/browse_panel.dart
- **Verification:** dart analyze shows 0 issues
- **Committed in:** d58a7f7 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor naming adjustment. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BrowseDataSource interface ready for UMAS adapter implementation (Plan 03)
- Plan 03 needs only to implement UmasBrowseDataSource and pass it to showBrowseDialog
- All existing OPC UA browse functionality preserved and tested

---
*Phase: 14-umas-protocol-support-schneider-browse-via-fc90*
*Completed: 2026-03-07*
