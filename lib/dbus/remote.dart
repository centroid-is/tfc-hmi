import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:dartssh2/dartssh2.dart';

Future<DBusClient> connectRemoteSystemBus({
  required String remoteHost,
  required String sshUser,
  String? sshPassword, // Optional password
  String? sshPrivateKeyPath, // Optional path to SSH private key
  String? sshPrivateKeyPassphrase, // Optional passphrase for the SSH key
  int remotePort = 22,
  int localPort = 7272,
}) async {
  // Validate that either password or key is provided
  if (sshPassword == null && sshPrivateKeyPath == null) {
    throw ArgumentError(
        'Either sshPassword or sshPrivateKeyPath must be provided.');
  }

  // 1) Set up the SSH session to run systemd-stdio-bridge on the remote
  final sshSocket = await SSHSocket.connect(remoteHost, remotePort);

  final SSHClient client;
  try {
    // Prepare identities (private keys) if provided
    List<SSHKeyPair>? identities;
    if (sshPrivateKeyPath != null) {
      final keyPairs = await loadPrivateKey(
        sshPrivateKeyPath,
        passphrase: sshPrivateKeyPassphrase,
      );
      identities = keyPairs;
    }

    client = SSHClient(
      sshSocket,
      username: sshUser,
      identities: identities, // Provide identities if using key auth
      onPasswordRequest: sshPassword != null
          ? () => sshPassword
          : null, // Provide password if available
      onVerifyHostKey: (host, key) => true, // ⚠️ Implement proper verification!
      onAuthenticated: () {
        print('SSH authentication successful.');
      },
    );

    await client.authenticated; // Wait for authentication to complete
  } catch (e) {
    await sshSocket.close();
    throw Exception('SSH connection failed: ${e.toString()}');
  }

  // 2) Start the TCP server that will accept a single D-Bus client connection
  final server = await ServerSocket.bind('127.0.0.1', localPort);
  print('Listening locally on ${server.address.address}:${server.port}');

  // Start an SSH session that runs "systemd-stdio-bridge"
  final uidSession = await client.execute('id -u');
  final uid = String.fromCharCodes(await uidSession.stdout.first).trim();
  final session = await client.execute('systemd-stdio-bridge');
  print('SSH session started: systemd-stdio-bridge on $remoteHost');

  // 3) Create the DBusClient first
  final dbusAddress = DBusAddress.tcp('127.0.0.1', port: localPort);
  final dbusAuth = DBusAuthClient(uid: uid);
  final dbusClient = DBusClient(dbusAddress, authClient: dbusAuth);
  print(
      'DBusClient created. Will connect to tcp:host=127.0.0.1,port=$localPort');

  // 4) Set up a future for the client connection
  final serverSideSocketFuture = server.first;

  // 5) Make the D-Bus call which will trigger the connection
  print('Attempting D-Bus call: ListNames on org.freedesktop.DBus...');
  final dbusCallFuture = dbusClient.callMethod(
    destination: 'org.freedesktop.DBus',
    path: DBusObjectPath('/org/freedesktop/DBus'),
    interface: 'org.freedesktop.DBus',
    name: 'ListNames',
    replySignature: DBusSignature('as'),
  );

  // 6) Wait for the client to connect
  print('Waiting for client socket connection...');
  final serverSideSocket = await serverSideSocketFuture;
  print('Client connected to local port ${serverSideSocket.port}');

  // 7) Set up the pipes between local socket and SSH session
  serverSideSocket.pipe(session.stdin);
  session.stdout.cast<List<int>>().pipe(serverSideSocket);

  // 8) Now wait for the D-Bus call to complete
  await dbusCallFuture;
  print('D-Bus connection established successfully');

  return dbusClient;
}

/// Loads an SSH private key from a PEM file.
///
/// [path] is the file path to the private key.
/// [passphrase] is optional and used if the key is encrypted.
Future<List<SSHKeyPair>> loadPrivateKey(String path,
    {String? passphrase}) async {
  final keyFile = File(path);
  if (!await keyFile.exists()) {
    throw Exception('Private key file not found at path: $path');
  }

  final keyContent = await keyFile.readAsString();

  // Parse the private key and return the first key
  final privateKeys = SSHKeyPair.fromPem(keyContent, passphrase);
  return privateKeys;
}
