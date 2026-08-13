/// Wire protocol for the relay pipe.
///
/// Shapes only: no transport, no JSON-RPC envelope (json_rpc_2 owns that),
/// no I/O. Everything here round-trips through plain JSON maps.
library;

export 'src/methods.dart';
export 'src/quality.dart';
export 'src/sanitize.dart';
export 'src/wire_value.dart';
export 'src/messages.dart';
export 'src/write_result.dart';
export 'src/send_buffer.dart';
export 'src/hello_gate.dart';
