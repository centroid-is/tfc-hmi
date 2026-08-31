import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/section_button.dart';

/// The decisions the section button makes before any pixel is drawn.
///
/// All four functions here answer a question about `FB_Section`'s interface
/// (`SVNCoreComponents/Section/FB_Section.TcPOU`), and getting any of them
/// wrong is a command that does the opposite of its label or a moving line
/// painted as an idle one — so they are pinned here rather than only through
/// the widget.
void main() {
  group('resolveSectionMode', () {
    test('all three bits unread is unknown, not stopped', () {
      expect(
        resolveSectionMode(enabled: null, cleanEnabled: null, permissive: null),
        SectionMode.unknown,
      );
    });

    test('any single missing member is unknown', () {
      expect(
        resolveSectionMode(
            enabled: false, cleanEnabled: false, permissive: null),
        SectionMode.unknown,
        reason: 'a struct without p_stat_xPermissive cannot be read as safe',
      );
      expect(
        resolveSectionMode(
            enabled: null, cleanEnabled: false, permissive: true),
        SectionMode.unknown,
      );
      expect(
        resolveSectionMode(
            enabled: false, cleanEnabled: null, permissive: true),
        SectionMode.unknown,
      );
    });

    test('p_stat_xEnabled is running', () {
      expect(
        resolveSectionMode(
            enabled: true, cleanEnabled: false, permissive: true),
        SectionMode.running,
      );
    });

    test('p_stat_xCleanEnabled is cleaning', () {
      expect(
        resolveSectionMode(
            enabled: false, cleanEnabled: true, permissive: true),
        SectionMode.cleaning,
      );
    });

    test('idle with the permissive satisfied is stopped', () {
      expect(
        resolveSectionMode(
            enabled: false, cleanEnabled: false, permissive: true),
        SectionMode.stopped,
      );
    });

    test('idle without the permissive is blocked (waiting, not faulted)', () {
      expect(
        resolveSectionMode(
            enabled: false, cleanEnabled: false, permissive: false),
        SectionMode.blocked,
      );
    });

    test('a running section with a lost permissive still reads as running', () {
      // The PLC drops the outputs the same scan the permissive goes away, so
      // this combination is transient at worst. Painting a line that is still
      // moving as `Blocked` — which an operator reads as idle — is the one
      // wrong answer that could get somebody hurt.
      expect(
        resolveSectionMode(
            enabled: true, cleanEnabled: false, permissive: false),
        SectionMode.running,
      );
      expect(
        resolveSectionMode(
            enabled: false, cleanEnabled: true, permissive: false),
        SectionMode.cleaning,
      );
    });
  });

  group('command guards', () {
    // p_cmd_Start and p_cmd_StartClean TOGGLE their output in FB_Section.
    // Sending Start to a running section stops it; that button must not be
    // live while it would do the opposite of what it says.
    test('Run is offered from stopped and from cleaning only', () {
      expect(canStart(SectionMode.stopped), isTrue);
      expect(canStart(SectionMode.cleaning), isTrue,
          reason: 'p_cmd_Start switches a cleaning section straight to auto');
      expect(canStart(SectionMode.running), isFalse,
          reason: 'p_cmd_Start toggles — it would STOP a running section');
      expect(canStart(SectionMode.blocked), isFalse,
          reason: 'the PLC ignores start commands without the permissive');
      expect(canStart(SectionMode.unknown), isFalse);
    });

    test('Clean is offered from stopped and from running only', () {
      expect(canClean(SectionMode.stopped), isTrue);
      expect(canClean(SectionMode.running), isTrue,
          reason: 'p_cmd_StartClean switches a running section to cleaning');
      expect(canClean(SectionMode.cleaning), isFalse,
          reason: 'p_cmd_StartClean toggles — it would stop the cleaning');
      expect(canClean(SectionMode.blocked), isFalse);
      expect(canClean(SectionMode.unknown), isFalse);
    });

    test('Stop is offered whenever the state is known, permissive or not', () {
      expect(canStop(SectionMode.running), isTrue);
      expect(canStop(SectionMode.cleaning), isTrue);
      expect(canStop(SectionMode.stopped), isTrue);
      expect(canStop(SectionMode.blocked), isTrue);
      expect(canStop(SectionMode.unknown), isFalse);
    });
  });

  group('SectionGroup — several sections behind one button', () {
    SectionGroup g(List<SectionMode> m) => SectionGroup(m);

    test('one section is never mixed', () {
      expect(g([SectionMode.running]).mixed, isFalse);
      expect(g([SectionMode.running]).label, 'Running');
    });

    test('agreement keeps the single state and a solid face', () {
      final all = g([SectionMode.running, SectionMode.running]);
      expect(all.mixed, isFalse);
      expect(all.agreed, SectionMode.running);
      expect(all.busiest, SectionMode.running);
      expect(all.quietest, SectionMode.running,
          reason: 'both halves equal means the painter draws no split');
    });

    test('disagreement splits between the busiest and the quietest', () {
      // The case the split exists for: a solid green button saying "the line
      // is running" when one of the three is standing still.
      final some = g([
        SectionMode.running,
        SectionMode.running,
        SectionMode.stopped,
      ]);
      expect(some.mixed, isTrue);
      expect(some.label, 'Mixed');
      expect(some.busiest, SectionMode.running);
      expect(some.quietest, SectionMode.stopped);
      expect(some.movingCount, 2);
    });

    test('three different states still resolve to two halves', () {
      final three = g([
        SectionMode.cleaning,
        SectionMode.blocked,
        SectionMode.stopped,
      ]);
      expect(three.busiest, SectionMode.cleaning);
      expect(three.quietest, SectionMode.stopped);
    });

    test('running outranks cleaning, so an auto line owns the top half', () {
      final both = g([SectionMode.cleaning, SectionMode.running]);
      expect(both.busiest, SectionMode.running);
      expect(both.quietest, SectionMode.cleaning);
    });

    test('unreadable ranks below everything and is never the busy half', () {
      final mix = g([SectionMode.running, SectionMode.unknown]);
      expect(mix.busiest, SectionMode.running);
      expect(mix.quietest, SectionMode.unknown);
      expect(mix.anyUnreadable, isTrue,
          reason: 'a button speaking for two sections that can see one '
              'must wear the mark');
    });

    test('all unreadable is not mixed, just unreadable', () {
      final none = g([SectionMode.unknown, SectionMode.unknown]);
      expect(none.mixed, isFalse);
      expect(none.agreed, SectionMode.unknown);
      expect(none.anyUnreadable, isTrue);
    });

    test('cleaning counts as moving', () {
      expect(g([SectionMode.cleaning, SectionMode.stopped]).movingCount, 1);
      expect(g([SectionMode.stopped, SectionMode.blocked]).movingCount, 0);
    });

    test('an empty group reads unknown rather than throwing', () {
      expect(g(const []).agreed, SectionMode.unknown);
      expect(g(const []).busiest, SectionMode.unknown);
      expect(g(const []).mixed, isFalse);
    });
  });

  group('canSend — the per-section guard behind the fan-out', () {
    // A blind broadcast of p_cmd_Start to a half-running group would start
    // the stopped members and STOP the running ones, leaving the line as it
    // was, inverted. Every command is asked per section for this reason.
    test('Start is refused for the members already running', () {
      expect(canSend(kSectionCmdStart, SectionMode.stopped), isTrue);
      expect(canSend(kSectionCmdStart, SectionMode.running), isFalse);
    });

    test('Clean is refused for the members already cleaning', () {
      expect(canSend(kSectionCmdStartClean, SectionMode.running), isTrue);
      expect(canSend(kSectionCmdStartClean, SectionMode.cleaning), isFalse);
    });

    test('Stop is accepted by anything readable', () {
      expect(canSend(kSectionCmdStop, SectionMode.running), isTrue);
      expect(canSend(kSectionCmdStop, SectionMode.blocked), isTrue);
      expect(canSend(kSectionCmdStop, SectionMode.unknown), isFalse);
    });

    test('an unrecognised field is never sent', () {
      expect(canSend('p_cmd_Nonsense', SectionMode.stopped), isFalse);
    });
  });

  group('SectionRef.displayLabel', () {
    test('an explicit label wins', () {
      expect(SectionRef(key: 'a.b.c', label: 'ST101').displayLabel, 'ST101');
    });

    test('otherwise the tail of the key, which is the instance name', () {
      expect(
        SectionRef(key: 'ST101.section.beforeFreezers.HMI').displayLabel,
        'HMI',
      );
      expect(SectionRef(key: 'plain').displayLabel, 'plain');
    });

    test('blank label and blank key both fall back rather than render empty',
        () {
      expect(SectionRef(key: 'a.b', label: '   ').displayLabel, 'b');
      expect(SectionRef(key: '').displayLabel, 'Section');
    });
  });
}
