# Phase 3: Windows Keepalive - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `Platform.isWindows` keepalive branch to MSocket's `_configureKeepalive()` so dead TCP connections are detected within ~11 seconds on Windows, matching the existing macOS and Linux behavior. An existing branch `fix/msocket-windows-keepalive` already has the implementation.

</domain>

<decisions>
## Implementation Decisions

### Existing branch handling
- Cherry-pick the existing commit from `fix/msocket-windows-keepalive`, then write TDD tests around it
- Delete the `fix/msocket-windows-keepalive` branch after cherry-picking (cleanup stale branch)
- Claude's discretion on TDD ordering (tests first then cherry-pick, or cherry-pick then tests)

### Windows constant values
- Let the researcher verify the correct Windows TCP keepalive constants against Microsoft docs
- The existing branch uses TCP_KEEPIDLE=3, TCP_KEEPINTVL=17, TCP_KEEPCNT=16 (same as modbus_client_tcp fork)
- The roadmap success criteria text may have transposed the constant names — research should clarify
- Values stay hardcoded (5s idle, 2s interval, 3 probes) — same as all other keepalive implementations in the project

### Fallback behavior
- Claude's discretion on whether to log a warning or silently fall back when fine-grained keepalive isn't available on older Windows
- Keep the inner try/catch for fine-grained options (SO_KEEPALIVE succeeds, fine-grained options may fail separately)
- Matches modbus_client_tcp pattern

### Test strategy
- Claude's discretion on test approach for verifying Windows code path on macOS dev environment
- Add Windows keepalive tests to existing `msocket_test.dart` keepalive group (same file)
- MSocket only — do not expand scope to modbus_client_tcp

### Claude's Discretion
- TDD ordering for the cherry-pick workflow
- Test verification approach for Windows code path (code inspection, mock-based, or other)
- Whether to log a warning on keepalive fallback for older Windows
- Exact error handling structure within the Windows branch

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `packages/jbtm/lib/src/msocket.dart:127-159`: Existing `_configureKeepalive()` with macOS and Linux branches — Windows branch slots in as an `else if`
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart:265-306`: Already-implemented Windows keepalive with try/catch fallback — proven pattern to follow
- `fix/msocket-windows-keepalive` branch: Single commit with the Windows implementation ready to cherry-pick

### Established Patterns
- Platform-specific keepalive: `if (Platform.isMacOS || Platform.isIOS) { ... } else if (Platform.isLinux || Platform.isAndroid) { ... }` — add `else if (Platform.isWindows)` in same structure
- Keepalive values: 5s idle, 2s interval, 3 probes consistently across MSocket and modbus_client_tcp
- Inner try/catch for fine-grained options: established in modbus_client_tcp for Windows fallback

### Integration Points
- `_configureKeepalive()` at `msocket.dart:127` — single method to modify
- `msocket_test.dart` keepalive group at line 205 — add tests here

</code_context>

<specifics>
## Specific Ideas

No specific requirements — the implementation already exists on a branch and mirrors the modbus_client_tcp pattern exactly.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-windows-keepalive*
*Context gathered: 2026-03-06*
