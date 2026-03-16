import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';

void main() {
  group('RiskGate', () {
    test('RiskLevel enum has all four values', () {
      expect(RiskLevel.values, hasLength(4));
      expect(RiskLevel.values, contains(RiskLevel.low));
      expect(RiskLevel.values, contains(RiskLevel.medium));
      expect(RiskLevel.values, contains(RiskLevel.high));
      expect(RiskLevel.values, contains(RiskLevel.critical));
    });

    test('NoOpRiskGate always returns confirmed=true', () async {
      final gate = NoOpRiskGate();
      final result = await gate.requestConfirmation(
        description: 'Create alarm for pump3',
        level: RiskLevel.medium,
        details: {'alarm': 'pump3_overcurrent'},
      );
      expect(result.confirmed, isTrue);
    });

    test('NoOpRiskGate returns confirmed for all risk levels', () async {
      final gate = NoOpRiskGate();
      for (final level in RiskLevel.values) {
        final result = await gate.requestConfirmation(
          description: 'Test operation',
          level: level,
        );
        expect(result.confirmed, isTrue,
            reason: 'NoOpRiskGate should confirm for $level');
      }
    });

    test('RiskGate is abstract and can be implemented', () {
      // Verify that NoOpRiskGate is a valid RiskGate implementation
      final RiskGate gate = NoOpRiskGate();
      expect(gate, isA<RiskGate>());
    });
  });
}
