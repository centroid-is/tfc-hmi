import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/proposal_feedback_bus.dart';
import 'tool_registry.dart';

/// Default park time for `await_proposal_feedback`, in seconds.
///
/// Just under a minute so it comfortably clears the 60-second idle timeout
/// that proxies and HTTP clients commonly apply, while still being long
/// enough that a client re-arming it once a minute is effectively always
/// listening.
const _defaultTimeoutSeconds = 55;

/// Hard ceiling on the park time.
///
/// Two minutes is the shortest read timeout seen in the wild among the
/// clients that reach this server; 110 seconds leaves headroom under it so
/// the tool returns its own answer rather than having the socket cut.
const _maxTimeoutSeconds = 110;

/// Registers the operator-decision feedback tools on [registry].
///
/// These are the return half of the proposal path. A write tool sends a
/// proposal to the operator's banner and then returns; whether the operator
/// accepted it is decided seconds or minutes later, by a person, and until
/// now that answer reached only the in-app chat. An external client polls
/// `get_proposal_feedback`, or -- better -- parks `await_proposal_feedback`
/// in a background process, which returns the instant the operator clicks a
/// button.
///
/// Both tools are registered `metered: false, audited: false`. See
/// [ToolRegistry.registerTool]: a parked long poll holds its concurrency slot
/// for its whole duration, and three of them would starve every other tool on
/// the server. Skipping the audit trail matters just as much -- a 55-second
/// poll re-armed forever would write an audit row a minute, permanently, to
/// record that nobody had decided anything.
void registerProposalFeedbackTools(
  ToolRegistry registry,
  ProposalFeedbackBus bus,
) {
  registry.registerTool(
    name: 'await_proposal_feedback',
    description:
        'Wait for the operator to accept, reject, dismiss or view proposals. '
        'Returns immediately if decisions newer than `since` are already '
        'buffered; otherwise blocks until one lands, the call is cancelled, '
        'or the timeout elapses (then `timed_out` is true and `decisions` is '
        'empty -- call again with the same `since` to keep listening). Each '
        'decision carries a human-readable `summary` of exactly what the '
        'operator acted on. Track `last_seq` and pass it back as `since` so '
        'you never see the same decision twice.',
    inputSchema: JsonSchema.object(
      properties: {
        'since': JsonSchema.integer(
          description: 'Return only decisions with a sequence number '
              'strictly greater than this. Pass the `last_seq` from your '
              'previous call. Omit on the first call to get the whole '
              'retained backlog.',
        ),
        'timeout_seconds': JsonSchema.integer(
          description: 'How long to wait for a decision before returning '
              'empty. Default $_defaultTimeoutSeconds, clamped to '
              '1..$_maxTimeoutSeconds.',
        ),
      },
    ),
    // A parked call must not hold a concurrency slot or write an audit row.
    metered: false,
    audited: false,
    handler: (arguments, extra) async {
      final since = _readSince(arguments);
      final seconds = (arguments['timeout_seconds'] as num?)?.toInt() ??
          _defaultTimeoutSeconds;
      final clamped = seconds.clamp(1, _maxTimeoutSeconds);

      try {
        final page = await bus.waitFor(
          since: since,
          timeout: Duration(seconds: clamped),
          // The client's own cancellation frees the waiter slot immediately
          // instead of leaving it parked until the timeout it will never
          // read the answer of.
          signal: extra.signal,
        );
        return _result(page);
      } on ProposalFeedbackBusyException catch (e) {
        return CallToolResult(
          content: [TextContent(text: e.message)],
          isError: true,
        );
      }
    },
  );

  registry.registerTool(
    name: 'get_proposal_feedback',
    description:
        'Non-blocking catch-up on operator decisions about proposals: '
        'returns everything buffered with a sequence number strictly greater '
        'than `since`, and returns straight away even when that is nothing. '
        'Same payload as await_proposal_feedback. Use this on reconnect, or '
        'when you cannot park a long-running call.',
    inputSchema: JsonSchema.object(
      properties: {
        'since': JsonSchema.integer(
          description: 'Return only decisions with a sequence number '
              'strictly greater than this. Omit to get the whole retained '
              'backlog.',
        ),
      },
    ),
    // Cheap and in-memory; metering it would only make it queue behind
    // whatever slow tool is running, for no benefit.
    metered: false,
    audited: false,
    handler: (arguments, extra) async {
      return _result(bus.since(_readSince(arguments)));
    },
  );
}

/// Reads the `since` cursor.
///
/// Typed as `num` rather than `int` because JSON makes no distinction and a
/// client that sends `12.0` means twelve. Anything that is not a number never
/// reaches here -- mcp_dart validates arguments against the input schema and
/// rejects the call before the handler runs.
int? _readSince(Map<String, dynamic> arguments) {
  final raw = arguments['since'];
  return raw is num ? raw.toInt() : null;
}

CallToolResult _result(ProposalFeedbackPage page) {
  return CallToolResult(
    content: [TextContent(text: jsonEncode(page.toJson()))],
  );
}
