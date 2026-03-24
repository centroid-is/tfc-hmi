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
}
