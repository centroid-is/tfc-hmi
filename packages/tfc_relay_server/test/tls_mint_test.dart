/// The certificate minter, judged at the DER tag rather than at the text.
///
/// 06-RESEARCH §B.2 measured the reason this code exists at all. `basic_utils`
/// — the library this repo already ships, and the one CONTEXT amendment 5
/// named — encodes *every* subject-alternative name as a dNSName
/// (`X509Utils.dart:480-484`, `ASN1PrintableString(stringValue: s, tag: 0x82)`),
/// so a leaf provisioned for `10.104.29.71` carries the literal DNS *string*
/// "10.104.29.71", and a panel dialling that IP literal is answered
/// `CERTIFICATE_VERIFY_FAILED`. The panels dial IPs — ST101/ST201/ST301 are
/// addresses, not names. So the certificate bytes are ours.
///
/// Every case below reads the DER tag byte and never the rendered text: tag
/// `0x82` carrying the characters `127.0.0.1` is *precisely* what the broken
/// encoding produces, so a string comparison passes on the bug. The hostname
/// case is here so a "cleanup" that unifies the two branches the other way —
/// everything an iPAddress — cannot pass either. Between them the two cases
/// pin the branch, which is the whole of the finding (trap 12).
///
/// Without this file, the next person who tidies `_generalName` ships a leaf
/// that works on their laptop (`wss://localhost`) and fails on every panel in
/// the plant, with an error message identical to a wrong CA and to an expired
/// certificate (trap 16).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asn1.dart';
import 'package:test/test.dart';
import 'package:tfc_relay_server/src/tls/mint.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart' as barrel;

/// `id-ce-keyUsage`, `id-ce-basicConstraints`, `id-ce-subjectAltName`,
/// `id-ce-extKeyUsage` — spelled as the numbers a DER dump shows, because a
/// symbolic name resolved through the same library that writes the extension
/// would agree with any mistake it made.
const _keyUsage = '2.5.29.15';
const _basicConstraints = '2.5.29.19';
const _subjectAltName = '2.5.29.17';
const _extKeyUsage = '2.5.29.37';

/// The tbsCertificate of [pem], parsed.
ASN1Sequence _tbsOf(String pem) {
  final der = CryptoUtils.getBytesFromPEMString(pem);
  final cert = ASN1Parser(der).nextObject() as ASN1Sequence;
  return cert.elements!.first as ASN1Sequence;
}

/// The DER value octets of the extension carrying [oid], or `null` when the
/// certificate does not carry that extension at all.
Uint8List? _extensionOctets(String pem, String oid) {
  final tagged = _tbsOf(pem).elements!.where((e) => e.tag == 0xA3);
  if (tagged.isEmpty) return null;
  final exts = ASN1Parser(tagged.first.valueBytes).nextObject() as ASN1Sequence;
  for (final ext in exts.elements!.cast<ASN1Sequence>()) {
    final id = ext.elements!.first as ASN1ObjectIdentifier;
    if (id.objectIdentifierAsString == oid) {
      return (ext.elements!.last as ASN1OctetString).octets;
    }
  }
  return null;
}

/// The GeneralName entries of the subjectAltName extension, untouched: the
/// tag byte as written and the value octets as written.
List<({int tag, Uint8List value})> _subjectAltNames(String pem) {
  final octets = _extensionOctets(pem, _subjectAltName);
  if (octets == null) return const [];
  final names = ASN1Parser(octets).nextObject() as ASN1Sequence;
  return [
    for (final n in names.elements!) (tag: n.tag!, value: n.valueBytes!),
  ];
}

/// The serial number as the certificate carries it.
BigInt _serialOf(String pem) =>
    (_tbsOf(pem).elements![1] as ASN1Integer).integer!;

