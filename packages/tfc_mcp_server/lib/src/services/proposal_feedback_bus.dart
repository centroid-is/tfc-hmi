import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart' show AbortSignal;

/// Raised when [ProposalFeedbackBus.waitFor] is called while the bus is
/// already holding its maximum number of parked callers.
///
/// An [Exception] rather than an [Error] on purpose: it travels back to the
/// MCP client as a tool error instead of tearing down the isolate.
class ProposalFeedbackBusyException implements Exception {
  ProposalFeedbackBusyException(this.waiterCount, this.maxWaiters);

  final int waiterCount;
  final int maxWaiters;

  String get message =>
      'Too many concurrent proposal-feedback waiters ($waiterCount of '
      '$maxWaiters). Retry with backoff, or use get_proposal_feedback to '
      'poll instead of parking a long call.';

  @override
  String toString() => 'ProposalFeedbackBusyException: $message';
}

/// A slice of the decision log, as handed to a caller.
class ProposalFeedbackPage {
  const ProposalFeedbackPage({
    required this.decisions,
    required this.lastSeq,
    required this.firstAvailableSeq,
    required this.truncated,
    this.timedOut = false,
  });

  /// The decisions newer than the caller's cursor, oldest first.
  final List<Map<String, dynamic>> decisions;

  /// The highest sequence number the bus has ever issued.
  ///
  /// A caller passes this back as `since` next time. It is the bus-wide
  /// high-water mark, not the last entry in [decisions], so a caller that
  /// asked for a slice that was filtered down to nothing still moves its
  /// cursor forward.
  final int lastSeq;

  /// The lowest sequence number still held in the ring buffer, or 0 when
  /// nothing has been published yet.
  final int firstAvailableSeq;

  /// Whether decisions between the caller's cursor and [firstAvailableSeq]
  /// were evicted from the ring before the caller came back for them.
  ///
  /// A caller that sees this knows its view of the operator's decisions has
  /// a hole in it, and should re-read the config rather than assume the
  /// decisions it did receive are the whole story.
  final bool truncated;

  /// Whether a [ProposalFeedbackBus.waitFor] gave up before a decision landed.
  final bool timedOut;

  /// The wire form handed to the MCP client.
  Map<String, dynamic> toJson() => {
        'decisions': decisions,
        'count': decisions.length,
        'last_seq': lastSeq,
        'first_available_seq': firstAvailableSeq,
        'truncated': truncated,
        'timed_out': timedOut,
      };
}

/// The return path for operator decisions on AI proposals.
///
/// Proposals travel out of the MCP server through [ProposalCallback]; until
/// this class existed, the operator's answer travelled back only inside the
/// Flutter app, into the in-app chat conversation. An external MCP client
/// over HTTP -- which is where most proposals now come from -- got nothing
/// back at all, and had no way to learn that its twenty proposals had been
/// accepted except to ask a person.
///
/// The bus is deliberately dumb: plain maps in, plain maps out, no knowledge
/// of `PendingProposal` or any other app type. The app-side relay renders the
/// human-readable summary (the same sentence the in-app AI is told) and hands
/// it over as data.
///
/// Two properties make it usable from a client that is not always attached:
///
/// * **A bounded ring buffer.** Decisions are kept for a while after they are
///   published, so a client that reconnects -- or that was started after the
///   operator clicked Accept -- still sees them. Without this, every decision
///   made while no client held a stream would be lost, which is exactly the
///   failure mode a bare broadcast stream has.
/// * **A monotonic sequence number.** A client tracks `last_seq` and asks for
///   what is strictly newer, so reconnecting is idempotent and a duplicate
///   delivery cannot be mistaken for a second decision.
class ProposalFeedbackBus {
  /// Creates a bus retaining the last [capacity] decisions and allowing at
  /// most [maxWaiters] parked [waitFor] callers.
  ///
  /// [maxWaiters] is a guard against a misbehaving client opening long polls
  /// in a loop: each parked caller costs a [Completer] and a timer, and an
  /// unbounded number of them is an unbounded memory leak that nothing would
  /// ever reclaim.
  ProposalFeedbackBus({this.capacity = 200, this.maxWaiters = 16})
      : assert(capacity > 0),
        assert(maxWaiters > 0);

  /// How many decisions the ring buffer retains.
  final int capacity;

  /// How many [waitFor] callers may be parked at once.
  final int maxWaiters;

  final _entries = <Map<String, dynamic>>[];
  // Deliberately not sync: a listener that throws must not be able to take
  // down the publisher, which is an operator clicking Accept in the UI.
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final _waiters = <Completer<void>>[];

  int _lastSeq = 0;
  bool _closed = false;

  /// The highest sequence number issued so far. 0 before anything is published.
  int get lastSeq => _lastSeq;

  /// The lowest sequence number still retained, or 0 when the ring is empty.
  int get firstAvailableSeq =>
      _entries.isEmpty ? 0 : _entries.first['seq'] as int;

  /// How many callers are currently parked in [waitFor].
  int get waiterCount => _waiters.length;

