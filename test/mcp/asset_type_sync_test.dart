import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart' show kValidAssetTypes;

/// kValidAssetTypes in the MCP package is a hand-maintained copy of the
/// asset types AssetRegistry can instantiate -- the package cannot depend
/// on the Flutter app layer, so the list cannot be derived. This test is
/// the only thing keeping the copy honest: it fails whenever an asset is
/// added to (or removed from) AssetRegistry without updating
/// packages/tfc_mcp_server/lib/src/tools/asset_write_tools.dart.
void main() {
  test('kValidAssetTypes matches AssetRegistry.defaultFactories exactly', () {
    final registryNames =
        AssetRegistry.defaultFactories.keys.map((t) => t.toString()).toSet();
    final mcpNames = kValidAssetTypes.toSet();

    expect(kValidAssetTypes.length, mcpNames.length,
        reason: 'kValidAssetTypes contains duplicates');

    expect(
      mcpNames.difference(registryNames),
      isEmpty,
      reason: 'kValidAssetTypes advertises types AssetRegistry cannot '
          'create -- remove them from asset_write_tools.dart',
    );
    expect(
      registryNames.difference(mcpNames),
      isEmpty,
      reason: 'AssetRegistry has types missing from kValidAssetTypes -- '
          'add them to asset_write_tools.dart so propose_asset/propose_page '
          'advertise them',
    );
  });
}
