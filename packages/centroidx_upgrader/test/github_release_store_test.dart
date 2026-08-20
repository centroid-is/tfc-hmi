import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

import 'package:centroidx_upgrader/centroidx_upgrader.dart';

/// Creates a minimal fake UpgraderState for use in tests.
/// GitHubReleaseStore only uses [installedVersion] parameter directly
/// (not the state), so we can pass any valid state instance.
UpgraderState _fakeState() {
  return UpgraderState(
    client: http.Client(),
    upgraderDevice: UpgraderDevice(),
    upgraderOS: UpgraderOS(),
  );
}

/// Creates a GitHubReleaseStore with a fake HTTP client returning [body]
/// and [statusCode] for any request.
GitHubReleaseStore _storeWith({
  required int statusCode,
  required String body,
  String? token,
  Map<String, String>? capturedHeaders,
}) {
  final fakeClient = MockClient((request) async {
    if (capturedHeaders != null) {
      capturedHeaders.addAll(request.headers);
    }
    return http.Response(body, statusCode);
  });

  return GitHubReleaseStore(
    owner: 'centroid-is',
    repo: 'tfc-hmi',
    httpClient: fakeClient,
    token: token,
  );
}

/// Builds a JSON string resembling a GitHub releases/latest response.
String _releaseJson({
  String tagName = '2026.4.1',
  String body = 'Bug fixes and improvements.',
  String htmlUrl = 'https://github.com/centroid-is/tfc-hmi/releases/tag/2026.4.1',
}) {
  return jsonEncode({
    'tag_name': tagName,
    'body': body,
    'html_url': htmlUrl,
  });
}

