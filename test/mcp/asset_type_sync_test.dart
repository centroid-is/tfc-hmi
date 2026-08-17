import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show AssetTypeCatalog, kValidAssetTypes;

/// AssetTypeCatalog in the MCP package describes the asset types the
/// Flutter-side AssetRegistry can instantiate -- the package cannot depend
/// on the app layer, so the catalog cannot be derived from the registry.
/// This test is what keeps it honest: it fails whenever an asset is added
/// to (or removed from) AssetRegistry without a matching catalog entry in
/// packages/tfc_mcp_server/lib/src/services/asset_type_catalog.dart.
void main() {
  test('AssetTypeCatalog matches AssetRegistry.defaultFactories exactly', () {
    final registryNames =
        AssetRegistry.defaultFactories.keys.map((t) => t.toString()).toSet();
    final catalogNames =
        AssetTypeCatalog.all.map((t) => t.assetName).toSet();

    expect(AssetTypeCatalog.all.length, catalogNames.length,
        reason: 'AssetTypeCatalog contains duplicate assetName entries');

    expect(
      catalogNames.difference(registryNames),
      isEmpty,
      reason: 'AssetTypeCatalog describes types AssetRegistry cannot '
          'create -- remove them from asset_type_catalog.dart',
    );
    expect(
      registryNames.difference(catalogNames),
      isEmpty,
      reason: 'AssetRegistry has types missing from AssetTypeCatalog -- '
          'add entries to asset_type_catalog.dart so the MCP write tools '
          'and get_asset_types advertise them',
    );
  });

  test('kValidAssetTypes is derived from the catalog', () {
    expect(
      kValidAssetTypes,
      AssetTypeCatalog.all.map((t) => t.assetName).toList(),
    );
  });
}
