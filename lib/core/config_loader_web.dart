import 'package:http/http.dart' as http;
import 'package:tfc_dart/core/config_source.dart';

/// Loads a [StaticConfig] by fetching config files from the web server
/// via HTTP relative to the web root.
///
/// Always returns a [StaticConfig] on web (or `null` if the required
/// config files are not served).
Future<StaticConfig?> loadStaticConfig() async {
  final configResp = await http.get(Uri.parse('config/config.json'));
  final keyMappingsResp = await http.get(Uri.parse('config/keymappings.json'));
  final pageEditorResp = await http.get(Uri.parse('config/page-editor.json'));

  if (configResp.statusCode != 200 || keyMappingsResp.statusCode != 200) {
    return null; // Required config files not found
  }

  return StaticConfig.fromStrings(
    configJson: configResp.body,
    keyMappingsJson: keyMappingsResp.body,
    pageEditorJson:
        pageEditorResp.statusCode == 200 ? pageEditorResp.body : null,
  );
}
