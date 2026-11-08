import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/config_info/preferences/extension_preference.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_any/one_of_any.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'manga/komga';

final String serverUrl = environmentValue('KOMGA_URL', 'http://localhost:25600');
final String apiKey = environmentValue('KOMGA_API_KEY');
final String username = environmentValue('KOMGA_USERNAME');
final String password = environmentValue('KOMGA_PASSWORD');

const String unavailableReason =
    'Komga is not reachable; set KOMGA_URL and KOMGA_API_KEY or KOMGA_USERNAME + KOMGA_PASSWORD';

MangaApiClient clientWith(ConfigInfo config, Map<String, Object?> preferences) {
  return MangaApiClient(
    code: readScript(extensionDirectory),
    host: hostFor(config, preferences: preferences),
  );
}

Map<String, Object?> credentialPreferences() {
  if (apiKey.isNotEmpty) {
    return {'serverUrl': serverUrl, 'apiKey': apiKey};
  }
  return {'serverUrl': serverUrl, 'username': username, 'password': password};
}

void main() {
  late ConfigInfo config;
  var available = false;

  setUpAll(() async {
    config = loadConfig(extensionDirectory);
    final hasCredentials =
        apiKey.isNotEmpty || (username.isNotEmpty && password.isNotEmpty);
    available = hasCredentials && await isReachable('$serverUrl/api/v1/claim');
  });

  group('config', () {
    test('declares api 2 with feeds, pagination and text settings', () {
      expect(config.apiVersion, 2);
      expect(config.feeds.map((feed) => feed.id), ['all', 'new', 'updated']);
      expect(config.pagination!.defaultPageSize, 20);
      final keys = config.preferences.map((preference) => preference.key);
      expect(keys, containsAll(['serverUrl', 'apiKey', 'username', 'password', 'libraries']));
      for (final preference in config.preferences) {
        expect(preference.type, ExtensionPreferenceType.text);
      }
    });
  });

  group('settings', () {
    test('asks for the server address when it is missing', () async {
      final client = clientWith(config, const {});
      final error = await expectSourceError(
          () => client.getGallery(page: 1), SourceErrorKind.loginRequired);
      expect(error.message, contains('server address'));
    });

    test('asks for credentials when only the address is set', () async {
      final client = clientWith(config, {'serverUrl': serverUrl});
      final error = await expectSourceError(
          () => client.getGallery(page: 1), SourceErrorKind.loginRequired);
      expect(error.message, contains('API key'));
    });

    test('reports an unreachable server as down', () async {
      final client = clientWith(config, {'serverUrl': 'http://127.0.0.1:9', 'apiKey': 'x'});
      await expectSourceError(() => client.getGallery(page: 1), SourceErrorKind.sourceDown);
    });
  });

  group('live server', () {
    late MangaApiClient client;
    late List<MangaGalleryView> catalogue;

    setUpAll(() async {
      if (available == false) {
        return;
      }
      client = clientWith(config, credentialPreferences());
      catalogue = await client.getGallery(page: 1, feed: 'all');
    });

    test('lists series with authenticated covers', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      expect(catalogue, isNotEmpty);
      final headers = await client.getImageHeaders(uid: catalogue.first.uid, data: const {});
      expect(await probeContentType(catalogue.first.cover, headers), startsWith('image/'));
    });

    test('recently added and recently updated feeds list series', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      expect(await client.getGallery(page: 1, feed: 'new'), isNotEmpty);
      expect(await client.getGallery(page: 1, feed: 'updated'), isNotEmpty);
    });

    test('pages do not overlap', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final sized = clientWith(config, {
        ...credentialPreferences(),
        ExtensionPreference.pageSizeKey: 20,
      });
      final first = await sized.getGallery(page: 1, feed: 'all');
      final second = await sized.getGallery(page: 2, feed: 'all');
      final firstUids = first.map((item) => item.uid).toSet();
      expect(second.map((item) => item.uid).toSet().intersection(firstUids), isEmpty);
    });

    test('search finds a series by title', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final wanted = catalogue.first;
      final results = await client.getGallery(page: 1, query: wanted.title, feed: 'all');
      expect(results.map((item) => item.uid), contains(wanted.uid));
    });

    test('the status filter keeps only series with that status', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final statusFilter = config.filters.firstWhere((filter) => filter.param == 'seriesStatus');
      final ongoing = await client.getGallery(
        page: 1,
        feed: 'all',
        filters: [FilterDataOneOfAny(selected: 'ONGOING', filter: statusFilter)],
      );
      for (final item in ongoing) {
        expect(item.status, MangaStatus.ONGOING);
      }
    });

    test('a wrong API key asks the user to sign in again', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final wrong = clientWith(config, {'serverUrl': serverUrl, 'apiKey': 'not-a-key'});
      await expectSourceError(() => wrong.getGallery(page: 1), SourceErrorKind.loginRequired);
    });

    test('an unknown library name is reported', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final filtered = clientWith(config, {
        ...credentialPreferences(),
        'libraries': 'no such library',
      });
      await expectLater(filtered.getGallery(page: 1), throwsA(anything));
    });

    test('opens a series and reads the first book', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final concrete = await client.getConcrete(uid: catalogue.first.uid, data: const {});
      expect(concrete.title, catalogue.first.title);
      final books = concrete.groups.expand((group) => group.elements).toList();
      expect(books, isNotEmpty);
      final pages = await client.getPages(uid: books.first.uid, data: books.first.data);
      expect(pages.value, isNotEmpty);
      final headers = await client.getImageHeaders(uid: books.first.uid, data: const {});
      expect(await probeContentType(pages.value.first, headers), startsWith('image/'));
    });

    test('an unknown series is reported as not found', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      await expectSourceError(
          () => client.getConcrete(uid: '0000000000000', data: const {}),
          SourceErrorKind.notFound);
    });
  });
}
