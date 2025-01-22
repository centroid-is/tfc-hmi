import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tfc_hmi/dbus/remote.dart';

enum ConnectionType { system, remote }

class LoginCredentials {
  final ConnectionType type;
  final String? host;
  final String? username;
  final String? password;
  final bool autoLogin;

  LoginCredentials({
    required this.type,
    this.host,
    this.username,
    this.password,
    this.autoLogin = false,
  });

  Future<DBusClient> connect() {
    return type == ConnectionType.system
        ? Future.value(DBusClient.system())
        : connectRemoteSystemBus(
            remoteHost: host!,
            sshUser: username!,
            sshPassword: password!,
          );
  }
}

class LoginApp extends StatelessWidget {
  final void Function(DBusClient client) onLoginSuccess;

  const LoginApp({super.key, required this.onLoginSuccess});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LoginPage(onLoginSuccess: onLoginSuccess),
    );
  }
}

class LoginPage extends StatefulWidget {
  final void Function(DBusClient client) onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Future<LoginCredentials>? _savedCredentialsFuture;
  Future<DBusClient>? _loginFuture;

  @override
  void initState() {
    super.initState();
    _savedCredentialsFuture = _loadSavedCredentials();
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

    // Attempt auto-login if enabled
    if (autoLogin) {
      _loginFuture = credentials.connect();
    }

    return credentials;
  }

  Future<void> _saveCredentials(LoginCredentials creds) async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();

    await prefs.setString('connectionType', creds.type.name);
    await prefs.setBool('autoLogin', creds.autoLogin);

    if (creds.type == ConnectionType.remote) {
      await prefs.setString('host', creds.host ?? '');
      await prefs.setString('username', creds.username ?? '');
      await secureStorage.write(key: 'password', value: creds.password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: FutureBuilder<LoginCredentials>(
            future: _savedCredentialsFuture,
            builder: (context, savedCredsSnapshot) {
              final credentials = savedCredsSnapshot.data ??
                  LoginCredentials(type: ConnectionType.remote);

              final hostController =
                  TextEditingController(text: credentials.host);
              final userController =
                  TextEditingController(text: credentials.username);
              final passwordController =
                  TextEditingController(text: credentials.password);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                      _savedCredentialsFuture = Future.value(LoginCredentials(
                        type: selection.first,
                        autoLogin: credentials.autoLogin,
                      ));
                      setState(() {});
                    },
                  ),
                  if (credentials.type == ConnectionType.remote) ...[
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(labelText: 'Host'),
                    ),
                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FutureBuilder<DBusClient>(
                    future: _loginFuture,
                    builder: (context, loginSnapshot) {
                      if (loginSnapshot.hasError) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('Login failed: ${loginSnapshot.error}'),
                            ),
                          );
                        });
                      }

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
                                await _saveCredentials(creds);
                                final loginFuture = creds.connect();
                                setState(() => _loginFuture = loginFuture);
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
