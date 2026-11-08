import 'package:capyscript/api_clients/host/extension_host.dart';
import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/config_info/preferences/extension_preference.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'manga/kavita';

final String serverUrl = environmentValue('KAVITA_URL', 'http://localhost:5000');
final String apiKey = environmentValue('KAVITA_API_KEY');

const String unavailableReason =
    'Kavita is not reachable; set KAVITA_URL and KAVITA_API_KEY';

MangaApiClient clientWith(
  ConfigInfo config,
  Map<String, Object?> preferences, [
  ExtensionStorage storage = const NoopExtensionStorage(),
]) {
  return MangaApiClient(
    code: readScript(extensionDirectory),
    host: hostFor(config, preferences: preferences, storage: storage),
  );
}

void main() {
  late ConfigInfo config;
  var available = false;

  setUpAll(() async {
    config = loadConfig(extensionDirectory);
    available = apiKey.isNotEmpty && await isReachable('$serverUrl/api/health');
  });

  group('config', () {
    test('declares api 2 with feeds, pagination and text settings', () {
      expect(config.apiVersion, 2);
      expect(config.feeds.map((feed) => feed.id), ['all', 'new', 'updated']);
      expect(config.pagination!.defaultPageSize, 20);
      expect(config.preferences.map((preference) => preference.key),
          ['serverUrl', 'apiKey', 'libraries']);
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

    test('asks for the API key when only the address is set', () async {
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
    late MemoryExtensionStorage storage;
    late MangaApiClient client;
    late List<MangaGalleryView> catalogue;

    setUpAll(() async {
      if (available == false) {
        return;
      }
      storage = MemoryExtensionStorage();
      client = clientWith(config, {'serverUrl': serverUrl, 'apiKey': apiKey}, storage);
      catalogue = await client.getGallery(page: 1, feed: 'all');
    });

    test('lists series with covers', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      expect(catalogue, isNotEmpty);
      expect(await probeContentType(catalogue.first.cover, const {}), startsWith('image/'));
    });

    test('caches the session token in extension storage', () {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      expect(storage.values.keys.where((key) => key.startsWith('token|')), hasLength(1));
    });

    test('a stale cached token is replaced', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final staleStorage = MemoryExtensionStorage();
      final tokenKey = 'token|$serverUrl|$apiKey';
      staleStorage.values[tokenKey] = '"not-a-token"';
      final staleClient =
          clientWith(config, {'serverUrl': serverUrl, 'apiKey': apiKey}, staleStorage);
      expect(await staleClient.getGallery(page: 1), isNotEmpty);
      expect(staleStorage.values[tokenKey], isNot('"not-a-token"'));
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
      final second = await client.getGallery(page: 2, feed: 'all');
      final firstUids = catalogue.map((item) => item.uid).toSet();
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
        'serverUrl': serverUrl,
        'apiKey': apiKey,
        'libraries': 'no such library',
      });
      await expectLater(filtered.getGallery(page: 1), throwsA(anything));
    });

    test('opens a series and reads the first chapter', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final concrete = await client.getConcrete(uid: catalogue.first.uid, data: const {});
      expect(concrete.title, catalogue.first.title);
      final chapters = concrete.groups.expand((group) => group.elements).toList();
      expect(chapters, isNotEmpty);
      for (final chapter in chapters) {
        expect(chapter.title, isNot(contains('100000')));
      }
      final pages = await client.getPages(uid: chapters.first.uid, data: chapters.first.data);
      expect(pages.value, isNotEmpty);
      expect(await probeContentType(pages.value.first, const {}), startsWith('image/'));
    });

    test('an unknown series is reported as not found', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      await expectLater(
          client.getConcrete(uid: '987654321', data: const {}), throwsA(anything));
    });
  });
}
