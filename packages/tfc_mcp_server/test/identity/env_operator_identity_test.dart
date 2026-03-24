import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/identity/operator_identity.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';

void main() {
  group('EnvOperatorIdentity', () {
    test('operatorId returns TFC_USER value when set', () {
      final env = <String, String>{'TFC_USER': 'operator1'};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      expect(identity.operatorId, equals('operator1'));
    });

    test('operatorId throws OperatorNotAuthenticatedError when TFC_USER is not set', () {
      final env = <String, String>{};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      expect(
        () => identity.operatorId,
        throwsA(isA<OperatorNotAuthenticatedError>().having(
          (e) => e.message,
          'message',
          contains('TFC_USER'),
        )),
      );
    });

    test('operatorId throws OperatorNotAuthenticatedError when TFC_USER is empty string', () {
      final env = <String, String>{'TFC_USER': ''};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      expect(
        () => identity.operatorId,
        throwsA(isA<OperatorNotAuthenticatedError>()),
      );
    });

    test('isAuthenticated returns true when TFC_USER is set and non-empty', () {
      final env = <String, String>{'TFC_USER': 'admin'};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      expect(identity.isAuthenticated, isTrue);
    });

    test('isAuthenticated returns false when TFC_USER is not set', () {
      final env = <String, String>{};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      expect(identity.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns false when TFC_USER is empty string', () {
      final env = <String, String>{'TFC_USER': ''};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      expect(identity.isAuthenticated, isFalse);
    });

    test('validate() succeeds when TFC_USER is set', () async {
      final env = <String, String>{'TFC_USER': 'operator1'};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      // Should complete without error
      await expectLater(identity.validate(), completes);
    });

    test('validate() throws OperatorNotAuthenticatedError when TFC_USER is not set', () async {
      final env = <String, String>{};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      await expectLater(
        identity.validate(),
        throwsA(isA<OperatorNotAuthenticatedError>()),
      );
    });

    test('multiple calls to validate() check environment each time (not cached)', () async {
      final env = <String, String>{'TFC_USER': 'operator1'};
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env,
      );

      // First call succeeds
      await identity.validate();
      expect(identity.operatorId, equals('operator1'));

      // Remove TFC_USER from environment
      env.remove('TFC_USER');

      // Second call should fail -- identity checks on every call
      expect(
        () => identity.operatorId,
        throwsA(isA<OperatorNotAuthenticatedError>()),
      );
      await expectLater(
        identity.validate(),
        throwsA(isA<OperatorNotAuthenticatedError>()),
      );
    });
  });

  group('OperatorIdentity interface', () {
    test('OperatorIdentity cannot be instantiated directly (is abstract)', () {
      // This is a compile-time check. If OperatorIdentity were concrete,
      // the following would compile. The fact that we use EnvOperatorIdentity
      // as the implementation confirms the abstract contract.
      //
      // OperatorIdentity(); // Would fail to compile
      //
      // Instead, verify the interface type relationship:
      final identity = EnvOperatorIdentity(
        environmentProvider: () => {'TFC_USER': 'test'},
      );
      expect(identity, isA<OperatorIdentity>());
    });
  });

  group('OperatorNotAuthenticatedError', () {
    test('has descriptive message', () {
      final error = OperatorNotAuthenticatedError('Test message');
      expect(error.message, equals('Test message'));
    });

    test('toString includes class name and message', () {
      final error = OperatorNotAuthenticatedError('Test message');
      expect(error.toString(), contains('OperatorNotAuthenticatedError'));
      expect(error.toString(), contains('Test message'));
    });
  });
}
