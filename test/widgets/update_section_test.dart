/// Behavior of the Update Channel preferences section: reflects the stored
/// channel, persists a change, and defaults to stable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/update_channel.dart';
import 'package:tfc/widgets/preferences.dart';

Widget _testable(UpdateSection section) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: section),
  );
}

String? _selectedChannel(WidgetTester tester) {
  return tester
      .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
      .groupValue;
}

void main() {
  testWidgets('defaults to stable when nothing is stored', (tester) async {
    await tester.pumpWidget(_testable(UpdateSection(
      readChannel: () async => updateChannelStable,
      writeChannel: (_) async {},
    )));
    await tester.pumpAndSettle();

    expect(_selectedChannel(tester), updateChannelStable);
  });

  testWidgets('shows latest selected when stored', (tester) async {
    await tester.pumpWidget(_testable(UpdateSection(
      readChannel: () async => updateChannelLatest,
      writeChannel: (_) async {},
    )));
    await tester.pumpAndSettle();

    expect(_selectedChannel(tester), updateChannelLatest);
  });

  testWidgets('selecting latest persists the channel', (tester) async {
    final written = <String>[];
    await tester.pumpWidget(_testable(UpdateSection(
      readChannel: () async => updateChannelStable,
      writeChannel: (value) async => written.add(value),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Latest'));
    await tester.pumpAndSettle();

    expect(written, equals([updateChannelLatest]));
    expect(_selectedChannel(tester), updateChannelLatest);
  });

  testWidgets('switching back persists stable', (tester) async {
    final written = <String>[];
    await tester.pumpWidget(_testable(UpdateSection(
      readChannel: () async => updateChannelLatest,
      writeChannel: (value) async => written.add(value),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stable'));
    await tester.pumpAndSettle();

    expect(written, equals([updateChannelStable]));
    expect(_selectedChannel(tester), updateChannelStable);
  });
}
