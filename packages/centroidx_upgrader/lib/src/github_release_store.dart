import 'package:http/http.dart' as http;
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

/// UpgraderStore subclass that queries GitHub Releases API for the latest version.
class GitHubReleaseStore extends UpgraderStore {
  final String owner;
  final String repo;
  final http.Client _httpClient;
  final String? token;

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
  }) {
    throw UnimplementedError('GitHubReleaseStore.getVersionInfo not yet implemented');
  }
}
