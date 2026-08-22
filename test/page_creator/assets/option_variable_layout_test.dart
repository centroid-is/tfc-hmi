import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/option_variable.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';

/// Layout of the option variable's collapsed face.
///
/// The chevron is an `Icon`, which is a square glyph: its `size` is spent on
/// width as much as on height. The `Row` it sits in only offers it a height,
/// so sizing it to `arrowConstraints.maxHeight` makes it as wide as the asset
/// is tall. Every asset taller than it is wide then overflows -- the
/// `Expanded` label collapses to zero and the row is still too wide by the
/// difference. Dragging an option variable narrow in the page editor is
/// enough to reach it.
void main() {
  Widget wrap(Widget child, {required Size size}) {
    return ProviderScope(
      overrides: [
        stateManProvider.overrideWith((_) async => _FakeStateMan()),
      ],
      child: BeamerProvider(
        routerDelegate: BeamerDelegate(
          locationBuilder: RoutesLocationBuilder(
            routes: {'*': (_, __, ___) => const SizedBox.shrink()},
          ).call,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  OptionVariableConfig config() => OptionVariableConfig(
        variableName: 'machine',
        options: [
          OptionItem(value: 'a', label: 'Baader 1'),
          OptionItem(value: 'b', label: 'Baader 2'),
        ],
        selectedValue: 'a',
      );

  /// Every box shape the page editor can produce, including the ones that
  /// used to overflow. The failure is a function of the aspect ratio only.
  const shapes = <String, Size>{
    'wide and short (the usual shape)': Size(220, 40),
    'square': Size(80, 80),
    'taller than wide': Size(60, 120),
    'a narrow sliver': Size(28, 200),
  };

  for (final entry in shapes.entries) {
    testWidgets('does not overflow when ${entry.key}', (tester) async {
      await tester.pumpWidget(
          wrap(OptionVariableWidget(config()), size: entry.value));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'a ${entry.value.width}x${entry.value.height} option '
              'variable overflowed its own box');
    });
  }

  testWidgets('the chevron never claims more width than the box has',
      (tester) async {
    const box = Size(60, 120);
    await tester.pumpWidget(wrap(OptionVariableWidget(config()), size: box));
    await tester.pump();

    final icon = tester.getSize(find.byType(Icon));
    expect(icon.width, lessThanOrEqualTo(box.width),
        reason: 'the chevron is square and sized off the row height, so on a '
            'box taller than it is wide it grew wider than the asset');
    expect(icon.width, greaterThan(0),
        reason: 'capping the chevron must not shrink it away entirely');
  });

  testWidgets('the label still gets room beside the chevron', (tester) async {
    const box = Size(60, 120);
    await tester.pumpWidget(wrap(OptionVariableWidget(config()), size: box));
    await tester.pump();

    final icon = tester.getSize(find.byType(Icon));
    expect(icon.width, lessThan(box.width * 0.5),
        reason: 'the label claims 70% of the width; a chevron taking half or '
            'more leaves nothing to read');
  });
}

class _FakeStateMan implements StateMan {
  final Map<String, String> _subs = {};

  @override
  void setSubstitution(String name, String value) => _subs[name] = value;

  @override
  String? getSubstitution(String name) => _subs[name];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
    );
  }
}