void main() {
  group('GitHubReleaseStore', () {
    final installedVersion = Version.parse('2026.1.1');

    // Test 1: Returns appStoreVersion parsed from tag_name on 200 response
    test('getVersionInfo returns appStoreVersion from tag_name "2026.4.1" on 200', () async {
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(tagName: '2026.4.1'),
      );

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.appStoreVersion, equals(Version.parse('2026.4.1')));
    });

    // Test 2: Returns installedVersion as appStoreVersion on non-200 response
    test('getVersionInfo returns installedVersion when API returns 404', () async {
      final store = _storeWith(statusCode: 404, body: '{}');

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.appStoreVersion, equals(installedVersion));
      expect(info.installedVersion, equals(installedVersion));
    });

    // Test 3: Strips "v" prefix from tag_name "v2026.4.1"
    test('getVersionInfo strips "v" prefix from tag_name "v2026.4.1"', () async {
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(tagName: 'v2026.4.1'),
      );

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.appStoreVersion, equals(Version.parse('2026.4.1')));
    });

    // Test 4: Strips "+1" build metadata from tag_name "2026.4.1+1"
    test('getVersionInfo strips "+1" build metadata from tag_name "2026.4.1+1"', () async {
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(tagName: '2026.4.1+1'),
      );

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.appStoreVersion, equals(Version.parse('2026.4.1')));
    });

    // Test 5: Populates releaseNotes from response body field
    test('getVersionInfo populates releaseNotes from body field', () async {
      const notes = 'Fixed critical bug in the update path.';
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(body: notes),
      );

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.releaseNotes, equals(notes));
    });

    // Test 6: Populates appStoreListingURL from html_url field
    test('getVersionInfo populates appStoreListingURL from html_url field', () async {
      const url = 'https://github.com/centroid-is/tfc-hmi/releases/tag/2026.4.1';
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(htmlUrl: url),
      );

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.appStoreListingURL, equals(url));
    });

    // Test 7: Returns installedVersion when tag_name is unparseable
    test('getVersionInfo returns installedVersion when tag_name is unparseable', () async {
      final store = _storeWith(
        statusCode: 200,
        body: jsonEncode({
          'tag_name': 'not-a-version',
          'body': '',
          'html_url': '',
        }),
      );

      final info = await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      expect(info.appStoreVersion, equals(installedVersion));
    });

    // Test 8: Includes Authorization header when token is provided
    test('getVersionInfo includes Authorization header when token is provided', () async {
      final capturedHeaders = <String, String>{};
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(),
        token: 'ghp_testtoken123',
        capturedHeaders: capturedHeaders,
      );

      await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      // http package may normalize header keys to lowercase
      final authValue = capturedHeaders['authorization'] ??
          capturedHeaders['Authorization'];
      expect(authValue, equals('Bearer ghp_testtoken123'));
    });

    // Test 9: Omits Authorization header when token is null/empty
    test('getVersionInfo omits Authorization header when token is null', () async {
      final capturedHeaders = <String, String>{};
      final store = _storeWith(
        statusCode: 200,
        body: _releaseJson(),
        token: null,
        capturedHeaders: capturedHeaders,
      );

      await store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );

      final hasAuth = capturedHeaders.containsKey('authorization') ||
          capturedHeaders.containsKey('Authorization');
      expect(hasAuth, isFalse);
    });
  });

  group('GitHubReleaseStore latest channel', () {
    final installedVersion = Version.parse('2026.3.26');

    /// A store on the latest channel with a fake client that serves
    /// [listBody] for the `/releases` list endpoint and records request paths.
    GitHubReleaseStore latestStoreWith({
      required String listBody,
      String? buildSha,
      List<String>? requestedPaths,
      Future<String> Function()? channel,
    }) {
      final fakeClient = MockClient((request) async {
        requestedPaths?.add(request.url.path);
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(_releaseJson(tagName: '2026.3.26'), 200);
        }
        return http.Response(listBody, 200);
      });
      return GitHubReleaseStore(
        owner: 'centroid-is',
        repo: 'tfc-hmi',
        httpClient: fakeClient,
        channel: channel ?? () async => kUpdateChannelLatest,
        buildSha: buildSha,
      );
    }

    Map<String, dynamic> releaseEntry({
      required String tagName,
      required String publishedAt,
      String body = '',
      String htmlUrl = 'https://github.com/centroid-is/tfc-hmi/releases',
      String targetCommitish = '',
      bool draft = false,
      bool prerelease = false,
    }) {
      return {
        'tag_name': tagName,
        'body': body,
        'html_url': htmlUrl,
        'published_at': publishedAt,
        'target_commitish': targetCommitish,
        'draft': draft,
        'prerelease': prerelease,
      };
    }

    Future<UpgraderVersionInfo> check(GitHubReleaseStore store) {
      return store.getVersionInfo(
        state: _fakeState(),
        installedVersion: installedVersion,
        country: null,
        language: null,
      );
    }

    test('queries the releases list, not releases/latest', () async {
      final paths = <String>[];
      final store = latestStoreWith(
        listBody: jsonEncode([
          releaseEntry(tagName: 'v2026.4.1', publishedAt: '2026-04-01T10:00:00Z'),
        ]),
        requestedPaths: paths,
      );

      await check(store);

      expect(paths, hasLength(1));
      expect(paths.single, endsWith('/releases'));
    });

    test('newest published tagged release wins by version comparison', () async {
      final store = latestStoreWith(
        listBody: jsonEncode([
          releaseEntry(tagName: 'v2026.3.26', publishedAt: '2026-03-26T10:00:00Z'),
          releaseEntry(tagName: 'v2026.4.1', publishedAt: '2026-04-01T10:00:00Z'),
        ]),
      );

      final info = await check(store);

      expect(info.appStoreVersion, equals(Version.parse('2026.4.1')));
    });

    test('rolling prerelease with differing sha announces a dated update', () async {
      final store = latestStoreWith(
        buildSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        listBody: jsonEncode([
          releaseEntry(tagName: 'v2026.3.26', publishedAt: '2026-03-26T10:00:00Z'),
          releaseEntry(
            tagName: 'main-latest',
            publishedAt: '2026-08-20T12:00:00Z',
            targetCommitish: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            prerelease: true,
            body: 'Automatically built from the tip of main.',
          ),
        ]),
      );

      final info = await check(store);

      expect(info.appStoreVersion, equals(Version(2026, 8, 20)));
      expect(info.releaseNotes, contains('bbbbbbb'));
      expect(info.releaseNotes, contains('Automatically built'));
    });

    test('rolling prerelease with matching sha is not announced', () async {
      final store = latestStoreWith(
        // Abbreviated build sha must still match the full target commit.
        buildSha: 'bbbbbbbbbb',
        listBody: jsonEncode([
          releaseEntry(
            tagName: 'main-latest',
            publishedAt: '2026-08-20T12:00:00Z',
            targetCommitish: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            prerelease: true,
          ),
        ]),
      );

      final info = await check(store);

      expect(info.appStoreVersion, equals(installedVersion));
    });

    test('rolling prerelease without a build sha is not announced', () async {
      final store = latestStoreWith(
        buildSha: null,
        listBody: jsonEncode([
          releaseEntry(
            tagName: 'main-latest',
            publishedAt: '2026-08-20T12:00:00Z',
            targetCommitish: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            prerelease: true,
          ),
        ]),
      );

      final info = await check(store);

      expect(info.appStoreVersion, equals(installedVersion));
    });

    test('draft releases are skipped', () async {
      final store = latestStoreWith(
        listBody: jsonEncode([
          releaseEntry(
            tagName: 'v2026.9.9',
            publishedAt: '2026-09-09T10:00:00Z',
            draft: true,
          ),
          releaseEntry(tagName: 'v2026.4.1', publishedAt: '2026-04-01T10:00:00Z'),
        ]),
      );

      final info = await check(store);

      expect(info.appStoreVersion, equals(Version.parse('2026.4.1')));
    });

    test('unknown channel value falls back to the stable endpoint', () async {
      final paths = <String>[];
      final store = latestStoreWith(
        listBody: '[]',
        requestedPaths: paths,
        channel: () async => 'nightly',
      );

      final info = await check(store);

      expect(paths.single, endsWith('/releases/latest'));
      expect(info.appStoreVersion, equals(Version.parse('2026.3.26')));
    });

    test('throwing channel resolver falls back to installed version', () async {
      final store = latestStoreWith(
        listBody: '[]',
        channel: () async => throw StateError('prefs unavailable'),
      );

      final info = await check(store);

      expect(info.appStoreVersion, equals(installedVersion));
    });
  });
}
