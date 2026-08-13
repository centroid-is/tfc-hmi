/// The shared contract every `StateManApi` implementation is judged against.
///
/// One suite runs against `LocalStateMan` (server, over DeviceClients and
/// TimescaleDB) and `RemoteStateMan` (client, over the pipe), and later
/// against both through a fault-injection proxy. That is only possible because
/// this package imports **no implementation**: the sole coupling to an
/// implementation is the factory function each sub-suite takes as a parameter.
///
/// It is also a separate package on purpose. `package:test` is a real entry in
/// this package's `dependencies`, which would be unacceptable in
/// `tfc_relay_protocol` — that package is imported by the Flutter app, and
/// `test` pulls `analyzer` into the app's version solve.
///
/// Today this exports only the two helpers every check is built from. Plan 11
/// fills in the sub-suites (`runSubscribeContract`, `runWriteContract`,
/// `runFreshnessContract`, ...) and the `runStateManContract` umbrella.
library;

// Nothing else is exported until plan 11 adds the sub-suites.
export 'src/check.dart';
