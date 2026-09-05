import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/server.dart';
import 'package:tfc_mcp_server/src/services/proposal_feedback_bus.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

/// `notifications/tfc/proposal_feedback` actually reaching a client.
///
/// The tools that fetch feedback (`get_` / `await_proposal_feedback`) were
/// covered; this push path was not. It is invisible by construction — the
/// notification carries no request id, nothing awaits it, and the send is
/// deliberately unawaited and swallowed so a departed client cannot turn an
/// operator's button click into an unhandled error. A wire that was never
/// connected would look exactly like one that works.
///
/// The PR's own handover note said this was worth "one manual accept against
/// a parked await_proposal_feedback before trusting it". These tests are that
/// check, run every time instead of once.
void main() {
  late ServerDatabase db;
  late ProposalFeedbackBus bus;

  setUp(() async {
    db = ServerDatabase.inMemory();
    await db.customStatement('SELECT 1');
    bus = ProposalFeedbackBus();
  });

  tearDown(() async {
    await bus.close();
    await db.close();
  });

  TfcMcpServer createServer({ProposalFeedbackBus? feedbackBus}) {
    return TfcMcpServer(
      database: db,
      stateReader: MockStateReader(),
      alarmReader: MockAlarmReader(),
      feedbackBus: feedbackBus,
    );
  }

  const method = 'notifications/tfc/proposal_feedback';

  Map<String, dynamic> publishAccept(ProposalFeedbackBus b) => b.publish(
        action: 'accepted',
        summary: 'Accepted 1 asset update proposal: '
            '"CVS02.CN01.PX01.Fault: server_alias -> st201".',
        proposals: [
          {
            'title': 'CVS02.CN01.PX01.Fault: server_alias -> st201',
            'type': 'asset_update',
            'op': 'update',
          },
        ],
      );

  test('a decision reaches a connected client as a notification', () async {
    final client = await MockMcpClient.connect(createServer(feedbackBus: bus)
        .mcpServer);
    addTearDown(client.close);

    final published = publishAccept(bus);
    final notification = await client.nextNotification(method);

    expect(notification.method, method);
    final params = notification.params!;
    expect(params['action'], 'accepted');
    expect(params['seq'], published['seq']);
    expect(params['count'], 1);
    expect(params['summary'], contains('server_alias -> st201'),
        reason: 'the summary is the whole point of the payload -- a client '
            'that receives an empty one learned nothing');
    expect((params['proposals'] as List).single,
        containsPair('title', 'CVS02.CN01.PX01.Fault: server_alias -> st201'));
  });

  test('the payload is exactly what the bus stored', () async {
    // No second rendering of the entry on the way out. If these ever diverge,
    // a client polling get_proposal_feedback and a client listening for the
    // notification see different accounts of the same decision.
    final client = await MockMcpClient.connect(createServer(feedbackBus: bus)
        .mcpServer);
    addTearDown(client.close);

    final published = publishAccept(bus);
    final params = (await client.nextNotification(method)).params!;

    for (final key in published.keys) {
      expect(params[key], published[key], reason: 'field "$key" differs');
    }
  });

  test('every decision arrives, in order', () async {
    final client = await MockMcpClient.connect(createServer(feedbackBus: bus)
        .mcpServer);
    addTearDown(client.close);

    for (var i = 0; i < 3; i++) {
      bus.publish(action: 'accepted', summary: 'decision $i');
    }
    // Wait for the last one, then look at what accumulated.
    await client.nextNotification(method);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final feedback =
        client.notifications.where((n) => n.method == method).toList();
    expect(feedback, hasLength(3),
        reason: 'a dropped decision is silent: the client simply never '
            'learns the operator answered');
    expect([for (final n in feedback) n.params!['summary']],
        ['decision 0', 'decision 1', 'decision 2']);
    expect([for (final n in feedback) n.params!['seq']], [1, 2, 3]);
  });

  test('two sessions each get their own copy', () async {
    // One TfcMcpServer per HTTP session, all sharing the app's single bus.
    // A broadcast stream that only fed the first subscriber would leave every
    // client but one in the dark.
    final a = await MockMcpClient.connect(createServer(feedbackBus: bus)
        .mcpServer);
    final b = await MockMcpClient.connect(createServer(feedbackBus: bus)
        .mcpServer);
    addTearDown(a.close);
    addTearDown(b.close);

    publishAccept(bus);

    expect((await a.nextNotification(method)).params!['action'], 'accepted');
    expect((await b.nextNotification(method)).params!['action'], 'accepted');
  });

  test('a server built without a bus simply sends nothing', () async {
    // The feedback bus is optional -- a stdio server started by a CLI has no
    // app behind it. That path must not throw, it must just be quiet.
    final client = await MockMcpClient.connect(createServer().mcpServer);
    addTearDown(client.close);

    publishAccept(bus);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.notifications.where((n) => n.method == method), isEmpty);
  });

  test('closing a session cancels its subscription to the bus', () async {
    // Asserted on the bus, not on the client. Watching the client receive
    // nothing proves nothing here: the sender is guarded by
    // `_mcpServer.isConnected`, so a closed session is silent whether or not
    // the subscription was ever cancelled. Deleting the cancel and watching
    // this test still pass is how that was found.
    //
    // The leak matters because the bus outlives every session -- one listener
    // per client that ever connected, never reclaimed.
    final client = await MockMcpClient.connect(createServer(feedbackBus: bus)
        .mcpServer);
    expect(bus.hasListeners, isTrue,
        reason: 'the session never subscribed, so this test proves nothing');

    await client.close();
    // onclose runs through the transport's teardown, not synchronously.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bus.hasListeners, isFalse,
        reason: 'the session closed without cancelling its bus subscription');

    // And the publish itself must not throw into the closed session.
    expect(() => publishAccept(bus), returnsNormally);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(client.notifications.where((n) => n.method == method), isEmpty);
  });
}
