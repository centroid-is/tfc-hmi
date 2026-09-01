/// The write path: three states, per protocol, with ambiguity resolving to
/// unknown — and the composer's `write`/`writeStatus` on top of it.
///
/// Two subjects in one file because `files_modified` names one test file for
/// both and because they are one subject seen from two ends: the translation
/// decides what a protocol's answer *means*, and the composer is the only
/// place in the package that asks a plant the question.
///
/// The sentence every arm below is defending, from `PROJECT.md` and
/// `write_result.dart:1-8`: **unknown is the safe default and rejected is the
/// claim that needs evidence.** "Rejected" tells an operator it is safe to
/// press the button again; a rejected that was actually applied is a second
/// start command on a machine somebody is standing next to.
library;

import 'package:test/test.dart';
// Reached through `src/` rather than through the barrel deliberately:
// `lib/tfc_relay_local.dart` is not in this plan's `files_modified`, and the
// only consumers of the translation in this phase are 08-07's and 08-10's
// adapters, which live inside this package and import it relatively. The plan
// that first needs it from outside adds the export line.
import 'package:tfc_relay_local/src/write_translation.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// A cmd the operator minted. Fixed rather than freshly generated wherever the
/// arm is about translation, so a failure names the same id every time.
const String cmd = '01J0000000000000000000000A';

/// An endpoint string of the shape a real OPC UA failure carries, credentials
/// and all. Every part of it is something that must not reach a panel.
const String credentialledEndpoint =
    'opc.tcp://user:secret@10.104.29.11:4840/relay';

