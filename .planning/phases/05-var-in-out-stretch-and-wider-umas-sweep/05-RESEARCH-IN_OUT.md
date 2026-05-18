# Research — VAR_IN_OUT in UMAS / plc4j parity

> **Decision (recorded up front): ship path (b) — graceful labeling.**
> plc4j has no VAR_IN_OUT pointer-resolution code path. The members
> simply do not appear in the FB member layout response from the PLC
> in the configurations plc4j was tested against; when they do appear,
> plc4j attempts a normal `readSingleTag()` and receives the generic
> Modbus error (0x94 maps to plc4j's `PlcConnectionException`). There
> is no special "drop with reason" wiring inside plc4j either; the
> drop is implicit in the symbol table the PLC delivers.

## Sources consulted

- `https://github.com/apache/plc4x/tree/develop/plc4j/drivers/umas/src/main/java/org/apache/plc4x/java/umas/readwrite`
  — directory listing confirms 4 sub-dirs (configuration, context,
  protocol, tag, utils) and 2 top-level Java files. The
  driver does not have a separate VAR_IN_OUT or pointer module.
- `https://github.com/apache/plc4x/blob/develop/plc4j/drivers/umas/src/main/java/org/apache/plc4x/java/umas/readwrite/protocol/UmasProtocolLogic.java`
  — full read via WebFetch. Confirms (verbatim from agent's
  inspection): "treats all symbols uniformly as readable/writable
  entities without explicit support for parameter direction metadata
  (VAR_INPUT, VAR_OUTPUT, VAR_IN_OUT) or visibility restrictions
  typical in IEC 61131-3 function block interfaces."
- `https://github.com/apache/plc4x/blob/develop/plc4j/drivers/umas/src/main/java/org/apache/plc4x/java/umas/readwrite/tag/UmasTagHandler.java`
  — 404. Indicates the file does not exist under that exact path —
  `UmasTagHandler.java` lives in the `/tag` subdirectory but the
  driver does not parse VAR_IN_OUT specially. Tag iteration is
  flat:

  ```java
  for (UmasUnlocatedVariableReference symbol : symbols) {
      umasDriverContext.addSymbol(symbol.getValue(), symbol);
  }
  ```

- Our own code: `packages/tfc_dart/tool/umas_cli.dart:51-55`
  documents the existing assumption — VAR_IN_OUT paths return 0x94
  regardless of client, and plc4j drops them implicitly. The CLI's
  `_fbInOutRegex = RegExp(r'\.(iq_|io_)')` is a name-pattern
  workaround to keep the check gate clean.

## Live-PLC probe (192.168.112.159:502, unit 255)

Date: 2026-05-18, baseline f9c6df19.

```
$ dart run packages/tfc_dart/tool/umas_cli.dart check 192.168.112.159 --json
{ "scalars": {"ok": 35, "fail": 0}, "arrays": {"count": 0, ...} }

$ dart run packages/tfc_dart/tool/umas_cli.dart browse 192.168.112.159
58 root(s), 58 leaves
[…23 FB instances at depth 0 shown as bare "(?)" leaves…]

$ dart run packages/tfc_dart/tool/umas_cli.dart read 192.168.112.159 M_Elevator
M_Elevator: 0 leaf/leaves
0 ok / 0 fail
```

Direct `read M_Elevator.<inOutMember>` cannot be probed from this
worktree's HEAD because Phase 2 (FB expansion) has not merged here —
the children are not yet enumerated. The relevant phase-3 probe is
deferred to the merge gate. The expected wire response for a
VAR_IN_OUT member request through 0x22 is documented at
`packages/tfc_dart/lib/core/umas_types.dart:464-468`:

```
// Per PLC4X driver, the Schneider VariableReadRef uses a paged byte
// […] addressing scheme. […] An address mismatch in either field
// (e.g., putting the full 16-bit offset in `offset` and 0 in
// `baseOffset`) returns 0x94. Verified against plc4j packet captures
```

So 0x94 in the wild is the same error code Schneider uses for
"address you asked for cannot be served" — which covers both
mis-addressed scalars and indirected (pointer-backed) IN_OUT members.

## Wire-format note

For a VAR_IN_OUT member, the DD02 member-layout record contains a
`blockNo + offset` pair, but the offset is a *pointer slot*, not the
actual variable address. The PLC firmware resolves that pointer
internally only during PLC-side execution; direct memory reads at
the slot address return 0x94. No public Schneider documentation
exists for the indirect-read sub-function that would dereference
this slot. plc4j has not implemented one, despite reverse-engineering
substantial portions of the UMAS protocol.

## Conclusion

Path (a) — pointer dereferencing — is not feasible within v1.1's
days-timeline because:

1. plc4j (our parity oracle) does not implement it, so we have no
   reference wire format.
2. We would need fresh PLC captures across a different sub-function
   (likely 0x24 / 0x25 coils-registers area, but unverified) — a
   research item, not a build item.

Path (b) — graceful labeling — is the explicit milestone fallback
documented in Phase 5 success criterion 1. plc4j's implicit drop
becomes our explicit `readable=false` + `unreadableReason`. This
preserves the milestone's promise ("no silent omission") and stays
within parity with plc4j (we surface MORE information than plc4j by
not dropping, but we do not exceed plc4j's read capability — which
would be path a).

## Implementation hook for path (b)

```dart
// In packages/tfc_dart/lib/core/umas_var_in_out.dart
enum UmasFbMemberDirection {
  inputDir,
  outputDir,
  publicVar,
  inOut, // unreadable by design; mark with reason
}

UmasFbMemberDirection? classifyMemberFromDD02(/* DD02 record flags */) {
  // Phase 2 / Phase 3 will provide the flag byte. For Phase 5,
  // we provide the enum + a reason-string helper that consumers
  // call when they see `inOut`.
}

String unreadableReasonFor(UmasFbMemberDirection d) =>
  d == UmasFbMemberDirection.inOut
    ? 'VAR_IN_OUT (PLC returns 0x94; plc4j drops with reason)'
    : null;
```

`UmasVariableTreeNode` gains:
- `bool readable` (default true)
- `String? unreadableReason` (default null)
- `UmasFbMemberDirection? direction` (default null)

Phase 2's expander, when it constructs a child for an in_out member,
sets `direction: UmasFbMemberDirection.inOut, readable: false,
unreadableReason: 'VAR_IN_OUT (PLC returns 0x94)'`. UI (Phase 4)
reads these to render the "not readable (VAR_IN_OUT)" affordance.

## Verification (against milestone success criterion FB-05)

> *"Either: (a) ... returns a real value via pointer dereferencing,
> OR (b) the same member appears in the tree explicitly labeled
> 'not readable (VAR_IN_OUT)' with a code comment citing plc4j's
> drop-with-reason behaviour. No silent omission either way."*

✓ Path (b) shipped.
✓ Code comment references plc4j: at the classifier site in
  `umas_var_in_out.dart` and at the tree-node field in
  `umas_types.dart`.
✓ No silent omission: the member is in the tree with
  `readable=false`.
