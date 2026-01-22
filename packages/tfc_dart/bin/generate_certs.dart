import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:basic_utils/basic_utils.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('cn', abbr: 'c', help: 'Common Name', defaultsTo: 'OPC-UA-Client')
    ..addOption('org', abbr: 'o', help: 'Organization', defaultsTo: 'Centroid')
    ..addOption('country', help: 'Country code', defaultsTo: 'IS')
    ..addOption('state', help: 'State/Province', defaultsTo: 'Hofudborgarsvaedid')
    ..addOption('locality', abbr: 'l', help: 'City/Locality', defaultsTo: 'Hafnarfjordur')
    ..addOption('days', abbr: 'd', help: 'Validity in days', defaultsTo: '3650')
    ..addFlag('pem', help: 'Output PEM format instead of JSON', defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  final results = parser.parse(args);

  if (results['help'] as bool) {
    print('Generate OPC-UA client certificates\n');
    print('Usage: dart run bin/generate_certs.dart [options]\n');
    print(parser.usage);
    exit(0);
  }

  final commonName = results['cn'] as String;
  final organization = results['org'] as String;
  final country = results['country'] as String;
  final state = results['state'] as String;
  final locality = results['locality'] as String;
  final validityDays = int.tryParse(results['days'] as String) ?? 3650;
  final outputPem = results['pem'] as bool;

  try {
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);

    final attributes = {
      'CN': commonName,
      'O': organization,
      'OU': 'OPC-UA',
      'C': country,
      'ST': state,
      'L': locality,
    };

    final csr = X509Utils.generateRsaCsrPem(
      attributes,
      keyPair.privateKey as RSAPrivateKey,
      keyPair.publicKey as RSAPublicKey,
      san: ['localhost', '127.0.0.1'],
    );

    final certPem = X509Utils.generateSelfSignedCertificate(
      keyPair.privateKey as RSAPrivateKey,
      csr,
      validityDays,
      sans: ['localhost', '127.0.0.1'],
    );

    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
        keyPair.privateKey as RSAPrivateKey);

    if (outputPem) {
      print('=== CERTIFICATE ===');
      print(certPem);
      print('=== PRIVATE KEY ===');
      print(keyPem);
    } else {
      final certBase64 = base64Encode(Uint8List.fromList(utf8.encode(certPem)));
      final keyBase64 = base64Encode(Uint8List.fromList(utf8.encode(keyPem)));
      const encoder = JsonEncoder.withIndent('  ');
      print(encoder.convert({'ssl_cert': certBase64, 'ssl_key': keyBase64}));
    }
  } catch (e, st) {
    stderr.writeln('Error: $e\n$st');
    exit(1);
  }
}
