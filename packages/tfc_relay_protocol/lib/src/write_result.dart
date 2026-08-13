/// The three-state write outcome — the safety-critical type in this
/// package, designed before the serialization (the RPC-layer research
/// hedge): a sealed hierarchy with NO throw on the unknown path, so client
/// code physically cannot collapse "unknown" into "failed".
///
/// JSON-RPC `error` on a write means "definitively no effect" (unauthorized,
/// malformed, unroutable) and is the ONLY retry-safe case. Everything the
/// PLC may have seen arrives here as a successful result.
library;

/// Why a write was rejected or is unknown.
final class WriteReason {
  /// Stable, greppable kind: `interlocked`, `out_of_range`, `wrong_mode`,
  /// `plc_timeout`, `link_lost`, …
  final String kind;
  final String? message;

  /// Upstream status if available (e.g. OPC UA `Bad_NotWritable`).
  final String? status;

  const WriteReason(this.kind, {this.message, this.status});

  factory WriteReason.fromJson(Map<String, Object?> json) => WriteReason(
        json['kind'] as String,
        message: json['message'] as String?,
        status: json['status'] as String?,
      );

  Map<String, Object?> toJson() => {
        'kind': kind,
        if (message != null) 'message': message,
        if (status != null) 'status': status,
      };
}

/// Result of `write` and of each entry in `writeStatus`.
sealed class WriteResult {
  /// The client-minted idempotency id (ULID), created when the operator
  /// acted — not at send time — so a re-send carries the same id.
  final String cmd;

  const WriteResult(this.cmd);

  factory WriteResult.fromJson(Map<String, Object?> json) {
    final cmd = json['cmd'] as String;
    final outcome = json['outcome'] as String;
    return switch (outcome) {
      'applied' => WriteApplied(
          cmd,
          readback: json['readback'],
          at: (json['at'] as num).toInt(),
        ),
      'rejected' => WriteRejected(
          cmd,
          WriteReason.fromJson((json['reason'] as Map).cast()),
          at: (json['at'] as num?)?.toInt(),
        ),
      'unknown' => WriteUnknown(
          cmd,
          WriteReason.fromJson((json['reason'] as Map).cast()),
        ),
      'not_received' => WriteNotReceived(cmd),
      // Forward compatibility: an outcome this client doesn't know is by
      // definition not proof of application — treat as unknown, never
      // throw on the write path.
      _ => WriteUnknown(cmd, WriteReason('unrecognized_outcome:$outcome')),
    };
  }

  Map<String, Object?> toJson();
}

/// The PLC applied the write and the gateway read the value back.
/// "Applied" always means "applied and read back" — the UI displays
/// [readback], never the locally-typed value.
final class WriteApplied extends WriteResult {
  final Object? readback;
  final int at;

  const WriteApplied(super.cmd, {required this.readback, required this.at});

  @override
  Map<String, Object?> toJson() =>
      {'cmd': cmd, 'outcome': 'applied', 'readback': readback, 'at': at};
}

/// The device said no (interlock, range, mode). A successful RPC carrying
/// bad news — NOT an error, NOT retry-safe by machine; show the reason.
final class WriteRejected extends WriteResult {
  final WriteReason reason;
  final int? at;

  const WriteRejected(super.cmd, this.reason, {this.at});

  @override
  Map<String, Object?> toJson() => {
        'cmd': cmd,
        'outcome': 'rejected',
        'reason': reason.toJson(),
        if (at != null) 'at': at,
      };
}

/// The gateway lost track (PLC timeout, link dropped mid-write). The write
/// may or may not have landed — surface "outcome unknown — verify" to the
/// operator; re-query via `writeStatus`; never auto-retry.
final class WriteUnknown extends WriteResult {
  final WriteReason reason;

  const WriteUnknown(super.cmd, this.reason);

  @override
  Map<String, Object?> toJson() =>
      {'cmd': cmd, 'outcome': 'unknown', 'reason': reason.toJson()};
}

/// `writeStatus` only: the gateway never received this cmd and its dedup
/// TTL has not expired — the one outcome that is definitively safe to
/// re-send (and even then, re-sending is an operator decision).
final class WriteNotReceived extends WriteResult {
  const WriteNotReceived(super.cmd);

  @override
  Map<String, Object?> toJson() => {'cmd': cmd, 'outcome': 'not_received'};
}
