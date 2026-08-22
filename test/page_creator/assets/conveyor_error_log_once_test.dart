// A stream that has failed must be reported once, not once per frame.
//
// The conveyor logged its stream error from inside `StreamBuilder`'s builder.
// That builder runs on every rebuild, not only when the stream reports
// something new, and a failed stream keeps handing back the same error — so
// the line was written again every time the widget rebuilt. Resizing the
// window rebuilds the page continuously, which turned one unresolved key into
// a solid wall of identical lines, multiplied by every conveyor on the page.
//
// Reporting the error is still right. Reporting it several hundred times a
// second is not: it buries everything else in the log, including whatever the
// operator is actually trying to find.

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

void main() {
  group('a failure is reported once', () {
    test('the first sighting is reported', () {
      final gate = RepeatedErrorGate();
      expect(gate.shouldReport(StateError('key not found')), isTrue);
    });

    test('the same failure on later rebuilds is not', () {
      final gate = RepeatedErrorGate();
      final error = StateError('key not found');
      expect(gate.shouldReport(error), isTrue);
      for (var frame = 0; frame < 240; frame++) {
        expect(gate.shouldReport(error), isFalse,
            reason: 'rebuild $frame logged the same error again');
      }
    });

    test('an equal-but-distinct error is still the same failure', () {
      // Each rebuild may hand back a fresh instance describing the same
      // problem; what matters is whether the log line would differ.
      final gate = RepeatedErrorGate();
      expect(gate.shouldReport(StateError('no such key: line 3 drive')), isTrue);
      expect(
          gate.shouldReport(StateError('no such key: line 3 drive')), isFalse);
    });
  });

  group('but a different failure still gets through', () {
    test('a changed error is reported', () {
      final gate = RepeatedErrorGate();
      expect(gate.shouldReport(StateError('no such key')), isTrue);
      expect(gate.shouldReport(StateError('connection refused')), isTrue);
      expect(gate.shouldReport(StateError('connection refused')), isFalse);
    });

    test('a failure that returns after a recovery is reported again', () {
      // Otherwise a belt that drops out, comes back and drops out again would
      // be silent the second time — the case most worth seeing.
      final gate = RepeatedErrorGate();
      final error = StateError('connection refused');
      expect(gate.shouldReport(error), isTrue);
      expect(gate.shouldReport(error), isFalse);
      gate.recovered();
      expect(gate.shouldReport(error), isTrue);
    });

    test('recovering twice in a row does not resurrect a report', () {
      final gate = RepeatedErrorGate();
      gate.recovered();
      gate.recovered();
      expect(gate.shouldReport(StateError('down')), isTrue);
      expect(gate.shouldReport(StateError('down')), isFalse);
    });
  });

  group('degenerate errors', () {
    test('a null error is reported once like any other', () {
      // `snapshot.error` is nullable; a gate that treated null as "nothing
      // reported yet" would log every frame for exactly the case it exists
      // to quiet.
      final gate = RepeatedErrorGate();
      expect(gate.shouldReport(null), isTrue);
      expect(gate.shouldReport(null), isFalse);
    });

    test('null and a real error are told apart', () {
      final gate = RepeatedErrorGate();
      expect(gate.shouldReport(null), isTrue);
      expect(gate.shouldReport(StateError('down')), isTrue);
      expect(gate.shouldReport(null), isTrue);
    });

    test('a fresh gate has reported nothing', () {
      // Two conveyors must not share a verdict; each holds its own gate.
      final one = RepeatedErrorGate();
      final two = RepeatedErrorGate();
      final error = StateError('down');
      expect(one.shouldReport(error), isTrue);
      expect(two.shouldReport(error), isTrue);
    });
  });
}
