import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:tfc_core/tfc_core.dart';
import 'package:postgres/postgres.dart' as pg;

/// TFC Configuration Tool - Simple TUI for configuring database and OPC UA servers
///
/// Usage:
///   dart run tfc_core:tfc_config

void main() async {
  print('═══════════════════════════════════════════════════════');
  print('TFC Configuration Tool');
  print('═══════════════════════════════════════════════════════');
  print('');

  final secureStorage = SecureStorage.getInstance();

  while (true) {
    print('Main Menu:');
    print('  1. Configure Database');
    print('  2. Configure OPC UA Servers');
    print('  3. View Current Configuration');
    print('  4. Test Database Connection');
    print('  5. Exit');
    print('');
    stdout.write('Select option [1-5]: ');
    final choice = stdin.readLineSync()?.trim();

    switch (choice) {
      case '1':
        await configurDatabase(secureStorage);
        break;
      case '2':
        await configureOpcUa(secureStorage);
        break;
      case '3':
        await viewConfiguration(secureStorage);
        break;
      case '4':
        await testDatabaseConnection(secureStorage);
        break;
      case '5':
        print('\nGoodbye!');
        return;
      default:
        print('\nInvalid option. Please try again.\n');
    }
  }
}

Future<void> configurDatabase(MySecureStorage storage) async {
  print('\n═══════════════════════════════════════════════════════');
  print('Database Configuration');
  print('═══════════════════════════════════════════════════════');
  print('');

  // Check for existing config
  final existing = await storage.read(key: 'database_config');
  if (existing != null) {
    print('Existing configuration found.');
    stdout.write('Overwrite? (y/N): ');
    final overwrite = stdin.readLineSync()?.trim().toLowerCase();
    if (overwrite != 'y' && overwrite != 'yes') {
      print('Cancelled.\n');
      return;
    }
  }

  print('Database Type:');
  print('  1. PostgreSQL');
  print('  2. SQLite (local)');
  stdout.write('Select [1-2]: ');
  final dbType = stdin.readLineSync()?.trim();

  DatabaseConfig config;

  if (dbType == '1') {
    // PostgreSQL configuration
    stdout.write('Host [localhost]: ');
    final host = stdin.readLineSync()?.trim();

    stdout.write('Port [5432]: ');
    final portStr = stdin.readLineSync()?.trim();
    final port = int.tryParse(portStr ?? '5432') ?? 5432;

    stdout.write('Database name [tfc]: ');
    final database = stdin.readLineSync()?.trim();

    stdout.write('Username [postgres]: ');
    final username = stdin.readLineSync()?.trim();

    stdout.write('Password: ');
    stdin.echoMode = false;
    final password = stdin.readLineSync()?.trim();
    stdin.echoMode = true;
    print('');

    stdout.write('Use SSL? (y/N): ');
    final useSsl = stdin.readLineSync()?.trim().toLowerCase();
    final sslMode = (useSsl == 'y' || useSsl == 'yes')
        ? pg.SslMode.require
        : pg.SslMode.disable;

    config = DatabaseConfig(
      postgres: pg.Endpoint(
        host: host?.isNotEmpty == true ? host! : 'localhost',
        port: port,
        database: database?.isNotEmpty == true ? database! : 'tfc',
        username: username?.isNotEmpty == true ? username! : 'postgres',
        password: password ?? '',
      ),
      sslMode: sslMode,
      debug: false,
    );
  } else {
    // SQLite (local)
    print('Using local SQLite database.');
    config = DatabaseConfig(
      postgres: null,
      debug: false,
    );
  }

  // Save to secure storage
  final configJson = jsonEncode(config.toJson());
  await storage.write(key: 'database_config', value: configJson);

  print('\n✓ Database configuration saved!\n');
}

Future<void> configureOpcUa(MySecureStorage storage) async {
  print('\n═══════════════════════════════════════════════════════');
  print('OPC UA Server Configuration');
  print('═══════════════════════════════════════════════════════');
  print('');

  // Check for existing config
  final existing = await storage.read(key: 'state_man_config');
  List<OpcUAConfig> servers = [];

  if (existing != null) {
    try {
      final existingConfig = StateManConfig.fromJson(jsonDecode(existing));
      servers = existingConfig.opcua;
      print('Found ${servers.length} existing server(s).');
    } catch (e) {
      print('Warning: Could not parse existing config: $e');
    }
  }

  while (true) {
    print('\nOPC UA Servers Menu:');
    print('  1. Add Server');
    print('  2. List Servers');
    print('  3. Remove Server');
    print('  4. Save and Return');
    stdout.write('Select [1-4]: ');
    final choice = stdin.readLineSync()?.trim();

    switch (choice) {
      case '1':
        final server = await addOpcUaServer();
        if (server != null) {
          servers.add(server);
          print('✓ Server added!\n');
        }
        break;
      case '2':
        listOpcUaServers(servers);
        break;
      case '3':
        await removeOpcUaServer(servers);
        break;
      case '4':
        if (servers.isEmpty) {
          print('\nWarning: No servers configured!');
          stdout.write('Save anyway? (y/N): ');
          final confirm = stdin.readLineSync()?.trim().toLowerCase();
          if (confirm != 'y' && confirm != 'yes') {
            continue;
          }
        }
        // Save configuration
        final config = StateManConfig(opcua: servers);
        final configJson = jsonEncode(config.toJson());
        await storage.write(key: 'state_man_config', value: configJson);
        print('\n✓ OPC UA configuration saved!\n');
        return;
      default:
        print('Invalid option.\n');
    }
  }
}

