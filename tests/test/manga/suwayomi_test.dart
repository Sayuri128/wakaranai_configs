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

const String extensionDirectory = 'manga/suwayomi';

final String serverUrl = environmentValue('SUWAYOMI_URL', 'http://localhost:4567');
final String username = environmentValue('SUWAYOMI_USERNAME');
final String password = environmentValue('SUWAYOMI_PASSWORD');
final String browseSource = environmentValue('SUWAYOMI_SOURCE', 'Local source');
final String remoteSource = environmentValue('SUWAYOMI_REMOTE_SOURCE');
final String remoteQuery = environmentValue('SUWAYOMI_REMOTE_QUERY', 'Yotsuba&!');

const String unavailableReason =
    'Suwayomi is not reachable; set SUWAYOMI_URL (and SUWAYOMI_USERNAME + SUWAYOMI_PASSWORD when it has a login)';

MangaApiClient clientWith(
  ConfigInfo config,
  Map<String, Object?> preferences, {
  MemoryExtensionStorage? storage,
}) {
  return MangaApiClient(
    code: readScript(extensionDirectory),
    host: hostFor(
      config,
      preferences: preferences,
      storage: storage ?? MemoryExtensionStorage(),
    ),
  );
}

Map<String, Object?> credentialPreferences([Map<String, Object?> extra = const {}]) {
  return {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
    ...extra,
  };
}

void main() {
  late ConfigInfo config;
  var available = false;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    available = await isReachable('$serverUrl/api/graphql');
  });

  group('config', () {
    test('declares api 2 with library and source feeds and server settings', () {
      expect(config.apiVersion, 2);
      expect(config.multiInstance, isTrue);
      expect(config.feeds.map((feed) => feed.id), ['library', 'popular', 'latest']);
      expect(config.pagination!.defaultPageSize, 50);
      final keys = config.preferences.map((preference) => preference.key);
      expect(keys, containsAll(['serverUrl', 'username', 'password', 'source', 'searchIn', 'categories']));
      final passwordPreference = config.preferences.firstWhere((preference) => preference.key == 'password');
      expect(passwordPreference.secret, isTrue);
    });
  });

  group('settings', () {
    test('asks for the server address when it is missing', () async {
      final client = clientWith(config, const {});
      final error = await expectSourceError(
          () => client.getGallery(page: 1), SourceErrorKind.loginRequired);
      expect(error.message, contains('server address'));
    });

    test('reports an unreachable server as down', () async {
      final client = clientWith(config, {'serverUrl': 'http://127.0.0.1:9'});
      await expectSourceError(() => client.getGallery(page: 1), SourceErrorKind.sourceDown);
    });
  });

  group('live server', () {
    late MangaApiClient client;
    late List<MangaGalleryView> library;

    setUpAll(() async {
      if (available == false) {
        return;
      }
      client = clientWith(config, credentialPreferences({'source': browseSource}));
      library = await client.getGallery(page: 1, feed: 'library');
    });

    test('lists the library with authenticated covers', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      expect(library, isNotEmpty);
      final headers = await client.getImageHeaders(uid: library.first.uid, data: const {});
      expect(await probeContentType(library.first.cover, headers), startsWith('image/'));
    });

    test('library pages do not overlap', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final sized = clientWith(config, credentialPreferences({ExtensionPreference.pageSizeKey: 20}));
      final first = await sized.getGallery(page: 1, feed: 'library');
      final second = await sized.getGallery(page: 2, feed: 'library');
      final firstUids = first.map((item) => item.uid).toSet();
      expect(second.map((item) => item.uid).toSet().intersection(firstUids), isEmpty);
    });

    test('searching the library finds a title', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final librarySearch = clientWith(config, credentialPreferences({'searchIn': 'library'}));
      final wanted = library.first;
      final results = await librarySearch.getGallery(page: 1, query: wanted.title);
      expect(results.map((item) => item.uid), contains(wanted.uid));
    });

    test('the status filter keeps only titles with that status', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final statusFilter = config.filters.firstWhere((filter) => filter.param == 'status');
      final ongoing = await client.getGallery(
        page: 1,
        feed: 'library',
        filters: [FilterDataOneOfAny(selected: 'ONGOING', filter: statusFilter)],
      );
      for (final item in ongoing) {
        expect(item.status, MangaStatus.ONGOING);
      }
    });

    test('the Default category and an unknown category', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final defaultOnly = clientWith(config, credentialPreferences({'categories': 'Default'}));
      final uncategorized = await defaultOnly.getGallery(page: 1, feed: 'library');
      expect(uncategorized.length, lessThanOrEqualTo(library.length));
      final unknown = clientWith(config, credentialPreferences({'categories': 'no such category'}));
      await expectLater(unknown.getGallery(page: 1, feed: 'library'), throwsA(anything));
    });

    test('lists the installed sources when no source is chosen', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final noSource = clientWith(config, credentialPreferences());
      final error = await expectSourceError(
          () => noSource.getGallery(page: 1, feed: 'popular'), SourceErrorKind.unsupported);
      expect(error.message, contains('Installed sources'));
      final unknown = clientWith(config, credentialPreferences({'source': 'no such source'}));
      await expectSourceError(
          () => unknown.getGallery(page: 1, feed: 'popular'), SourceErrorKind.unsupported);
    });

    test('browses the chosen source', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final popular = await client.getGallery(page: 1, feed: 'popular');
      expect(popular, isNotEmpty);
      expect(await client.getGallery(page: 1, feed: 'latest'), isNotEmpty);
    });

    test('opens a title and reads the first chapter', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final concrete = await client.getConcrete(uid: library.first.uid, data: const {});
      expect(concrete.title, library.first.title);
      final chapters = concrete.groups.expand((group) => group.elements).toList();
      expect(chapters, isNotEmpty);
      expect(chapters.first.timestamp, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      final pages = await client.getPages(uid: chapters.first.uid, data: chapters.first.data);
      expect(pages.value, isNotEmpty);
      final headers = await client.getImageHeaders(uid: chapters.first.uid, data: const {});
      expect(await probeContentType(pages.value.first, headers), startsWith('image/'));
    });

    test('an unknown title is reported as not found', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      await expectSourceError(
          () => client.getConcrete(uid: '987654321', data: const {}), SourceErrorKind.notFound);
    });

    test('a wrong password asks the user to sign in again', () async {
      if (skipUnless(available && username.isNotEmpty, available ? 'set SUWAYOMI_USERNAME and SUWAYOMI_PASSWORD to test a server with a login' : unavailableReason)) {
        return;
      }
      final wrong = clientWith(config, {'serverUrl': serverUrl, 'username': username, 'password': 'not-the-password'});
      await expectSourceError(() => wrong.getGallery(page: 1), SourceErrorKind.loginRequired);
    });

    test('searches a remote source and opens a result', () async {
      if (skipUnless(available && remoteSource.isNotEmpty, 'set SUWAYOMI_REMOTE_SOURCE to search an online source')) {
        return;
      }
      final remote = clientWith(config, credentialPreferences({'source': remoteSource, 'searchIn': 'source'}));
      final results = await remote.getGallery(page: 1, query: remoteQuery);
      expect(results, isNotEmpty);
      final exact = results.where((item) => item.title.toLowerCase() == remoteQuery.toLowerCase());
      final picked = exact.isEmpty ? results.first : exact.first;
      final concrete = await remote.getConcrete(uid: picked.uid, data: const {});
      final chapters = concrete.groups.expand((group) => group.elements).toList();
      expect(chapters, isNotEmpty);
      final pages = await remote.getPages(uid: chapters.first.uid, data: chapters.first.data);
      expect(pages.value, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
