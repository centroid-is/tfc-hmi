import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

/// UpgraderStore subclass that queries the GitHub Releases API for the latest
/// version of the centroidx-manager / centroidx app.
///
/// Replaces [microsoft_store_upgrader] with a cross-platform GitHub-based
/// update check that works on Windows, Linux, and macOS.
class GitHubReleaseStore extends UpgraderStore {
  /// The GitHub repository owner (e.g. 'centroid-is').
  final String owner;

  /// The GitHub repository name (e.g. 'tfc-hmi2').
  final String repo;

  /// Optional GitHub personal access token for authenticated API requests.
  /// When provided, the `Authorization: Bearer <token>` header is added.
  final String? token;

  final http.Client _httpClient;

  GitHubReleaseStore({
    required this.owner,
    required this.repo,
    http.Client? httpClient,
    this.token,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  }) async {
    final fallback = UpgraderVersionInfo(
      appStoreVersion: installedVersion,
      installedVersion: installedVersion,
    );

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );

      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

      final t = token;
      if (t != null && t.isNotEmpty) {
        headers['Authorization'] = 'Bearer $t';
      }

      final response = await _httpClient.get(uri, headers: headers);

      if (response.statusCode != 200) {
        return fallback;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTag = (json['tag_name'] as String?) ?? '';
      final htmlUrl = (json['html_url'] as String?) ?? '';
      final bodyText = (json['body'] as String?) ?? '';

      // Strip leading 'v' prefix (e.g. 'v2026.4.1' → '2026.4.1')
      var cleanTag = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;

      // Strip build metadata suffix (e.g. '2026.4.1+1' → '2026.4.1')
      final plusIndex = cleanTag.indexOf('+');
      if (plusIndex != -1) {
        cleanTag = cleanTag.substring(0, plusIndex);
      }

      Version parsedVersion;
      try {
        parsedVersion = Version.parse(cleanTag);
      } catch (_) {
        // Unparseable tag — return installed version so no update is shown.
        return fallback;
      }

      return UpgraderVersionInfo(
        appStoreVersion: parsedVersion,
        installedVersion: installedVersion,
        appStoreListingURL: htmlUrl.isNotEmpty ? htmlUrl : null,
        releaseNotes: bodyText.isNotEmpty ? bodyText : null,
      );
    } catch (_) {
      return fallback;
    }
  }
}
