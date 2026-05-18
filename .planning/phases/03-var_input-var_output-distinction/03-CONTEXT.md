# Phase 3: VAR_INPUT / VAR_OUTPUT distinction - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

For every function-block (FB) instance that Phase 2 surfaces in the variable tree, each member must carry a structural classification of its declaration direction: `VAR_INPUT`, `VAR_OUTPUT`, public `VAR`, `VAR_IN_OUT`, or `unknown`. This is a **data-layer** concern — the field exists on the per-member record (and propagates to `UmasVariableTreeNode`) but is not rendered. Phase 4 owns icons / colors / tooltips; this phase ensures the data is there to render.

The phase ships in its own slice on top of Phase 2's FB-member resolution. Phase 2 introduces some sort of "FB member" record produced from a DD02 member-layout query (`_readDD02Block(blockNo: typeId, isMemberLayout: true)` already exists at `packages/tfc_dart/lib/core/umas_client.dart:626-665`). Phase 3 layers a `direction` field on top of whatever Phase 2 produces.

Not in scope for Phase 3: the FB visibility mechanic itself (Phase 2), browser tree icons/colors for direction (Phase 4), VAR_IN_OUT pointer dereferencing (Phase 5), or any wire-format bytes that are not part of the per-member DD02 record header.

</domain>

<decisions>
## Implementation Decisions

### Interface assumption (the Phase 2 contract)

Phase 2 has **not** landed in this worktree (branched from `f9c6df1979b3778e14abce6f77ff09a0f0875a98`; Phases 1, 2, 4, 5 run in parallel worktrees). Phase 3 codes against this assumed interface:

- Phase 2 will produce a per-FB-member result type. The most likely shape — extrapolating from the existing `UmasVariable` model at `packages/tfc_dart/lib/core/umas_types.dart:79-97` and the existing helper `_readDD02Block(... isMemberLayout: true)` — is that members get represented as `UmasVariable` instances, the same struct the top-level tree uses today. Phase 2 may rename fields (`members` vs `children`) or introduce a subtype (`UmasFbMember`); the exact field naming is Phase 2's call.
- The wire-format raw bytes that come back from a DD02 member-layout query at the per-record level are stable regardless of Phase 2's naming choice. Phase 3's classifier operates on the **byte slice** (or the equivalent parsed-but-not-classified fields). This isolates Phase 3 from naming churn.

### Direction enum

A new enum `UmasFbMemberDirection` with values `{ input, output, publicVar, inOut, unknown }`. Placement: **separate file** `packages/tfc_dart/lib/core/umas_fb_direction.dart`. Sibling-file placement (instead of dropping the enum into `umas_types.dart`) is the choice for three reasons: (a) keeps the Phase 3 diff small and concentrated; (b) avoids touching `umas_types.dart` line 1236, which Phase 1 modifies for the STRING-clamp fix — eliminates a merge conflict against Phase 1; (c) the enum + its classifier helper live together, which makes the unit test naturally co-located.

Enum spelling discipline: `publicVar` (not `var`, which is a reserved word in Dart) and `inOut` (camelCase). `unknown` is the fallback when bytes don't match any known encoding — the classifier never throws; it returns `unknown` and logs at warn level.

### Direction classifier helper

A free function `UmasFbMemberDirection classifyFbMemberDirection(...)` in `packages/tfc_dart/lib/core/umas_fb_direction.dart`. Takes the raw per-member byte slice from the DD02 member-layout response (or an already-parsed struct exposing the candidate bytes — TBD by what Phase 2 exposes). Returns the enum. Pure function, no side effects, no I/O. Easy to test in isolation.

The plc4j wire-format reference (see RESEARCH.md) is the source of truth for what byte / mask / value table the classifier uses. **plc4j itself does not classify direction** (members all become children of `UmasCustomVariable` without a direction field); the relevant bytes (`unknown5`, `unknown4` in `UmasUDTDefinition`; `unknown4` in `UmasUnlocatedVariableReference`) are unparsed in plc4j. Phase 3's classifier infers direction from these "unknown" fields based on the heuristic documented in RESEARCH.md — explicitly marked as inferred-from-empirical-observation, not from a plc4j source citation that would have classified the bytes for us.

### Integration adapter (forward-compatible)

A thin adapter — `UmasFbMemberDirection directionFromMemberBytes(Uint8List recordHeader)` — that takes the 8-byte member record header (`dataType(2) + offset(2) + unknown5(2) + unknown4(2)` per plc4j `UmasUDTDefinition`) and returns the direction. Phase 2's member-layout parser can wire this in trivially regardless of its internal type shape; Phase 3 also exposes a higher-level adapter that wraps an existing `UmasVariable` member if Phase 2 builds those by hand.

If Phase 2's actual API differs from this assumption, the integration is mechanical: one call site change to pass the bytes into the classifier. The orchestrator reconciles at merge.

### Test design

Test file: `packages/tfc_dart/test/core/umas_fb_direction_test.dart` — sits next to other core tests. Pure-function tests on the classifier helper with byte fixtures. No live-PLC dependency in CI.