void main() {
  group('OPC UA: a named refusal is rejected, everything else is unknown', () {
    test('GOOD is applied, and the readback is what the operator is shown', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: const WriteAcknowledged(readback: 42, at: 1700000000000),
      );
      expect(result, isA<WriteApplied>());
      expect((result as WriteApplied).readback, 42,
          reason: '"applied" means applied AND read back — the UI displays the '
              'readback, never the locally typed value (write_result.dart:117)');
      expect(result.cmd, cmd);
    });

    for (final entry in <int, String>{
      0x801F0000: 'Bad_UserAccessDenied',
      0x803C0000: 'Bad_OutOfRange',
      0x80740000: 'Bad_TypeMismatch',
      0x803B0000: 'Bad_NotWritable',
      0x80340000: 'Bad_NodeIdUnknown',
    }.entries) {
      test('${entry.value} is REJECTED, with the code on the reason', () {
        final result = translateWriteAnswer(
          protocol: UpstreamProtocol.opcUa,
          cmd: cmd,
          answer: WriteStatusAnswer(entry.key),
        );
        expect(result, isA<WriteRejected>(),
            reason: 'the server named a refusal, which is the positive '
                'evidence "rejected" requires. Anything less specific must '
                'stay unknown');
        expect((result as WriteRejected).reason.status, entry.value,
            reason: 'switch on the code, never on the English — the status is '
                'what a later phase maps to an operator-facing sentence');
      });
    }

    test('an unrecognised Bad code is UNKNOWN, not rejected', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        // BadInternalError: a real code, and one that says nothing about
        // whether the node was written before the server gave up.
        answer: const WriteStatusAnswer(0x80020000),
      );
      expect(result, isA<WriteUnknown>(),
          reason: 'a Bad code this gateway does not have a ruling for may be a '
              'service-level failure raised AFTER the node was written. '
              'Calling it rejected invites a second actuation');
    });

    test('a timeout is UNKNOWN — the request may be on the wire', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: const WriteDeadlineExpired(),
      );
      expect(result, isA<WriteUnknown>());
      expect((result as WriteUnknown).reason.kind, 'plc_timeout');
    });

    test('a deadline that expired before the link was even reachable is '
        'UNKNOWN too — the gateway cannot tell the two apart', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: const WriteDeadlineExpired(requestSent: false),
      );
      expect(result, isA<WriteUnknown>(),
          reason: 'the honest position is that this side does not know which '
              'of the two happened, and a guess in either direction is a '
              'claim it cannot support');
    });

    test('a channel loss (a thrown error) is UNKNOWN', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: WriteThrew(StateError('connection closed mid-write')),
      );
      expect(result, isA<WriteUnknown>());
    });

    test('the string fallback recognises a named code inside the prose', () {
      // 08-01 task 1(d) did not land: `client.dart:485-494` completes the write
      // completer with a formatted String because `isolate.dart` marshals every
      // error across the port as `e.toString()`. This is assumption A3's branch.
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: const WriteErrorText('Failed to write value: BadNotWritable'),
      );
      expect(result, isA<WriteRejected>());
      expect((result as WriteRejected).reason.status, 'Bad_NotWritable',
          reason: 'both spellings appear in the wild (BadNotWritable in the '
              'binding, Bad_NotWritable in the cert overlay) and they are one '
              'code');
    });

    test('an UNPARSED string is UNKNOWN, and the reason says what a wrong '
        '"rejected" costs at a keyboard', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: const WriteErrorText('Failed to write value: something new'),
      );
      expect(result, isA<WriteUnknown>(),
          reason: 'THE arm of this file. Rejected means the operator may press '
              'the button again; a rejected that was actually applied is a '
              'second start command on a machine somebody is standing next '
              'to. An unparsed sentence is not evidence of refusal');
      expect((result as WriteUnknown).reason.kind, 'unparsed_upstream_error');
    });

    test('an upstream error string is REDACTED before it becomes a reason', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa,
        cmd: cmd,
        answer: const WriteErrorText(
            'write to $credentialledEndpoint failed: BadInternalError'),
      );
      final rendered = result.toJson().toString();
      expect(rendered, isNot(contains('secret')),
          reason: 'T-08-24: a panel with no privileges renders this reason');
      expect(rendered, isNot(contains('user')));
      expect(rendered, isNot(contains('10.104.29.11')),
          reason: 'the endpoint is as much of a disclosure as the password — '
              'it names a machine on the plant network');
      expect(rendered, isNot(contains('4840')));
    });
  });

  group('Modbus: an exception response is the device answering', () {
    test('a function-code echo is applied', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.modbus,
        cmd: cmd,
        answer: const WriteAcknowledged(readback: true),
      );
      expect(result, isA<WriteApplied>());
    });

    test('an exception response is REJECTED, with its code', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.modbus,
        cmd: cmd,
        answer: const WriteStatusAnswer(0x02),
      );
      expect(result, isA<WriteRejected>());
      expect((result as WriteRejected).reason.status,
          'Modbus_IllegalDataAddress');
    });

    test('an exception code outside the table is STILL rejected — unlike OPC '
        'UA, an exception response IS the device refusing', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.modbus,
        cmd: cmd,
        answer: const WriteStatusAnswer(0x7F),
      );
      expect(result, isA<WriteRejected>(),
          reason: 'a Modbus exception PDU is a reply: the slave parsed the '
              'request and declined it. The OPC UA ambiguity does not exist '
              'here, because there is no service layer above the write that '
              'could fail after the register moved');
      expect((result as WriteRejected).reason.status, 'Modbus_Exception_0x7f');
    });

    test('no response inside the deadline is UNKNOWN', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.modbus,
        cmd: cmd,
        answer: const WriteDeadlineExpired(),
      );
      expect(result, isA<WriteUnknown>());
    });
  });

  group('UMAS: a typed exception splits the same way', () {
    test('a typed code is rejected', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.umas,
        cmd: cmd,
        answer: const WriteStatusAnswer(0x0F),
      );
      expect(result, isA<WriteRejected>());
      expect((result as WriteRejected).reason.status, 'Umas_0x0f');
    });

    test('an untyped throw is unknown', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.umas,
        cmd: cmd,
        answer: WriteThrew(StateError('socket closed')),
      );
      expect(result, isA<WriteUnknown>(),
          reason: 'the adapter wraps both directions symmetrically '
              '(state_man.dart:2005-2018) and an exception that is not a '
              'typed UMAS refusal is a transport failure, not a refusal');
    });

    test('a timeout is unknown', () {
      expect(
          translateWriteAnswer(
            protocol: UpstreamProtocol.umas,
            cmd: cmd,
            answer: const WriteDeadlineExpired(),
          ),
          isA<WriteUnknown>());
    });
  });

  group('M2400: read-only by protocol answers a refusal, never an exception',
      () {
    test('a write is REJECTED with Bad_NotWritable, in the cert overlay\'s '
        'exact shape', () {
      final result = translateWriteAnswer(
        protocol: UpstreamProtocol.m2400,
        cmd: cmd,
        answer: const WriteDeadlineExpired(),
      );
      expect(result, isA<WriteRejected>(),
          reason: 'state_man.dart:1266-1268 throws UnsupportedError here, '
              'which reads to a session as "the write failed for an unknown '
              'reason". The honest answer is a refusal, and it is the same '
              'refusal cert_health_state_man.dart:411-424 gives');
      final reason = (result as WriteRejected).reason;
      expect(reason.kind, 'not_writable');
      expect(reason.status, 'Bad_NotWritable',
          reason: 'the contract leg\'s readOnlyKey asserts on the STATUS, not '
              'only on the arm — an operator reading two different refusals '
              'from two layers of one gateway learns nothing from the '
              'difference');
    });

    test('even an acknowledgement is rejected — a read-only device cannot '
        'have applied it', () {
      expect(
          translateWriteAnswer(
            protocol: UpstreamProtocol.m2400,
            cmd: cmd,
            answer: const WriteAcknowledged(readback: 1),
          ),
          isA<WriteRejected>());
    });
  });

  group('the ambiguity rule holds across every protocol', () {
    test('a deadline is unknown for all four, and never rejected', () {
      for (final protocol in UpstreamProtocol.values) {
        final result = translateWriteAnswer(
          protocol: protocol,
          cmd: cmd,
          answer: const WriteDeadlineExpired(),
        );
        if (protocol == UpstreamProtocol.m2400) {
          // The one exception, and it is a rejection for the opposite reason:
          // nothing was ever sent, because the device takes no writes at all.
          expect(result, isA<WriteRejected>());
          continue;
        }
        expect(result, isA<WriteUnknown>(),
            reason: '$protocol turned a lost answer into something other than '
                'unknown');
      }
    });

    test('every translated result carries the operator\'s own cmd', () {
      for (final answer in <WriteAnswer>[
        const WriteAcknowledged(readback: 1),
        const WriteStatusAnswer(0x803B0000),
        const WriteErrorText('nothing recognisable'),
        const WriteDeadlineExpired(),
        WriteThrew(StateError('x')),
      ]) {
        expect(
            translateWriteAnswer(
              protocol: UpstreamProtocol.opcUa,
              cmd: cmd,
              answer: answer,
            ).cmd,
            cmd,
            reason: 'an outcome under a different id is an outcome nothing can '
                'reconcile through writeStatus later');
      }
    });
  });

  group('the array-element ruling: refuse, do not read-modify-write', () {
    test('an array-element write with no expect is REJECTED by name', () {
      final refusal = guardArrayElementWrite(cmd: cmd, hasExpect: false);
      expect(refusal, isA<WriteRejected>(),
          reason: 'state_man.dart:2033-2039 reads the array, replaces one '
              'element and writes it back — not atomic. On a gateway serving '
              'thirty panels a concurrent change between the read and the '
              'write is silently overwritten, which is somebody else\'s '
              'setpoint disappearing');
      expect((refusal! as WriteRejected).reason.kind,
          'array_element_requires_expect',
          reason: 'a named refusal is a page-editor bug report; a silent '
              'overwrite is a plant incident');
    });

    test('with an expect present the write may proceed', () {
      expect(guardArrayElementWrite(cmd: cmd, hasExpect: true), isNull,
          reason: 'the comparison is the guard the read-modify-write needs, '
              'and null here means "no refusal — carry on"');
    });
  });
}
