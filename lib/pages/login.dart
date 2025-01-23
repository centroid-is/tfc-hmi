import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:tfc_hmi/dbus/remote.dart';
import 'package:tfc_hmi/theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum ConnectionType { system, remote }

class LoginCredentials {
  ConnectionType type;
  String? host;
  String? username;
  String? password;
  bool autoLogin;

  LoginCredentials({
    required this.type,
    this.host,
    this.username,
    this.password,
    this.autoLogin = false,
  });

  LoginCredentials copyWith({
    ConnectionType? type,
    String? host,
    String? username,
    String? password,
    bool? autoLogin,
  }) {
    return LoginCredentials(
      type: type ?? this.type,
      host: host ?? this.host,
      username: username ?? this.username,
      password: password ?? this.password,
      autoLogin: autoLogin ?? this.autoLogin,
    );
  }

  @override
  String toString() {
    final maskedPassword = password?.replaceAll(RegExp(r'.'), '*');
    return 'LoginCredentials(type: $type, host: $host, username: $username, password: $maskedPassword, autoLogin: $autoLogin)';
  }

  Future<DBusClient> connect(BuildContext context) async {
    try {
      // wait for build to finish creating widgets before showing loading dialog, can occur during auto login
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Connecting...'),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      });

      final result = await (type == ConnectionType.system
          ? Future.value(DBusClient.system())
          : connectRemoteSystemBus(
              remoteHost: host!,
              sshUser: username!,
              sshPassword: password!,
            ));

      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return result;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connection Error'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      rethrow;
    }
  }
}

class LoginApp extends StatelessWidget {
  final void Function(DBusClient) onLoginSuccess;

  const LoginApp({super.key, required this.onLoginSuccess});

  @override
  Widget build(BuildContext context) {
    final (light, dark) = solarized();
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          title: 'Login',
          themeMode: themeNotifier.themeMode,
          theme: light,
          darkTheme: dark,
          home: LoginPage(onLoginSuccess: onLoginSuccess),
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  final void Function(DBusClient) onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  LoginCredentials? _currentCredentials;

  Future<void> _saveCredentials(LoginCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();

    await prefs.setString('connectionType', creds.type.name);
    await prefs.setString('host', creds.host ?? '');
    await prefs.setString('username', creds.username ?? '');
    await prefs.setBool('autoLogin', creds.autoLogin);

    if (creds.password != null) {
      await secureStorage.write(key: 'password', value: creds.password);
    }
  }

  Future<LoginCredentials> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();

    final type = ConnectionType.values.byName(
        prefs.getString('connectionType') ?? ConnectionType.remote.name);
    final host = prefs.getString('host');
    final username = prefs.getString('username');
    final password = await secureStorage.read(key: 'password');
    final autoLogin = prefs.getBool('autoLogin') ?? false;

    final credentials = LoginCredentials(
      type: type,
      host: host,
      username: username,
      password: password,
      autoLogin: autoLogin,
    );

    return credentials;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: FutureBuilder<LoginCredentials>(
            future: _loadSavedCredentials(),
            builder: (context, savedCredsSnapshot) {
              // Wait for credentials to load
              if (!savedCredsSnapshot.hasData) {
                return const CircularProgressIndicator();
              }

              _currentCredentials ??= savedCredsSnapshot.data?.copyWith();

              final credentials = _currentCredentials!;

              final hostController =
                  TextEditingController(text: credentials.host);
              final userController =
                  TextEditingController(text: credentials.username);
              final passwordController =
                  TextEditingController(text: credentials.password);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/centroid.svg',
                    height: 50,
                    package: 'tfc_hmi',
                    colorFilter: ColorFilter.mode(
                        Theme.of(context).colorScheme.onSurface,
                        BlendMode.srcIn),
                  ),
                  const SizedBox(height: 32),
                  SegmentedButton<ConnectionType>(
                    segments: const [
                      ButtonSegment(
                        value: ConnectionType.system,
                        label: Text('System DBus'),
                      ),
                      ButtonSegment(
                        value: ConnectionType.remote,
                        label: Text('Remote DBus'),
                      ),
                    ],
                    selected: {credentials.type},
                    onSelectionChanged: (Set<ConnectionType> selection) {
                      setState(() {
                        credentials.type = selection.first;
                      });
                    },
                  ),
                  if (credentials.type == ConnectionType.remote) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(labelText: 'Host'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                  ],
                  CheckboxListTile(
                    title: const Text('Auto Login'),
                    value: credentials.autoLogin,
                    onChanged: (value) {
                      setState(() {
                        credentials.autoLogin = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  FutureBuilder<DBusClient>(
                    future: credentials.autoLogin &&
                            savedCredsSnapshot.data!.autoLogin
                        ? credentials.connect(context)
                        : null,
                    builder: (context, loginSnapshot) {
                      if (loginSnapshot.hasData) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          widget.onLoginSuccess(loginSnapshot.data!);
                        });
                      }

                      return ElevatedButton(
                        onPressed: loginSnapshot.connectionState ==
                                ConnectionState.waiting
                            ? null
                            : () async {
                                final creds = LoginCredentials(
                                  type: credentials.type,
                                  host: hostController.text,
                                  username: userController.text,
                                  password: passwordController.text,
                                  autoLogin: credentials.autoLogin,
                                );
                                _saveCredentials(creds); // Fire and forget

                                final client = await creds.connect(context);
                                widget.onLoginSuccess(client);
                              },
                        child: loginSnapshot.connectionState ==
                                ConnectionState.waiting
                            ? const CircularProgressIndicator()
                            : const Text('Login'),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
