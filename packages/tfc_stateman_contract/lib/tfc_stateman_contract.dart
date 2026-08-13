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
/// Exported here: the helpers every check is built from (`within`,
/// `expectContractViolation`), the test-only control surface an implementation
/// must expose for a case to be able to make a value arrive
/// (`StateManHarness`), and the sub-suites written so far. The remaining
/// sub-suites (`runWriteContract`, `runDataServicesContract`) and the
/// `runStateManContract` umbrella arrive with the plans that contract those
/// areas.
///
/// The reference implementation is deliberately **not** exported from here:
/// `package:tfc_stateman_contract/testing/fake_state_man.dart` is a separate
/// import path, so nothing can acquire an implementation by depending on the
/// contract.
library;

export 'src/check.dart';
export 'src/freshness_contract.dart';
export 'src/harness.dart';
export 'src/meta.dart';
export 'src/read_contract.dart';
export 'src/store_contract.dart';
export 'src/subscribe_contract.dart';
