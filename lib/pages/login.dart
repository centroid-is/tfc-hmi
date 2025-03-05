import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:path/path.dart' as path;
import '../dbus/remote.dart';
import '../theme.dart';
import '../providers/theme.dart';

final logger = Logger();

enum ConnectionType { system, remote }

class LoginCredentials {
  ConnectionType type;
  String? host;
  String? username;
  String? password;
  String? sshPrivateKeyPath;
  bool autoLogin;

  LoginCredentials({
    required this.type,
    this.host,
    this.username,
    this.password,
    this.sshPrivateKeyPath,
    this.autoLogin = false,
  });

  LoginCredentials copyWith({
    ConnectionType? type,
    String? host,
    String? username,
    String? password,
    String? sshPrivateKeyPath,
    bool? autoLogin,
  }) {
    return LoginCredentials(
      type: type ?? this.type,
      host: host ?? this.host,
      username: username ?? this.username,
      password: password ?? this.password,
      sshPrivateKeyPath: sshPrivateKeyPath ?? this.sshPrivateKeyPath,
      autoLogin: autoLogin ?? this.autoLogin,
    );
  }

  @override
  String toString() {
    final maskedPassword = password?.replaceAll(RegExp(r'.'), '*');
    return 'LoginCredentials(type: $type, host: $host, username: $username, password: $maskedPassword, sshPrivateKeyPath: $sshPrivateKeyPath, autoLogin: $autoLogin)';
  }

  Future<DBusClient> connect(BuildContext context) async {
    logger.d('Connecting to: $this');
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
                  sshPassword: sshPrivateKeyPath == null ? password : null,
                  sshPrivateKeyPath: sshPrivateKeyPath,
                  sshPrivateKeyPassphrase:
                      sshPrivateKeyPath != null ? password : null,
                ))
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException('Connection timed out after 10 seconds'),
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return result;
    } catch (e) {
      logger.e('Error connecting to bus: $e');
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

class LoginApp extends ConsumerWidget {
  final void Function(DBusClient) onLoginSuccess;

  const LoginApp({super.key, required this.onLoginSuccess});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use Riverpod to watch the asynchronous theme provider.
    final themeAsync = ref.watch(themeStateProvider);
    final (light, dark) = solarized();
    final themeMode = themeAsync.when(
      data: (themeNotifier) => themeNotifier.themeMode,
      loading: () => ThemeMode.system,
      error: (err, stack) => ThemeMode.system,
    );
    return MaterialApp(
      title: 'Login',
      themeMode: themeMode,
      theme: light,
      darkTheme: dark,
      home: LoginPage(onLoginSuccess: onLoginSuccess),
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
    logger.d('Saving credentials: $creds');
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();

    await prefs.setString('connectionType', creds.type.name);
    await prefs.setString('host', creds.host ?? '');
    await prefs.setString('username', creds.username ?? '');
    await prefs.setBool('autoLogin', creds.autoLogin);
    await prefs.setString('sshPrivateKeyPath', creds.sshPrivateKeyPath ?? '');

    await secureStorage.write(key: 'password', value: creds.password);
    logger.d('Saved credentials: $creds');
  }

  Future<LoginCredentials> _loadSavedCredentials() async {
    logger.d('Loading saved credentials');
    final prefs = await SharedPreferences.getInstance();

    logger.d('Loading saved credentials from prefs');
    final type = ConnectionType.values.byName(
        prefs.getString('connectionType') ?? ConnectionType.remote.name);
    final host = prefs.getString('host');
    final username = prefs.getString('username');
    final autoLogin = prefs.getBool('autoLogin') ?? false;
    final sshPrivateKeyPath = prefs.getString('sshPrivateKeyPath');

    // Currently read on FlutterSecureStorage is not working on eLinux
    // It just hangs indefinitely.
    String? password;
    if (username != null && username.isNotEmpty) {
      logger.d('Loading saved credentials from secure storage');
      const secureStorage = FlutterSecureStorage();
      logger.d('Reading password from secure storage');
      password = await secureStorage.read(key: 'password');
    }

    final credentials = LoginCredentials(
      type: type,
      host: host,
      username: username,
      password: password,
      sshPrivateKeyPath:
          sshPrivateKeyPath?.isNotEmpty == true ? sshPrivateKeyPath : null,
      autoLogin: autoLogin,
    );

    logger.d('Loaded credentials: $credentials');
    return credentials;
  }

  Future<void> _pickPrivateKey() async {
    logger.d('Picking private key');
    String? sshDir;

    if (!Platform.isAndroid && !Platform.isIOS) {
      // Desktop platforms only
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        sshDir = userProfile != null ? path.join(userProfile, '.ssh') : null;
      } else {
        final home = Platform.environment['HOME'];
        sshDir = home != null ? path.join(home, '.ssh') : null;
      }
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      initialDirectory: sshDir, // Will be ignored on mobile platforms
    );

    if (result != null) {
      logger.d('Picked private key: ${result.files.single.path}');
      setState(() {
        _currentCredentials = _currentCredentials!
            .copyWith(sshPrivateKeyPath: result.files.single.path);
      });
    }
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
                    package: 'tfc',
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
                      decoration: const InputDecoration(
                        labelText: 'Password',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Or use private key'),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _pickPrivateKey,
                          icon: const Icon(Icons.key),
                          tooltip: 'Select Private Key',
                        ),
                      ],
                    ),
                    if (credentials.sshPrivateKeyPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selected key: ${credentials.sshPrivateKeyPath!.split('/').last}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
                                  password: passwordController.text.isNotEmpty
                                      ? passwordController.text
                                      : null,
                                  sshPrivateKeyPath:
                                      credentials.sshPrivateKeyPath,
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
}
