import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:tfc_core/core/secure_storage/secure_storage.dart';

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
    BuildContext? dialogContext;
    try {
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
      return result;
    } catch (e) {
      logger.e('Error connecting to bus: $e');
      if (context.mounted) {
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

class LoginForm extends ConsumerStatefulWidget {
  final void Function(DBusClient) onLoginSuccess;
  final bool showLogo;
  final double? width;

  const LoginForm({
    super.key,
    required this.onLoginSuccess,
    this.showLogo = true,
    this.width,
  });

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  LoginCredentials? _currentCredentials;

  Future<void> _saveCredentials(LoginCredentials creds) async {
    logger.d('Saving credentials: $creds');
    final prefs = await SharedPreferences.getInstance();
    final secureStorage = SecureStorage.getInstance();

    await prefs.setString('connectionType', creds.type.name);
    await prefs.setString('host', creds.host ?? '');
    await prefs.setString('username', creds.username ?? '');
    await prefs.setBool('autoLogin', creds.autoLogin);
    await prefs.setString('sshPrivateKeyPath', creds.sshPrivateKeyPath ?? '');

    if (creds.password != null) {
      await secureStorage.write(key: 'dbus_password', value: creds.password!);
    }
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
      final secureStorage = SecureStorage.getInstance();
      logger.d('Reading password from secure storage');
      password = await secureStorage.read(key: 'dbus_password');
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
    return SizedBox(
      width: widget.width ?? 300,
      child: FutureBuilder<LoginCredentials>(
        future: _loadSavedCredentials(),
        builder: (context, savedCredsSnapshot) {
          // Wait for credentials to load
          if (!savedCredsSnapshot.hasData) {
            return const CircularProgressIndicator();
          }

          _currentCredentials ??= savedCredsSnapshot.data?.copyWith();

          final credentials = _currentCredentials!;

          final hostController = TextEditingController(text: credentials.host);
          final userController =
              TextEditingController(text: credentials.username);
          final passwordController =
              TextEditingController(text: credentials.password);

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.showLogo) ...[
                SvgPicture.asset(
                  'assets/centroid.svg',
                  height: 50,
                  package: 'tfc',
                  colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.onSurface, BlendMode.srcIn),
                ),
                const SizedBox(height: 32),
              ],
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
                future:
                    credentials.autoLogin && savedCredsSnapshot.data!.autoLogin
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
                              sshPrivateKeyPath: credentials.sshPrivateKeyPath,
                              autoLogin: credentials.autoLogin,
                            );
                            _saveCredentials(creds); // Fire and forget

                            final client = await creds.connect(context);
                            widget.onLoginSuccess(client);
                          },
                    child:
                        loginSnapshot.connectionState == ConnectionState.waiting
                            ? const CircularProgressIndicator()
                            : const Text('Login'),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class LoginApp extends ConsumerWidget {
  final void Function(DBusClient) onLoginSuccess;

  const LoginApp({super.key, required this.onLoginSuccess});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeNotifierProvider);
    final (light, dark) = solarized();
    final themeMode = themeAsync.when(
      data: (themeMode) => themeMode,
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

class LoginPage extends ConsumerWidget {
  final void Function(DBusClient) onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: LoginForm(
          onLoginSuccess: onLoginSuccess,
          showLogo: true,
        ),
      ),
    );
  }
}
