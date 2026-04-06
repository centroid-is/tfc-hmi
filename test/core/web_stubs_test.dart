import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Import stub files directly to verify their exported classes.
import 'package:tfc/pages/dbus_login_stub.dart';
import 'package:tfc/pages/ip_settings_stub.dart';
import 'package:tfc/pages/about_linux_stub.dart';
import 'package:tfc/pages/config_edit_stub.dart';
import 'package:tfc/pages/config_list_stub.dart';
import 'package:tfc/pages/ipc_connections_stub.dart';

void main() {
  group('Web stub pages', () {
    testWidgets('LoginForm stub renders placeholder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginForm(onLoginSuccess: (_) {})),
      );
      expect(find.text('Not available on web'), findsOneWidget);
    });

    testWidgets('IpSettingsPage stub renders placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: IpSettingsPage()),
      );
      expect(find.text('Not available on web'), findsOneWidget);
    });

    testWidgets('AboutLinuxPage stub renders placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AboutLinuxPage()),
      );
      expect(find.text('Not available on web'), findsOneWidget);
    });

    testWidgets('ConfigEditDialog stub renders placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConfigEditDialog(
            dbusClient: null,
            serviceName: '',
            objectPath: '',
          ),
        ),
      );
      expect(find.text('Not available on web'), findsOneWidget);
    });

    testWidgets('ConfigListPage stub renders placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ConfigListPage(dbusClient: null)),
      );
      expect(find.text('Not available on web'), findsOneWidget);
    });

    testWidgets('ConnectionsPage stub renders placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ConnectionsPage(dbusClient: null)),
      );
      expect(find.text('Not available on web'), findsOneWidget);
    });
  });
}