  /// Whether anything is currently subscribed to [stream].
  ///
  /// For tests. Exists so a subscription that was never cancelled can be
  /// seen: the bus outlives every HTTP session, so a session that closes
  /// without cancelling leaves a listener here forever -- and the
  /// `isConnected` guard on the sending side makes that leak invisible from
  /// the client's side, because nothing is delivered either way.
  bool get hasListeners => _controller.hasListener;

  /// Live decisions, for listeners that want a push rather than a poll.
  ///
  /// Fires only for decisions published after the listener subscribes -- use
  /// [since] to catch up on anything older.
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  /// Records one operator decision and wakes every parked caller.
  ///
  /// [action] is `accepted`, `rejected`, `dismissed` or `viewed`. [summary]
  /// is the sentence a person could act on -- it is the whole point of the
  /// payload, so it is required rather than derived here: the renderer lives
  /// in the app, next to the proposal titles the banner actually showed.
  /// [proposals] carries one entry per proposal the action applied to.
  ///
  /// Returns the stored entry, which is also what [since] and [waitFor] hand
  /// out, so a caller reading the return value sees exactly what a client
  /// would.
  Map<String, dynamic> publish({
    required String action,
    required String summary,
    List<Map<String, dynamic>> proposals = const [],
  }) {
    if (_closed) {
      throw StateError('ProposalFeedbackBus is closed');
    }

    final entry = <String, dynamic>{
      'seq': ++_lastSeq,
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'count': proposals.length,
      'summary': summary,
      // Copied, not aliased: the caller's list is its own, and an entry that
      // is handed out repeatedly must not be mutable from outside the bus.
      'proposals': [
        for (final p in proposals) Map<String, dynamic>.unmodifiable(p),
      ],
    };

    _entries.add(entry);
    // Evict from the front. Anyone whose cursor falls behind the new front
    // learns about it through ProposalFeedbackPage.truncated.
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }

    _controller.add(entry);
    _wakeWaiters();
    return entry;
  }

  /// Everything strictly newer than [since], oldest first.
  ///
  /// `since: null` (or 0) means "everything still retained" -- a client that
  /// has never connected gets the backlog. Strictly-greater rather than
  /// greater-or-equal so a client can hand back the `last_seq` it was given
  /// without re-reading the last decision it already acted on.
  ProposalFeedbackPage since(int? since) {
    final cursor = since ?? 0;
    final decisions = [
      for (final e in _entries)
        if ((e['seq'] as int) > cursor) e,
    ];
    // A hole exists when the caller asked for something older than what the
    // ring still holds. `cursor == 0` on an empty-but-never-published bus is
    // not a hole, and neither is a cursor that is already at the high-water
    // mark: there was simply nothing to lose.
    final truncated = _entries.isNotEmpty &&
        cursor > 0 &&
        cursor < firstAvailableSeq - 1;
    return ProposalFeedbackPage(
      decisions: decisions,
      lastSeq: _lastSeq,
      firstAvailableSeq: firstAvailableSeq,
      truncated: truncated,
    );
  }

  /// Returns decisions newer than [since], parking until one arrives.
  ///
  /// Returns immediately when the backlog already holds something newer.
  /// Otherwise it waits for the first of: a [publish], [timeout] elapsing
  /// (the page comes back with `timedOut` set and no decisions), the client
  /// cancelling its request ([signal]), or the bus closing.
  ///
  /// This is the nudge an external client parks in a background process: it
  /// returns the moment the operator clicks a button, so the client learns
  /// about the decision without polling on a timer.
  Future<ProposalFeedbackPage> waitFor({
    int? since,
    Duration timeout = const Duration(seconds: 55),
    AbortSignal? signal,
  }) async {
    final immediate = this.since(since);
    if (immediate.decisions.isNotEmpty || _closed) return immediate;

    if (signal != null && signal.aborted) return immediate;

    if (_waiters.length >= maxWaiters) {
      throw ProposalFeedbackBusyException(_waiters.length, maxWaiters);
    }

    final completer = Completer<void>();
    _waiters.add(completer);

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!completer.isCompleted) completer.complete();
    });

    // The abort stream is a broadcast stream, so subscribing here does not
    // compete with anything else the transport does with the signal.
    StreamSubscription<void>? abortSub;
    if (signal != null) {
      abortSub = signal.onAbort.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
    }

    try {
      await completer.future;
    } finally {
      timer.cancel();
      await abortSub?.cancel();
      _waiters.remove(completer);
    }

    final page = this.since(since);
    // Only report a timeout when it really came back empty: a decision that
    // lands in the same tick as the timer fires is a delivery, not a timeout.
    if (timedOut && page.decisions.isEmpty) {
      return ProposalFeedbackPage(
        decisions: const [],
        lastSeq: page.lastSeq,
        firstAvailableSeq: page.firstAvailableSeq,
        truncated: page.truncated,
        timedOut: true,
      );
    }
    return page;
  }

  /// Wakes every parked caller and releases the broadcast stream.
  ///
  /// Parked callers come back with whatever the backlog holds rather than
  /// hanging until their timeout: a shutting-down server should not make a
  /// client wait 55 seconds to find out.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _wakeWaiters();
    await _controller.close();
  }

  void _wakeWaiters() {
    // Copy first: completing a waiter runs its `finally`, which mutates the
    // list we would otherwise be iterating.
    for (final waiter in List<Completer<void>>.from(_waiters)) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}
