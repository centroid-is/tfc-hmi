/// NAIVE PLACEHOLDER — the RED half of this plan's TDD cycle.
///
/// This compares the `DynamicValue` wrappers, which is the obvious thing and
/// the wrong thing. It is committed only so the suite can be run against it and
/// the failure recorded; the next commit replaces it.
library;

import 'package:open62541/open62541.dart' show DynamicValue;

/// One member of a struct write that changed.
class MemberChange {
  const MemberChange({
    this.member,
    this.oldValue,
    this.newValue,
    this.noBaseline = false,
  });

  final String? member;
  final String? oldValue;
  final String? newValue;
  final bool noBaseline;
}

/// The cap applied to a rendered value.
const int kMaxRenderedValueLength = 256;

/// Appended to a rendering the cap cut short.
const String kRenderTruncationMarker = '...[truncated]';

List<MemberChange> diffDynamicValue(DynamicValue? oldValue, DynamicValue newValue) {
  if (oldValue == null) {
    return [MemberChange(newValue: newValue.asString, noBaseline: true)];
  }
  final changes = <MemberChange>[];
  for (final entry in newValue.entries) {
    final oldMember = oldValue.asObject[entry.key];
    if (oldMember != entry.value) {
      changes.add(MemberChange(
        member: entry.key,
        oldValue: oldMember?.asString,
        newValue: entry.value.asString,
      ));
    }
  }
  return changes;
}