Fixtures: hand-crafted bytes for the three classified cases (VAR_INPUT, VAR_OUTPUT, public VAR), one inferred case (VAR_IN_OUT — even if Phase 5 will treat it as inaccessible, the direction should still classify), and at least one "unknown" fallback case. Test helper `buildMemberRecordHeader({direction, dataTypeId, offset})` mirrors the style in `test/core/umas_client_test.dart:117-136`.

### CLI surface

A new `--show-direction` flag added to the `browse` command in `packages/tfc_dart/tool/umas_cli.dart`. When set, every leaf node prints its direction alongside type/address — provides the live-PLC verification probe. Default-off so existing behavior is unchanged.

### Claude's Discretion

- Exact field name on `UmasVariableTreeNode` for direction (`direction` vs `fbMemberDirection`) — `direction` reads cleaner in code, `fbMemberDirection` is more explicit. Either is fine.
- Whether to inline the classifier-helper byte parsing as a method on `UmasFbMemberDirection` or as a free function. Free function reads better at call sites.
- Whether the enum gets a `toString()` or display-string method. Phase 4 can add one if it wants.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `UmasVariable` at `packages/tfc_dart/lib/core/umas_types.dart:79-97` — the existing per-variable model used for both top-level and member-layout records. Phase 3 may add a `direction` field here or wrap in a sibling type, depending on Phase 2's call.
- `UmasVariableTreeNode` at `packages/tfc_dart/lib/core/umas_types.dart:233-254` — the tree node that the browser consumes. Phase 3 adds a `direction` field here so Phase 4 can read it during render.
- `_readDD02Block(blockNo: typeId, isMemberLayout: true)` at `packages/tfc_dart/lib/core/umas_client.dart:626-665` — already returns parsed member records. Phase 2 will likely route through this. Phase 3's classifier slots into the parsing loop.
- `_parseVariableRecords` at `packages/tfc_dart/lib/core/umas_client.dart:729-778` — the per-record loop with the 8-byte member header (or 10-byte top-level header). Phase 3's classifier reads the 4 unknown bytes (`unknown5` + `unknown4`) for member records.
- `packages/tfc_dart/test/core/umas_client_test.dart:117-168` — fixture builders for DD02/DD03 responses. Same patterns used for Phase 3's classifier tests.

### Established Patterns

- Bytes-as-source-of-truth: existing parsers in `umas_types.dart` operate on `ByteData.sublistView(...)` for little-endian uint16/uint32 reads. Phase 3's classifier follows the same convention.
- Enum-with-fallback: the existing `UmasSessionState` and `UmasSubFunction` enums use a `code` field for wire-format mapping. Phase 3's `UmasFbMemberDirection` follows the same pattern if any byte values need to round-trip; otherwise the enum stays purely-typed.
- plc4j as the oracle: existing code comments cite `PLC4X mspec` and reference `protocols/umas/.../umas.mspec`. Phase 3's classifier comment chain points at the same mspec lines for `UmasUDTDefinition` / `UmasUnlocatedVariableReference`.

### Integration Points

- Phase 2's `_expandVariable` member-walk loop at `packages/tfc_dart/lib/core/umas_client.dart:2038-2058` — where each child `UmasVariable` is built from `m.blockNo`/`m.offset`/`m.dataTypeId`. Phase 3 attaches direction to the resulting `UmasVariableTreeNode` here (or one level up depending on what Phase 2 builds).
- Phase 4 will consume `UmasVariableTreeNode.direction` in `lib/widgets/umas_browse.dart`. Out of scope for Phase 3 — but the field is the contract.
- `packages/tfc_dart/tool/umas_cli.dart:186-196` — the `_printTree` helper formats a node line. Phase 3 extends this to optionally render `direction` when `--show-direction` is set.

</code_context>

<specifics>
## Specific Ideas

- Live-PLC acceptance probe: `dart run packages/tfc_dart/tool/umas_cli.dart browse 192.168.112.159 --show-direction` produces output where at least one `M_Elevator` child has `direction=input` and at least one has `direction=output`. If Phase 2's resolution mechanism is also in this worktree at test time (it may not be — Phase 2 runs in parallel), the live-PLC check is best-effort; CI gate is the unit test on the classifier with byte fixtures.
- Classifier output is deterministic and pure: given the same byte slice it always returns the same enum value. No I/O, no logging from inside the classifier (caller may log).
- Test count target: 5+ unit tests on the classifier (one per enum value, plus the unknown fallback, plus an edge-case test for a truncated byte slice).

</specifics>

<deferred>
## Deferred Ideas

- Visual rendering of direction in the browser tree — owned by Phase 4 (UI-01, UI-02).
- Direction-aware read paths (e.g., refusing to write to VAR_OUTPUT) — not in v1.1 scope; write paths are SWEEP candidates in Phase 5.
- Reconciling with Phase 2's exact API shape — handled mechanically at merge by the orchestrator; CONTEXT documents the assumption.
- VAR_IN_OUT pointer dereferencing — Phase 5 stretch (FB-05); Phase 3 only classifies the direction.

</deferred>
