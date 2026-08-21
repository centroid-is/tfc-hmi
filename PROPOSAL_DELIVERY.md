# Proposal delivery

## How a proposal travels

The MCP server is hosted **inside the Flutter app** (`lib/mcp/mcp_sse_server.dart`,
started from `lib/providers/mcp_bridge.dart`). A write tool and the banner that
displays its result are objects in the same isolate, and the path between them
is a callback:

```
tool handler (propose_asset / create_alarm / ...)
   -> ProposalService.wrapProposal  -> onProposal(wrapped)
   -> McpBridgeNotifier.proposalStream
   -> ChatNotifier.injectProposal
   -> proposalStateProvider
   -> ProposalBanner / page editor / alarm editor / key repository
```

Nothing about a proposal is persisted. It exists from the moment a tool wraps
it until the operator accepts, rejects or dismisses it. **Accepting** is what
makes it durable: the editor writes the key mapping, alarm or page asset
through the same code path it uses when a person types the change by hand. The
UI is what talks to the database; the proposal system is a tunnel between the
AI and the UI.

An in-app tool call surfaces the same proposal twice — once from the callback
above, once from the tool result inside `ChatNotifier`'s own tool loop. Both
copies carry the identical JSON, because the write tool returns
`jsonEncode(wrapped)` of the very map the callback was handed, and
`ProposalStateNotifier.addProposal` deduplicates on it. Ids are minted locally
by `nextLocalProposalId()` and mean nothing outside the process.

Operator decisions travel back the same way, in memory: every accept, reject,
dismiss and view emits a `ProposalFeedback` event, which the chat lifecycle
turns into an operator-decision note in the conversation. The AI is told; there
is nothing for it to poll.

## Why the database left the path

Until 2026-08-21 a proposal was inserted into `mcp_proposal` and a
`ProposalWatcher` polled the table every three seconds to find it again — a
database round trip and up to three seconds of latency to move a
`Map<String, dynamic>` between two objects in one isolate. Status write-backs
recorded the operator's decision on the row.

The poll and both status writes bound their parameters with `?`, which SQLite
accepts and PostgreSQL does not; against the plant's Postgres they were syntax
errors, and all three sat inside `catch (_) {}`. So the watcher had never read
a proposal out of the table in production, and no decision had ever been
recorded: 1018 rows, every one `pending`. Everything that worked, worked
through the callback.

That backlog also explains a run of commissioning bugs that were treated as
separate: proposals not surviving a restart, "the yellow boxes came back" after
Accept all, and "I rejected it but it is still there". The last two were races
between the un-awaited database write and the state removal — with the write
gone, the state change lands in the caller's own microtask and the race has
nowhere to happen.

The `mcp_proposal` table itself is still in the schema; dropping it needs a
migration and nothing reads or writes it, so those 1018 rows are inert.

## What the database bought, and why it is not missed

* **Audit** of who proposed what. Real, but it never worked: no row ever
  recorded an outcome, so the table said only that the AI had suggested
  something, not what came of it. The accepted change itself is auditable
  where it lands, in the config.
* **Surviving a crash.** A proposal is a suggestion that has not been looked at
  yet. Re-asking is cheaper than the machinery, and restores never worked
  either — the restore query only ever looked for `pending`, while the banner
  had already flipped the row to `notified`.
* **Working out-of-process.** If the MCP server is ever hosted separately from
  the UI, it needs a transport. A dead table is not one; that job would want a
  socket, and the callback boundary is the right place to put it.
