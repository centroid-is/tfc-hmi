# tfc_access

The fixed access vocabulary shared by the HMI and, later, the relay: the seven
`AccessGroup` values, the `AccessRole` value type and the four seed roles,
`AuthenticatedUser`, the `AuthProvider` interface, and the audit contract
(`AuditRecord` + `AuditSink`).

Enums, strings and interfaces. Nothing here reaches a database, a PLC or a
widget.

## The dependency rule

**This package is pure Dart and must not depend on `tfc_dart`.**

`tfc_dart` carries the open62541 FFI and its native assets. Anything depending
on it inherits them, and the relay was built specifically so that its server —
and a later web client — need neither. So the edge runs one way:

    tfc_dart  ──▶  tfc_access          (allowed)
    tfc_access ──▶ tfc_dart            (never)

The guards depend on what they wrap, so `GuardedStateMan` and
`GuardedPreferences` live beside `StateMan` / `PreferencesApi` in `tfc_dart` and
depend on this package, not the other way round.

`test/package_purity_test.dart` enforces this mechanically: it fails if
`tfc_dart`, `flutter`, `open62541` or `cryptography_flutter` appears in
`pubspec.yaml`, or if anything under `lib/` imports `package:flutter` or
`dart:ui`. Without it the rule rots silently — nothing in the type system
objects when somebody adds the import.

## What this is honestly for

This is an **operational guardrail against accident, not an access control.**

Three station-held credentials do the real authenticating — the OPC UA session,
the Postgres password and the D-Bus credential — and every one of them
authenticates *the station*, never a person. Everything in this package lives
inside the Dart process and is bypassed by anyone holding those credentials with
UaExpert or `psql` in front of them.

The failure mode worth guarding against is not the guardrail itself. It is
somebody concluding "the HMI has logins" and deprioritising network
segmentation.
