import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/plc/plc_code_upload_service.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

class _MockPlcCodeService extends Fake implements PlcCodeService {
  final bool _hasCode;
  _MockPlcCodeService({bool hasCode = false}) : _hasCode = hasCode;

  @override
  bool get hasCode => _hasCode;
}

void main() {
  group('PlcCodeUploadService', () {
    test('hasExistingIndex proxies PlcCodeService.hasCode true', () {
      final service = PlcCodeUploadService(_MockPlcCodeService(hasCode: true));
      expect(service.hasExistingIndex, isTrue);
    });

    test('hasExistingIndex returns false when no code indexed', () {
      final service = PlcCodeUploadService(_MockPlcCodeService(hasCode: false));
      expect(service.hasExistingIndex, isFalse);
    });
  });
}
