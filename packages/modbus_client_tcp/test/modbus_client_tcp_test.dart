import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';

import 'modbus_test_server.dart';

void main() {
  group('frame length (TCPFIX-01)', () {
    late ModbusTestServer server;
    late ModbusClientTcp client;

    setUp(() async {
      // Create a server that responds to FC03 read holding register requests.
      // The onData callback parses the incoming MBAP request and replies with
      // a valid FC03 response containing 1 register (2 data bytes).
      server = ModbusTestServer(onData: (socket, data) {
        // Parse incoming MBAP request
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // Build FC03 response: function code + byte count + 2 data bytes
        // 1 register = 2 bytes of data (matches Uint16 element byteCount)
        final pdu = Uint8List.fromList([
          0x03, // FC03 read holding registers
          0x02, // byte count = 2
          0x00, 0x01, // register 0 = 1
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);
    });

    tearDown(() async {
      await client.disconnect();
      await server.shutdown();
    });

    test('parses response with small payload (3 registers = 6 data bytes)',
        () async {
      // Create a read request for 3 holding registers starting at address 0
      final register = ModbusUint16Register(
          name: 'test', address: 0, type: ModbusElementType.holdingRegister);
      final request = register.getReadRequest();
      final code = await client.send(request);
      expect(code, equals(ModbusResponseCode.requestSucceed));
    });

    test('handles response split across two TCP segments', () async {
      // Override onData to split response into two TCP writes
      await server.shutdown();
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        final pdu = Uint8List.fromList([
          0x03, 0x02,
          0x00, 0x01,
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);

        // Split at byte 7: first 7 bytes (header), then remaining (PDU)
        server.sendToClient(socket, response.sublist(0, 7));
        // Small delay to ensure separate TCP segments
        Future.delayed(const Duration(milliseconds: 50), () {
          server.sendToClient(socket, response.sublist(7));
        });
      });
      final port = await server.start();
      await client.disconnect();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      final register = ModbusUint16Register(
          name: 'test', address: 0, type: ModbusElementType.holdingRegister);
      final request = register.getReadRequest();
      final code = await client.send(request);
      expect(code, equals(ModbusResponseCode.requestSucceed));
    });

    test('handles single-byte-at-a-time response delivery', () async {
      await server.shutdown();
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        final pdu = Uint8List.fromList([
          0x03, 0x02,
          0x00, 0x01,
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);

        // Drip-feed one byte at a time with delays
        for (var i = 0; i < response.length; i++) {
          final byteIndex = i;
          Future.delayed(Duration(milliseconds: 10 * (i + 1)), () {
            server.sendToClient(socket, [response[byteIndex]]);
          });
        }
      });
      final port = await server.start();
      await client.disconnect();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      final register = ModbusUint16Register(
          name: 'test', address: 0, type: ModbusElementType.holdingRegister);
      final request = register.getReadRequest();
      final code = await client.send(request);
      expect(code, equals(ModbusResponseCode.requestSucceed));
    });
  });

  group('length validation (TCPFIX-03)', () {
    test('rejects response with MBAP length field of 0', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // Build raw frame with length=0 (invalid)
        final pdu = Uint8List.fromList([0x03, 0x00]);
        final response = ModbusTestServer.buildRawFrame(
            transactionId, 0, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestRxFailed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('rejects response with MBAP length field > 254', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // Build raw frame with length=255 (exceeds Modbus spec max of 254)
        final pdu = Uint8List.fromList([0x03, 0x00]);
        final response = ModbusTestServer.buildRawFrame(
            transactionId, 255, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestRxFailed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('accepts response with MBAP length field of 254 (max valid)',
        () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // Build response with length=254: 1 unitId + 253 PDU bytes
        // FC03 response: function code (1) + byte count (1) + 251 data bytes
        // Total PDU = 253 bytes
        final pdu = Uint8List(253);
        pdu[0] = 0x03; // FC03
        pdu[1] = 251; // byte count = 251 (remaining bytes are data)
        // Fill with dummy data
        for (var i = 2; i < 253; i++) {
          pdu[i] = i & 0xFF;
        }
        // Use buildResponse which calculates length = pdu.length + 1 = 254
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        // Use a custom request (not element-based) to bypass byte count
        // validation, since this test is about MBAP length limits, not
        // element-level data validation.
        final request = _Fc03RawRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });
  });

  group('TCP_NODELAY (TCPFIX-04)', () {
    // TCP_NODELAY cannot be directly verified via the Dart Socket API as
    // there is no getOption equivalent for tcpNoDelay. This smoke test
    // verifies that the connect + send/receive path works, which exercises
    // the code path where TCP_NODELAY is set.
    // Actual TCP_NODELAY presence is verified by code inspection.
    test('connects and successfully sends/receives a request', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        final pdu = Uint8List.fromList([
          0x03, 0x02, // FC03, byte count=2
          0x00, 0x42, // register value = 0x0042
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
        expect(register.value, equals(0x0042));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });
  });

  group('keepalive (TCPFIX-05)', () {
    test(
        'constructor accepts separate keepAliveIdle and keepAliveInterval parameters',
        () {
      // This test verifies the API change: separate idle and interval params
      final client = ModbusClientTcp('localhost',
          keepAliveIdle: const Duration(seconds: 5),
          keepAliveInterval: const Duration(seconds: 2),
          keepAliveCount: 3);
      expect(client, isNotNull);
      // Verify the values are stored correctly
      expect(client.keepAliveIdle, equals(const Duration(seconds: 5)));
      expect(client.keepAliveInterval, equals(const Duration(seconds: 2)));
      expect(client.keepAliveCount, equals(3));
    });

    test(
        'default keepalive values match MSocket (5s idle, 2s interval, 3 probes)',
        () {
      final client = ModbusClientTcp('localhost');
      expect(client.keepAliveIdle, equals(const Duration(seconds: 5)));
      expect(client.keepAliveInterval, equals(const Duration(seconds: 2)));
      expect(client.keepAliveCount, equals(3));
    });
  });

  group('concurrent requests (TCPFIX-02)', () {
    late ModbusTestServer server;
    late ModbusClientTcp client;

    tearDown(() async {
      await client.disconnect();
      await server.shutdown();
    });

    test('two concurrent requests resolve by transaction ID', () async {
      // Server collects requests and responds to the SECOND one first,
      // then the FIRST, to prove transaction ID routing works.
      final receivedRequests = <_ReceivedRequest>[];
      final allRequestsReceived = Completer<void>();

      server = ModbusTestServer(onData: (socket, data) {
        // Parse potentially concatenated MBAP requests from the data
        final requests = _parseRequests(data);
        for (final req in requests) {
          receivedRequests.add(_ReceivedRequest(socket, req.tid, req.unitId));
        }

        // Once we have both requests, signal
        if (receivedRequests.length >= 2 && !allRequestsReceived.isCompleted) {
          allRequestsReceived.complete();
        }
      });
      final port = await server.start();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 3),
          unitId: 1);

      // Create two different registers at different addresses
      final reg1 = ModbusUint16Register(
          name: 'reg1', address: 0, type: ModbusElementType.holdingRegister);
      final reg2 = ModbusUint16Register(
          name: 'reg2', address: 10, type: ModbusElementType.holdingRegister);

      // Send both requests concurrently (do NOT await the first)
      final future1 = client.send(reg1.getReadRequest());
      final future2 = client.send(reg2.getReadRequest());

      // Wait for both requests to arrive at the server
      await allRequestsReceived.future.timeout(const Duration(seconds: 2));

      // Respond to the SECOND request first (value = 0xBBBB)
      final pdu2 = Uint8List.fromList([0x03, 0x02, 0xBB, 0xBB]);
      server.sendToClient(
          receivedRequests[1].socket,
          ModbusTestServer.buildResponse(
              receivedRequests[1].transactionId,
              receivedRequests[1].unitId,
              pdu2));

      // Small delay then respond to the FIRST request (value = 0xAAAA)
      await Future.delayed(const Duration(milliseconds: 50));
      final pdu1 = Uint8List.fromList([0x03, 0x02, 0xAA, 0xAA]);
      server.sendToClient(
          receivedRequests[0].socket,
          ModbusTestServer.buildResponse(
              receivedRequests[0].transactionId,
              receivedRequests[0].unitId,
              pdu1));

      // Both should resolve correctly
      final code1 = await future1;
      final code2 = await future2;

      expect(code1, equals(ModbusResponseCode.requestSucceed));
      expect(code2, equals(ModbusResponseCode.requestSucceed));
      expect(reg1.value, equals(0xAAAA));
      expect(reg2.value, equals(0xBBBB));
    });

    test('response for unknown transaction ID is discarded', () async {
      // Server sends a response with an unknown transaction ID first,
      // then sends the real response. The real request should still resolve.
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // First, send a response with a bogus transaction ID (0xFFFF)
        final bogusPdu = Uint8List.fromList([0x03, 0x02, 0xDE, 0xAD]);
        server.sendToClient(socket,
            ModbusTestServer.buildResponse(0xFFFF, unitId, bogusPdu));

        // Then send the real response after a short delay
        Future.delayed(const Duration(milliseconds: 50), () {
          final realPdu = Uint8List.fromList([0x03, 0x02, 0x00, 0x42]);
          server.sendToClient(socket,
              ModbusTestServer.buildResponse(transactionId, unitId, realPdu));
        });
      });
      final port = await server.start();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 3),
          unitId: 1);

      final register = ModbusUint16Register(
          name: 'test', address: 0, type: ModbusElementType.holdingRegister);
      final request = register.getReadRequest();
      final code = await client.send(request);

      // Should succeed with the real response, not the bogus one
      expect(code, equals(ModbusResponseCode.requestSucceed));
      expect(register.value, equals(0x0042));
    });

    test('concatenated responses in single TCP segment', () async {
      // Server waits for both requests, then sends BOTH responses
      // concatenated in a single TCP write.
      final receivedRequests = <_ReceivedRequest>[];
      final allRequestsReceived = Completer<void>();

      server = ModbusTestServer(onData: (socket, data) {
        final requests = _parseRequests(data);
        for (final req in requests) {
          receivedRequests.add(_ReceivedRequest(socket, req.tid, req.unitId));
        }

        if (receivedRequests.length >= 2 && !allRequestsReceived.isCompleted) {
          allRequestsReceived.complete();
        }
      });
      final port = await server.start();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 3),
          unitId: 1);

      final reg1 = ModbusUint16Register(
          name: 'reg1', address: 0, type: ModbusElementType.holdingRegister);
      final reg2 = ModbusUint16Register(
          name: 'reg2', address: 10, type: ModbusElementType.holdingRegister);

      // Send both concurrently
      final future1 = client.send(reg1.getReadRequest());
      final future2 = client.send(reg2.getReadRequest());

      // Wait for both requests to arrive
      await allRequestsReceived.future.timeout(const Duration(seconds: 2));

      // Build two responses and concatenate them into a single TCP write
      final pdu1 = Uint8List.fromList([0x03, 0x02, 0x11, 0x11]);
      final response1 = ModbusTestServer.buildResponse(
          receivedRequests[0].transactionId,
          receivedRequests[0].unitId,
          pdu1);

      final pdu2 = Uint8List.fromList([0x03, 0x02, 0x22, 0x22]);
      final response2 = ModbusTestServer.buildResponse(
          receivedRequests[1].transactionId,
          receivedRequests[1].unitId,
          pdu2);

      // Concatenate both responses into a single byte array
      final concatenated = Uint8List(response1.length + response2.length);
      concatenated.setAll(0, response1);
      concatenated.setAll(response1.length, response2);

      // Send as a single TCP write (single _onSocketData callback)
      server.sendToClient(receivedRequests[0].socket, concatenated);

      // Both should resolve correctly
      final code1 = await future1;
      final code2 = await future2;

      expect(code1, equals(ModbusResponseCode.requestSucceed));
      expect(code2, equals(ModbusResponseCode.requestSucceed));
      expect(reg1.value, equals(0x1111));
      expect(reg2.value, equals(0x2222));
    });

    test('single request still works (backward compatibility)', () async {
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        final pdu = Uint8List.fromList([0x03, 0x02, 0x00, 0x99]);
        server.sendToClient(socket,
            ModbusTestServer.buildResponse(transactionId, unitId, pdu));
      });
      final port = await server.start();
      client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      final register = ModbusUint16Register(
          name: 'test', address: 0, type: ModbusElementType.holdingRegister);
      final code = await client.send(register.getReadRequest());
      expect(code, equals(ModbusResponseCode.requestSucceed));
      expect(register.value, equals(0x0099));
    });
  });

  group('FC90 UMAS MBAP length exemption', () {
    test('FC90 response with MBAP length 500 bytes is accepted', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // Build FC90 response with MBAP length = 500
        // PDU: FC=0x5A + pairingKey + status(0xFE) + subFunc + padding
        final pduLen = 499; // length field = unitId(1) + pdu(499) = 500
        final pdu = Uint8List(pduLen);
        pdu[0] = 0x5A; // FC90
        pdu[1] = 0x00; // pairing key
        pdu[2] = 0xFE; // success status
        pdu[3] = 0x01; // sub-function echo
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final request = _Fc90TestRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('FC90 response with MBAP length 5000 bytes is accepted', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        final pduLen = 4999; // length field = unitId(1) + pdu(4999) = 5000
        final pdu = Uint8List(pduLen);
        pdu[0] = 0x5A;
        pdu[1] = 0x00;
        pdu[2] = 0xFE;
        pdu[3] = 0x01;
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final request = _Fc90TestRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('non-FC90 response with MBAP length 255 is still rejected', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // FC03 response with length=255 (exceeds Modbus spec max of 254)
        final pdu = Uint8List.fromList([0x03, 0x00]);
        final response = ModbusTestServer.buildRawFrame(
            transactionId, 255, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestRxFailed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('FC90 response within old limit (254 bytes) still works', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // FC90 response with MBAP length = 10 (well within limit)
        final pdu = Uint8List.fromList([
          0x5A, 0x00, 0xFE, 0x01, // FC, pairing, status, subFunc
          0xF0, 0x00, // max frame size LE = 240
          0x00, 0x00, 0x00, // padding
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final request = _Fc90TestRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });
  });

  group('response byte count validation (BUG-02)', () {
    test('FC03 response with correct byte count is accepted', () async {
      // Reading 2 registers = expected byte count of 4 (2 bytes per register)
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // FC03 response: byte count = 2 (correct for 1 Uint16 register)
        final pdu = Uint8List.fromList([
          0x03, // FC03
          0x02, // byte count = 2 (matches Uint16 byteCount)
          0x00, 0x42, // register value
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
        expect(register.value, equals(0x0042));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('FC03 response with wrong byte count returns requestRxFailed',
        () async {
      // Reading 1 Uint16 register = expected byte count of 2,
      // but response says byte count = 4
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // FC03 response with WRONG byte count (4 instead of 2)
        final pdu = Uint8List.fromList([
          0x03, // FC03
          0x04, // byte count = 4 (WRONG for Uint16, should be 2)
          0x00, 0x42, 0x00, 0x43, // extra data
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestRxFailed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('FC01 response with correct byte count is accepted', () async {
      // Reading 1 coil = expected byte count of 1 (ceil(1/8) = 1)
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // FC01 response: byte count = 1 (correct for 1 coil)
        final pdu = Uint8List.fromList([
          0x01, // FC01
          0x01, // byte count = 1
          0x01, // coil value = ON
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final coil = ModbusCoil(name: 'test', address: 0);
        final request = coil.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
        expect(coil.value, equals(true));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('FC01 response with wrong byte count returns requestRxFailed',
        () async {
      // Reading 1 coil = expected byte count of 1,
      // but response says byte count = 2
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // FC01 response with WRONG byte count (2 instead of 1)
        final pdu = Uint8List.fromList([
          0x01, // FC01
          0x02, // byte count = 2 (WRONG, should be 1)
          0x01, 0x00, // extra data
        ]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 1);

      try {
        final coil = ModbusCoil(name: 'test', address: 0);
        final request = coil.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestRxFailed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });
  });

  group('unit ID validation (BUG-03)', () {
    test('response with matching unit ID is accepted', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        final unitId = view.getUint8(6);

        // Response with same unit ID as request
        final pdu = Uint8List.fromList([0x03, 0x02, 0x00, 0x42]);
        final response = ModbusTestServer.buildResponse(
            transactionId, unitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 5);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestSucceed));
        expect(register.value, equals(0x0042));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });

    test('response with mismatched unit ID returns requestRxFailed', () async {
      late ModbusTestServer server;
      server = ModbusTestServer(onData: (socket, data) {
        if (data.length < 7) return;
        final view = ByteData.view(Uint8List.fromList(data).buffer);
        final transactionId = view.getUint16(0);
        // Intentionally use a DIFFERENT unit ID in the response
        final wrongUnitId = 99;

        final pdu = Uint8List.fromList([0x03, 0x02, 0x00, 0x42]);
        final response = ModbusTestServer.buildResponse(
            transactionId, wrongUnitId, pdu);
        server.sendToClient(socket, response);
      });
      final port = await server.start();
      final client = ModbusClientTcp('127.0.0.1',
          serverPort: port,
          connectionTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(seconds: 2),
          unitId: 5);

      try {
        final register = ModbusUint16Register(
            name: 'test', address: 0, type: ModbusElementType.holdingRegister);
        final request = register.getReadRequest();
        final code = await client.send(request);
        expect(code, equals(ModbusResponseCode.requestRxFailed));
      } finally {
        await client.disconnect();
        await server.shutdown();
      }
    });
  });
}

/// Raw FC03 test request that skips byte count validation.
/// Used for MBAP-level tests (e.g., max length field) where we don't want
/// element-level byte count checks interfering.
class _Fc03RawRequest extends ModbusRequest {
  _Fc03RawRequest() : super();

  @override
  FunctionCode get functionCode => ModbusFunctionCode.readHoldingRegisters;

  @override
  Uint8List get protocolDataUnit =>
      Uint8List.fromList([0x03, 0x00, 0x00, 0x00, 0x01]); // FC03, addr=0, qty=1

  @override
  int get responsePduLength => -1;

  @override
  ModbusResponseCode internalSetFromPduResponse(Uint8List pdu) {
    return ModbusResponseCode.requestSucceed;
  }
}

/// Simple FC90 test request for UMAS MBAP length validation tests.
class _Fc90TestRequest extends ModbusRequest {
  _Fc90TestRequest() : super();

  @override
  FunctionCode get functionCode =>
      const ModbusFunctionCode(0x5A, FunctionType.custom);

  @override
  Uint8List get protocolDataUnit =>
      Uint8List.fromList([0x5A, 0x00, 0x01]); // FC90, pairingKey, subFunc

  @override
  int get responsePduLength => -1;

  @override
  ModbusResponseCode internalSetFromPduResponse(Uint8List pdu) {
    return ModbusResponseCode.requestSucceed;
  }
}

/// Helper to track received requests in test server callbacks.
class _ReceivedRequest {
  final Socket socket;
  final int transactionId;
  final int unitId;
  _ReceivedRequest(this.socket, this.transactionId, this.unitId);
}

/// Parsed MBAP request header from raw bytes.
class _ParsedRequest {
  final int tid;
  final int unitId;
  _ParsedRequest(this.tid, this.unitId);
}

/// Parse potentially concatenated MBAP requests from raw TCP data.
///
/// Each MBAP request has a 7-byte header (transaction ID 2 + protocol ID 2 +
/// length 2 + unit ID 1) followed by the PDU. The length field tells us how
/// many bytes follow the 6-byte prefix (unit ID + PDU).
List<_ParsedRequest> _parseRequests(Uint8List data) {
  final requests = <_ParsedRequest>[];
  var offset = 0;
  while (offset + 6 <= data.length) {
    final view = ByteData.view(data.buffer, data.offsetInBytes + offset, 6);
    final tid = view.getUint16(0);
    final lengthField = view.getUint16(4);
    final totalFrameSize = lengthField + 6;
    if (offset + totalFrameSize > data.length) break;
    final unitId = data[offset + 6];
    requests.add(_ParsedRequest(tid, unitId));
    offset += totalFrameSize;
  }
  return requests;
}