Future<OpcUAConfig?> addOpcUaServer() async {
  print('\n--- Add OPC UA Server ---');

  stdout.write('Server Alias (e.g., "plc1"): ');
  final alias = stdin.readLineSync()?.trim();
  if (alias == null || alias.isEmpty) {
    print('Error: Alias is required.');
    return null;
  }

  stdout.write('Endpoint URL (e.g., "opc.tcp://192.168.1.10:4840"): ');
  final endpoint = stdin.readLineSync()?.trim();
  if (endpoint == null || endpoint.isEmpty) {
    print('Error: Endpoint is required.');
    return null;
  }

  stdout.write('Use authentication? (y/N): ');
  final useAuth = stdin.readLineSync()?.trim().toLowerCase();

  String? username;
  String? password;
  if (useAuth == 'y' || useAuth == 'yes') {
    stdout.write('Username: ');
    username = stdin.readLineSync()?.trim();

    stdout.write('Password: ');
    stdin.echoMode = false;
    password = stdin.readLineSync()?.trim();
    stdin.echoMode = true;
    print('');
  }

  stdout.write('Use SSL/TLS? (y/N): ');
  final useSsl = stdin.readLineSync()?.trim().toLowerCase();

  Uint8List? sslCert;
  Uint8List? sslKey;
  if (useSsl == 'y' || useSsl == 'yes') {
    print('Note: Certificate configuration via TUI is limited.');
    print('For now, certificates will need to be configured via the Flutter UI.');
    // In a real implementation, you could prompt for file paths and load them
  }

  final config = OpcUAConfig()
    ..serverAlias = alias
    ..endpoint = endpoint
    ..username = username
    ..password = password
    ..sslCert = sslCert
    ..sslKey = sslKey;

  return config;
}

void listOpcUaServers(List<OpcUAConfig> servers) {
  print('\n--- OPC UA Servers ---');
  if (servers.isEmpty) {
    print('No servers configured.');
    return;
  }

  for (var i = 0; i < servers.length; i++) {
    final s = servers[i];
    print('${i + 1}. ${s.serverAlias}');
    print('   Endpoint: ${s.endpoint}');
    print('   Auth: ${s.username != null ? 'Yes (${s.username})' : 'No'}');
    print('   SSL: ${s.sslCert != null ? 'Yes' : 'No'}');
    print('');
  }
}

Future<void> removeOpcUaServer(List<OpcUAConfig> servers) async {
  if (servers.isEmpty) {
    print('\nNo servers to remove.');
    return;
  }

  listOpcUaServers(servers);
  stdout.write('Enter number to remove (or 0 to cancel): ');
  final numStr = stdin.readLineSync()?.trim();
  final num = int.tryParse(numStr ?? '');

  if (num == null || num < 1 || num > servers.length) {
    print('Cancelled.');
    return;
  }

  final removed = servers.removeAt(num - 1);
  print('✓ Removed server: ${removed.serverAlias}');
}

Future<void> viewConfiguration(MySecureStorage storage) async {
  print('\n═══════════════════════════════════════════════════════');
  print('Current Configuration');
  print('═══════════════════════════════════════════════════════');
  print('');

  // Database config
  print('Database:');
  final dbConfigJson = await storage.read(key: 'database_config');
  if (dbConfigJson != null) {
    try {
      final dbConfig = DatabaseConfig.fromJson(jsonDecode(dbConfigJson));
      if (dbConfig.postgres != null) {
        print('  Type: PostgreSQL');
        print('  Host: ${dbConfig.postgres!.host}:${dbConfig.postgres!.port}');
        print('  Database: ${dbConfig.postgres!.database}');
        print('  Username: ${dbConfig.postgres!.username}');
        print('  SSL: ${dbConfig.sslMode}');
      } else {
        print('  Type: SQLite (local)');
      }
    } catch (e) {
      print('  Error: Could not parse config: $e');
    }
  } else {
    print('  Not configured');
  }

  print('');

  // OPC UA config
  print('OPC UA Servers:');
  final stateManConfigJson = await storage.read(key: 'state_man_config');
  if (stateManConfigJson != null) {
    try {
      final stateManConfig = StateManConfig.fromJson(jsonDecode(stateManConfigJson));
      if (stateManConfig.opcua.isEmpty) {
        print('  No servers configured');
      } else {
        for (var i = 0; i < stateManConfig.opcua.length; i++) {
          final s = stateManConfig.opcua[i];
          print('  ${i + 1}. ${s.serverAlias} - ${s.endpoint}');
        }
      }
    } catch (e) {
      print('  Error: Could not parse config: $e');
    }
  } else {
    print('  Not configured');
  }

  print('');
}

Future<void> testDatabaseConnection(MySecureStorage storage) async {
  print('\n═══════════════════════════════════════════════════════');
  print('Test Database Connection');
  print('═══════════════════════════════════════════════════════');
  print('');

  final dbConfigJson = await storage.read(key: 'database_config');
  if (dbConfigJson == null) {
    print('Error: No database configuration found.');
    print('Please configure database first (option 1).\n');
    return;
  }

  try {
    final dbConfig = DatabaseConfig.fromJson(jsonDecode(dbConfigJson));
    print('Connecting to database...');

    final appDb = await AppDatabase.spawn(dbConfig);
    await appDb.open();

    print('Running test query...');
    await appDb.customSelect('SELECT 1').get();

    await appDb.close();

    print('✓ Connection successful!\n');
  } catch (e) {
    print('✗ Connection failed: $e\n');
  }
}
