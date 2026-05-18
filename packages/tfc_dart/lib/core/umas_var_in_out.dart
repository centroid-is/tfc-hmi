/// VAR_IN_OUT readability helpers (Phase 5 / FB-05).
///
/// plc4j (Apache PLC4X) does not implement a pointer-resolution path
/// for VAR_IN_OUT FB members. From a direct inspection of
/// `plc4j/drivers/umas/.../protocol/UmasProtocolLogic.java`
/// (https://github.com/apache/plc4x/blob/develop/plc4j/drivers/umas/src/main/java/org/apache/plc4x/java/umas/readwrite/protocol/UmasProtocolLogic.java):
///
///     "treats all symbols uniformly as readable/writable entities
///     without explicit support for parameter direction metadata
///     (VAR_INPUT, VAR_OUTPUT, VAR_IN_OUT) or visibility restrictions
///     typical in IEC 61131-3 function block interfaces."
///
/// In practice, an attempt to read a VAR_IN_OUT slot via 0x22
/// (ReadVariable) returns the PLC's 0x94 "address cannot be served"
/// error because the slot stores a pointer, not the data. plc4j
/// drops the read; we surface the member with `readable=false` and
/// a human-readable `unreadableReason` instead — see Phase 5 success
/// criterion FB-05 path (b).
library;

import 'umas_fb_direction.dart';

/// Human-readable reason why an FB member is unreadable, or `null`
/// when the member is readable through the normal read path.
///
/// Currently only [UmasFbMemberDirection.inOut] carries a reason —
/// every other direction is readable.
String? unreadableReasonForDirection(UmasFbMemberDirection direction) {
  switch (direction) {
    case UmasFbMemberDirection.inOut:
      // The exact wording is part of the FB-05 contract — Phase 4 UI
      // searches for the literal substring "VAR_IN_OUT" to render
      // the affordance. The 0x94 hint helps operators / log
      // searchers connect the dot when they see the error code in
      // captures from `dump-array` or live wireshark traces.
      return 'VAR_IN_OUT (PLC returns 0x94; plc4j drops with reason)';
    case UmasFbMemberDirection.input:
    case UmasFbMemberDirection.output:
    case UmasFbMemberDirection.publicVar:
    case UmasFbMemberDirection.unknown:
      return null;
  }
}

/// Whether an FB member with the given direction is expected to be
/// readable through the normal 0x22 / 0x50 read path.
///
/// `VAR_IN_OUT` members are pointer-backed and unreadable by design;
/// every other direction is readable.
bool isReadableForDirection(UmasFbMemberDirection direction) {
  return direction != UmasFbMemberDirection.inOut;
}