void main() {
  late RelayKeyPair caKeys;
  late RelayKeyPair leafKeys;
  late DateTime now;
  const caDn = {'CN': 'Relay Test CA', 'O': 'Centroid'};
  const leafDn = {'CN': 'relay-gateway', 'O': 'Centroid'};

  // ~180 ms apiece (06-RESEARCH §B.3), which is why the keys are generated
  // once for the file and every case mints from them at ~15 ms.
  setUpAll(() {
    caKeys = generateKeyPair();
    leafKeys = generateKeyPair();
    now = DateTime.now().toUtc();
  });

  String mintLeafWith({
    List<String> sans = const ['localhost', '127.0.0.1'],
    BigInt? serial,
  }) =>
      mintCertificate(
        signingKey: caKeys.privateKey,
        issuer: caDn,
        subject: leafDn,
        subjectPublicKey: leafKeys.publicKey,
        sans: sans,
        notBefore: now.subtract(const Duration(days: 1)),
        notAfter: now.add(const Duration(days: 365)),
        serial: serial,
      );

  String mintRoot() => mintCertificate(
        signingKey: caKeys.privateKey,
        issuer: caDn,
        subject: caDn,
        subjectPublicKey: caKeys.publicKey,
        sans: const [],
        notBefore: now.subtract(const Duration(days: 1)),
        notAfter: now.add(const Duration(days: 3650)),
        ca: true,
      );

  group('subject-alternative names', () {
    test('an IP subject-alternative name is an iPAddress, not a DNS string',
        () {
      final sans = _subjectAltNames(mintLeafWith(sans: const ['127.0.0.1']));

      expect(sans, hasLength(1));
      expect(sans.single.tag, 0x87,
          reason: 'a panel dialling wss://10.104.x.x is answered '
              'CERTIFICATE_VERIFY_FAILED unless the address is a real '
              'iPAddress GeneralName; tag 0x82 here is the basic_utils defect '
              'shipped verbatim');
      expect(sans.single.value, Uint8List.fromList([127, 0, 0, 1]),
          reason: 'an iPAddress carries the four raw address octets — the '
              'ASCII text "127.0.0.1" is exactly what the broken encoding '
              'writes, so it must not be what passes here');
    });

    test('a hostname subject-alternative name is a dNSName', () {
      final sans = _subjectAltNames(mintLeafWith(sans: const ['localhost']));

      expect(sans, hasLength(1));
      expect(sans.single.tag, 0x82,
          reason: 'unifying the two GeneralName branches into iPAddress would '
              'fix the IP dial and break every hostname dial — a developer '
              'laptop on wss://localhost stops connecting');
      expect(ascii.decode(sans.single.value), 'localhost');
    });

    test('a leaf carries both name kinds in the order asked for', () {
      final sans = _subjectAltNames(
          mintLeafWith(sans: const ['localhost', '127.0.0.1', '10.104.29.71']));

      expect(sans.map((s) => s.tag), [0x82, 0x87, 0x87],
          reason: 'one leaf serves the developer by name and the plant by '
              'address; a minter that can only do one of them means two '
              'certificates to keep in step');
      expect(sans[2].value, Uint8List.fromList([10, 104, 29, 71]));
    });
  });

  group('serial numbers', () {
    test('two leaves from one CA never share a serial', () {
      final first = _serialOf(mintLeafWith());
      final second = _serialOf(mintLeafWith());

      expect(first, isNot(second),
          reason: 'two certificates from one issuer sharing a serial is a '
              'chain-building failure — a verifier is entitled to treat the '
              'second as the first, and one leaf on a test bench never shows '
              'it');
      expect(first > BigInt.zero, isTrue,
          reason: 'a negative or zero serial is malformed; some stacks refuse '
              'the certificate outright');
      expect(first < (BigInt.one << 64), isTrue,
          reason: 'the serial stays inside 64 bits, so a DER dump on a plant '
              'machine is readable rather than a 40-digit wall');
    });

    test('an explicit serial is what the certificate carries', () {
      final wanted = BigInt.from(0x0DEFACED);

      expect(_serialOf(mintLeafWith(serial: wanted)), wanted,
          reason: 'an integrator re-issuing a leaf must be able to pin the '
              'serial their CRL or inventory already names');
    });
  });

  group('extensions', () {
    test('the root declares CA:TRUE and a leaf does not', () {
      final rootOctets = _extensionOctets(mintRoot(), _basicConstraints);
      final leafOctets = _extensionOctets(mintLeafWith(), _basicConstraints);

      final root = ASN1Parser(rootOctets).nextObject() as ASN1Sequence;
      expect((root.elements!.first as ASN1Boolean).boolValue, isTrue,
          reason: 'without CA:TRUE on the root no chain builds and every '
              'panel refuses the gateway');

      if (leafOctets != null) {
        final leaf = ASN1Parser(leafOctets).nextObject() as ASN1Sequence;
        final asserted = leaf.elements!.isEmpty
            ? false
            : (leaf.elements!.first as ASN1Boolean).boolValue;
        expect(asserted, isFalse,
            reason: 'a leaf that asserts CA:TRUE can sign for any name in the '
                'plant — the gateway key becomes a second certificate '
                'authority nobody provisioned');
      }
    });

    test('a leaf declares extendedKeyUsage serverAuth', () {
      final octets = _extensionOctets(mintLeafWith(), _extKeyUsage);
      expect(octets, isNotNull,
          reason: 'BoringSSL does not check EKU here today, and "it did not '
              'check today" is not a property to build a plant on — every '
              'other TLS stack on site expects it (§B.1)');

      final eku = ASN1Parser(octets).nextObject() as ASN1Sequence;
      expect(
          eku.elements!
              .cast<ASN1ObjectIdentifier>()
              .map((o) => o.objectIdentifierAsString),
          contains('1.3.6.1.5.5.7.3.1'));
    });

    test('both the root and a leaf declare a keyUsage', () {
      for (final entry in {'root': mintRoot(), 'leaf': mintLeafWith()}.entries) {
        final octets = _extensionOctets(entry.value, _keyUsage);
        expect(octets, isNotNull,
            reason: 'the ${entry.key} without keyUsage is a certificate a '
                'stricter stack than BoringSSL may refuse, and the plant runs '
                'more than one stack');
        final bits = ASN1Parser(octets).nextObject() as ASN1BitString;
        expect(bits.stringValues, isNotEmpty);
      }
    });
  });

  group('round trip', () {
    test('a minted leaf parses back with the validity it was asked for', () {
      final wanted = DateTime.utc(now.year + 1, now.month, now.day, 11, 22, 33);
      final pem = mintCertificate(
        signingKey: caKeys.privateKey,
        issuer: caDn,
        subject: leafDn,
        subjectPublicKey: leafKeys.publicKey,
        sans: const ['localhost'],
        notBefore: now.subtract(const Duration(days: 1)),
        notAfter: wanted,
      );

      // `validity` is non-nullable while `tbsCertificate` is nullable, and the
      // SAN accessor beside it is misspelled `subjectAlternativNames` upstream
      // (trap 14) — read the field that is spelled right.
      final parsed = X509Utils.x509CertificateFromPem(pem);
      expect(parsed.tbsCertificate!.validity.notAfter.toUtc(), wanted,
          reason: 'the cert-expiry health key counts days from this field; if '
              'the minter rounds it, the 30-day alarm fires on the wrong '
              'Tuesday');
    });

    test('the barrel exports the minting helper', () {
      expect(barrel.mintCertificate, isA<Function>(),
          reason: 'provisioning is something an embedder does, and 06-05 mints '
              'client-side fixtures against this same function rather than '
              "reaching into another package's src/");
      expect(barrel.generateKeyPair, isA<Function>());
    });
  });
}
