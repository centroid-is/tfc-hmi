import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

/// Release channel names, shared with the centroidx-manager `-channel` flag
/// and the persisted preference value.
const String kUpdateChannelStable = 'stable';
const String kUpdateChannelLatest = 'latest';

/// UpgraderStore subclass that queries the GitHub Releases API for the latest
/// version of the centroidx-manager / centroidx app.
///
/// Replaces [microsoft_store_upgrader] with a cross-platform GitHub-based
/// update check that works on Windows, Linux, and macOS.
///
/// Two channels are supported:
///  * `stable` — the latest tagged release (`/releases/latest`), compared by
///    CalVer version. This is the default.
///  * `latest` — the most recently published release including prereleases,
///    i.e. the rolling `main-latest` build republished on every merge to
///    main. Its tag never parses as a version, so the check compares the
///    release's target commit against [buildSha] (the `GIT_SHA` dart-define
///    baked into CI builds) instead.
class GitHubReleaseStore extends UpgraderStore {
  /// The GitHub repository owner (e.g. 'centroid-is').
  final String owner;

  /// The GitHub repository name (e.g. 'tfc-hmi').
  final String repo;

  /// Optional GitHub personal access token for authenticated API requests.
  /// When provided, the `Authorization: Bearer <token>` header is added.
  final String? token;

  /// Resolves the channel to check, called on every [getVersionInfo] so a
  /// changed preference takes effect without an app restart. Unknown values
  /// fall back to stable. When null, the stable channel is used.
  final Future<String> Function()? channel;

  /// The git commit this build was produced from (`GIT_SHA` dart-define).
  /// Empty or null for local builds — those never announce latest-channel
  /// updates, because without a sha there is nothing to compare.
  final String? buildSha;

  final http.Client _httpClient;

  GitHubReleaseStore({
    required this.owner,
    required this.repo,
    http.Client? httpClient,
    this.token,
    this.channel,
    this.buildSha,
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
      var resolvedChannel = kUpdateChannelStable;
      if (channel != null) {
        resolvedChannel = await channel!();
      }

      if (resolvedChannel == kUpdateChannelLatest) {
        return await _latestChannelVersionInfo(installedVersion, fallback);
      }
      return await _stableChannelVersionInfo(installedVersion, fallback);
    } catch (_) {
      return fallback;
    }
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    final t = token;
    if (t != null && t.isNotEmpty) {
      headers['Authorization'] = 'Bearer $t';
    }
    return headers;
  }

  Future<UpgraderVersionInfo> _stableChannelVersionInfo(
    Version installedVersion,
    UpgraderVersionInfo fallback,
  ) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );

    final response = await _httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      return fallback;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawTag = (json['tag_name'] as String?) ?? '';
    final htmlUrl = (json['html_url'] as String?) ?? '';
    final bodyText = (json['body'] as String?) ?? '';

    final parsedVersion = _parseTag(rawTag);
    if (parsedVersion == null) {
      // Unparseable tag — return installed version so no update is shown.
      return fallback;
    }

    return UpgraderVersionInfo(
      appStoreVersion: parsedVersion,
      installedVersion: installedVersion,
      appStoreListingURL: htmlUrl.isNotEmpty ? htmlUrl : null,
      releaseNotes: bodyText.isNotEmpty ? bodyText : null,
    );
  }

  Future<UpgraderVersionInfo> _latestChannelVersionInfo(
    Version installedVersion,
    UpgraderVersionInfo fallback,
  ) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases?per_page=30',
    );

    final response = await _httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      return fallback;
    }

    final releases = (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((r) => r['draft'] != true)
        .toList();
    if (releases.isEmpty) {
      return fallback;
    }

    // Newest published release wins — prereleases like main-latest included.
    Map<String, dynamic>? newest;
    DateTime? newestAt;
    for (final r in releases) {
      final publishedAt =
          DateTime.tryParse((r['published_at'] as String?) ?? '');
      if (publishedAt == null) continue;
      if (newestAt == null || publishedAt.isAfter(newestAt)) {
        newest = r;
        newestAt = publishedAt;
      }
    }
    if (newest == null || newestAt == null) {
      return fallback;
    }

    final rawTag = (newest['tag_name'] as String?) ?? '';
    final htmlUrl = (newest['html_url'] as String?) ?? '';
    final bodyText = (newest['body'] as String?) ?? '';

    final parsedVersion = _parseTag(rawTag);
    if (parsedVersion != null) {
      // A normal tagged release is the newest — plain version comparison.
      return UpgraderVersionInfo(
        appStoreVersion: parsedVersion,
        installedVersion: installedVersion,
        appStoreListingURL: htmlUrl.isNotEmpty ? htmlUrl : null,
        releaseNotes: bodyText.isNotEmpty ? bodyText : null,
      );
    }

    // Rolling prerelease (tag like `main-latest`): versions can't order it,
    // so compare the release's commit against the sha this build came from.
    final targetSha = ((newest['target_commitish'] as String?) ?? '').trim();
    final ownSha = (buildSha ?? '').trim();
    if (ownSha.isEmpty || targetSha.isEmpty) {
      return fallback;
    }
    if (_sameCommit(ownSha, targetSha)) {
      return fallback;
    }

    // Announce using the publish date as a CalVer stand-in version — for a
    // newer main build it always exceeds the installed tagged version.
    final syntheticVersion =
        Version(newestAt.year, newestAt.month, newestAt.day);
    final shortSha =
        targetSha.length > 7 ? targetSha.substring(0, 7) : targetSha;
    final notes = 'Development build $shortSha from the latest channel.'
        '${bodyText.isNotEmpty ? '\n\n$bodyText' : ''}';

    return UpgraderVersionInfo(
      appStoreVersion: syntheticVersion,
      installedVersion: installedVersion,
      appStoreListingURL: htmlUrl.isNotEmpty ? htmlUrl : null,
      releaseNotes: notes,
    );
  }

  /// Parses a release tag into a [Version], stripping the leading 'v' and any
  /// '+build' metadata. Returns null for tags like `main-latest`.
  Version? _parseTag(String rawTag) {
    var cleanTag = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
    final plusIndex = cleanTag.indexOf('+');
    if (plusIndex != -1) {
      cleanTag = cleanTag.substring(0, plusIndex);
    }
    try {
      return Version.parse(cleanTag);
    } catch (_) {
      return null;
    }
  }

  /// Compares two commit identifiers, tolerating one being abbreviated.
  bool _sameCommit(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    return la.startsWith(lb) || lb.startsWith(la);
  }
}
