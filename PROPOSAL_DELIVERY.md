# Proposal delivery: why the database is in the path, and what it costs

Written 2026-08-19, after three separate bugs turned out to share this root.

## How a proposal travels today

The MCP server is hosted **inside the Flutter app** (`lib/mcp/mcp_sse_server.dart`,
started from `lib/providers/mcp_bridge.dart`). A tool handler and the banner
that displays its result are objects in the same process. The path between them
is nonetheless:

```
tool handler (propose_asset / create_alarm / ...)
   -> ProposalService: INSERT INTO mcp_proposal (status='pending')
   -> ProposalWatcher: Timer.periodic(3s) polls  WHERE id > ? AND status = ?
   -> proposalStateProvider
   -> ProposalBanner / page editor
```

A database round trip and up to three seconds of latency to move a
`Map<String, dynamic>` between two objects in one isolate.

An in-process path already exists and is threaded most of the way through:

```dart
// packages/tfc_mcp_server/lib/src/services/proposal_service.dart
typedef ProposalCallback = void Function(Map<String, dynamic> wrapped);

// server.dart:79, mcp_sse_server.dart:45 — accepted and forwarded
ProposalCallback? onProposal,
```

`mcp_bridge.dart` never passes it, so it is dead wiring.

## What the database buys

* **Audit.** `mcp_proposal` records who proposed what, when, and whether it was
  accepted or rejected. On an industrial HMI that is genuinely worth having —
  "who changed this binding and when" is a real question.
* **Survives a crash.** A proposal written before the app dies is still in the
  table afterwards (in principle — see below, it is not restored today).
* **Would work out-of-process.** If the MCP server were ever hosted separately
  from the UI, the table is already the transport.

## What it costs

Three bugs hit during commissioning trace directly to this design.

### 1. Proposals do not survive a restart

`main.dart:563` calls `watcher.markNotified(p.id)` the moment a proposal
reaches the banner, which sets `status='notified'`. `proposal_watcher.dart:88`
only ever restores `status='pending'`. So anything not accepted or rejected
before a restart is unreachable — the row is still there, just invisible.

Cost during commissioning: every restart meant re-sending the batch. The 38
sensor alarms were sent five times.

### 2. Accept race — the "yellow boxes came back"

`acceptProposal()` awaits a database write before removing the proposal from
state:

```dart
Future<void> acceptProposal(int id) async {
  await _updateStatus(id, 'accepted');   // DB round trip
  _removeFromState(id);                  // only now does the UI know
}
```

`_saveToPrefs` fired 28 of these without awaiting, then cleared the staged
batch. The removals landed afterwards, each one notifying
`proposalStateProvider`, and the listener treated whatever had not been removed
yet as a fresh batch and re-staged it. Outlines reappeared after Accept all.

### 3. Reject race — "I rejected but it is still there"

Identical mechanism in `_discardProposal`: un-awaited `rejectProposal` calls,
state cleared, late removals re-trigger the listener, the remainder is
re-applied on top of the reverted page.

### 4. Latency

Up to 3s between a tool call returning and the banner showing it. Harmless
alone, but it widens every window above.

## The current mitigation

Applied 2026-08-19, deliberately defensive rather than structural:

* `await` each accept/reject before clearing the staged batch;
* a `_consumedProposalIds` set that `_applyUpdateBatch` skips permanently, so a
  late removal cannot resurrect a resolved proposal.

Same treatment in `key_repository.dart` and `alarm_editor.dart`, which had the
one-at-a-time version of the problem.

This closes the observed bugs. It does not remove the race — it serialises it.

## The structural fix, if it is ever worth doing

**State first, database as audit.**

1. Wire `onProposal` in `mcp_bridge.dart` so a proposal reaches
   `proposalStateProvider` synchronously. Delivery stops depending on the poll.
2. Accept/reject update the provider **synchronously**; the status write goes
   out unawaited, purely as an audit record. The operator's click is instant and
   no listener can observe a half-resolved batch.
3. Keep `ProposalWatcher` only for rows written by an out-of-process client. If
   there is never one, it can go entirely.
4. Fix the restore query regardless: include `'notified'`, or stop flipping the
   status until the operator actually acts. That one is worth doing on its own —
   it is a one-line change and it is the difference between a restart costing
   nothing and costing a re-send.

### Why it has not been done

It touches `proposal_state.dart`, `proposal_watcher.dart` and
`mcp_bridge.dart` — the delivery path for every proposal in the app — during a
commissioning window where proposals are being accepted every few minutes. The
mitigation above is enough to work with. This is a job for a quiet afternoon,
with the existing proposal tests as the guard.

### Argument for leaving it alone

Not everything above is a flaw. Polling is simple and hard to get wrong; a
callback path introduces ordering questions the poll does not have. The DB is
already the audit trail, and having exactly one path (rather than a fast path
plus a fallback) is easier to reason about. If item 4 alone is fixed — restarts
stop losing proposals — the remaining cost is 3s of latency and two races that
are now guarded. That may well be the right place to stop.
