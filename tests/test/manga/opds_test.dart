import 'package:capyscript/api_clients/host/extension_host.dart';
import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'manga/opds';

class Catalog {
  final String name;
  final String url;
  final String username;
  final String password;
  final String probeUrl;
  final String unavailableReason;

  const Catalog({
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.probeUrl,
    required this.unavailableReason,
  });

  bool get configured => url.isNotEmpty;

  Map<String, Object?> get preferences => {
        'catalogUrl': url,
        if (username.isNotEmpty) 'username': username,
        if (password.isNotEmpty) 'password': password,
      };
}

Catalog komgaCatalog() {
  final server = environmentValue('KOMGA_URL', 'http://localhost:25600');
  final username = environmentValue('KOMGA_USERNAME');
  return Catalog(
    name: 'Komga',
    url: username.isEmpty ? '' : '$server/opds/v1.2/series',
    username: username,
    password: environmentValue('KOMGA_PASSWORD'),
    probeUrl: '$server/api/v1/claim',
    unavailableReason: 'Komga is not reachable; set KOMGA_URL, KOMGA_USERNAME and KOMGA_PASSWORD',
  );
}

Catalog kavitaCatalog() {
  final server = environmentValue('KAVITA_URL', 'http://localhost:5000');
  final apiKey = environmentValue('KAVITA_API_KEY');
  final library = environmentValue('KAVITA_OPDS_LIBRARY', '1');
  return Catalog(
    name: 'Kavita',
    url: apiKey.isEmpty ? '' : '$server/api/opds/$apiKey/libraries/$library',
    username: '',
    password: '',
    probeUrl: '$server/api/health',
    unavailableReason: 'Kavita is not reachable; set KAVITA_URL and KAVITA_API_KEY',
  );
}

Catalog customCatalog() {
  final url = environmentValue('OPDS_URL');
  return Catalog(
    name: 'OPDS_URL',
    url: url,
    username: environmentValue('OPDS_USERNAME'),
    password: environmentValue('OPDS_PASSWORD'),
    probeUrl: url,
    unavailableReason: 'set OPDS_URL (and OPDS_USERNAME / OPDS_PASSWORD) to test another catalog',
  );
}

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

void catalogTests(Catalog catalog) {
  group(catalog.name, () {
    late ConfigInfo config;
    late MangaApiClient client;
    late List<MangaGalleryView> firstPage;
    var available = false;

    setUpAll(() async {
      config = loadConfig(extensionDirectory);
      available = catalog.configured && await isReachable(catalog.probeUrl);
      if (available == false) {
        return;
      }
      client = clientWith(config, catalog.preferences, MemoryExtensionStorage());
      firstPage = await client.getGallery(page: 1);
    });

    test('lists catalog entries as titles', () {
      if (skipUnless(available, catalog.unavailableReason)) {
        return;
      }
      expect(firstPage, isNotEmpty);
      for (final item in firstPage) {
        expect(item.title, isNotEmpty);
        expect(item.uid, anyOf(startsWith('feed|'), startsWith('book|')));
      }
    });

    test('follows next links for later pages', () async {
      if (skipUnless(available, catalog.unavailableReason)) {
        return;
      }
      final secondPage = await client.getGallery(page: 2);
      final firstUids = firstPage.map((item) => item.uid).toSet();
      expect(secondPage.map((item) => item.uid).toSet().intersection(firstUids), isEmpty);
      final fresh = clientWith(config, catalog.preferences, MemoryExtensionStorage());
      final walked = await fresh.getGallery(page: 2);
      expect(walked.map((item) => item.uid), secondPage.map((item) => item.uid));
    });

    test('searches through the OpenSearch description', () async {
      if (skipUnless(available, catalog.unavailableReason)) {
        return;
      }
      final wanted = firstPage.first;
      final results = await client.getGallery(page: 1, query: wanted.title);
      expect(results.map((item) => item.title), contains(wanted.title));
    });

    test('opens a title and streams the pages of its first book', () async {
      if (skipUnless(available, catalog.unavailableReason)) {
        return;
      }
      final item = firstPage.first;
      final concrete = await client.getConcrete(uid: item.uid, data: item.data);
      final books = concrete.groups.expand((group) => group.elements).toList();
      expect(books, isNotEmpty);
      final pages = await client.getPages(uid: books.first.uid, data: books.first.data);
      expect(pages.value, isNotEmpty);
      for (final url in pages.value) {
        expect(url, isNot(contains('{pageNumber}')));
      }
      final headers = await client.getImageHeaders(uid: books.first.uid, data: const {});
      expect(await probeContentType(pages.value.first, headers), startsWith('image/'));
      expect(await probeContentType(pages.value.last, headers), startsWith('image/'));
    });

    test('a wrong password asks the user to sign in again', () async {
      final reason = catalog.username.isEmpty
          ? '${catalog.name} catalog is tested without a login'
          : catalog.unavailableReason;
      if (skipUnless(available && catalog.username.isNotEmpty, reason)) {
        return;
      }
      final wrong = clientWith(config, {
        ...catalog.preferences,
        'password': 'not-the-password',
      });
      await expectSourceError(() => wrong.getGallery(page: 1), SourceErrorKind.loginRequired);
    });
  });
}

void main() {
  late ConfigInfo config;

  setUpAll(() {
    config = loadConfig(extensionDirectory);
  });

  group('settings', () {
    test('declares api 2 with catalog and login settings', () {
      expect(config.apiVersion, 2);
      expect(config.preferences.map((preference) => preference.key),
          ['catalogUrl', 'username', 'password']);
    });

    test('asks for the catalog address when it is missing', () async {
      final client = clientWith(config, const {});
      final error = await expectSourceError(
          () => client.getGallery(page: 1), SourceErrorKind.loginRequired);
      expect(error.message, contains('catalog address'));
    });

    test('reports an unreachable catalog as down', () async {
      final client = clientWith(config, {'catalogUrl': 'http://127.0.0.1:9/opds'});
      await expectSourceError(() => client.getGallery(page: 1), SourceErrorKind.sourceDown);
    });

    test('books without page streaming are unsupported', () async {
      final client = clientWith(config, {'catalogUrl': 'http://127.0.0.1:9/opds'});
      await expectSourceError(
          () => client.getPages(uid: 'none|0|/book.epub', data: const {}),
          SourceErrorKind.unsupported);
    });

    test('page streaming links expand to one url per page', () async {
      final client = clientWith(config, {'catalogUrl': 'https://example.org/opds/catalog'});
      final pages = await client.getPages(
          uid: 'pse|3|/opds/books/7/pages/{pageNumber}?width={maxWidth}', data: const {});
      expect(pages.value, [
        'https://example.org/opds/books/7/pages/0?width=4000',
        'https://example.org/opds/books/7/pages/1?width=4000',
        'https://example.org/opds/books/7/pages/2?width=4000',
      ]);
    });
  });

  catalogTests(komgaCatalog());
  catalogTests(kavitaCatalog());
  catalogTests(customCatalog());

  group('Komga catalog root', () {
    final server = environmentValue('KOMGA_URL', 'http://localhost:25600');
    final username = environmentValue('KOMGA_USERNAME');
    final password = environmentValue('KOMGA_PASSWORD');
    var available = false;

    setUpAll(() async {
      available = username.isNotEmpty && await isReachable('$server/api/v1/claim');
    });

    test('a folder entry explains how to browse it', () async {
      if (skipUnless(available, 'Komga is not reachable; set KOMGA_URL, KOMGA_USERNAME and KOMGA_PASSWORD')) {
        return;
      }
      final client = clientWith(config, {
        'catalogUrl': '$server/opds/v1.2/catalog',
        'username': username,
        'password': password,
      });
      final root = await client.getGallery(page: 1);
      final allSeries = root.firstWhere((item) => item.uid.endsWith('/opds/v1.2/series'));
      final concrete = await client.getConcrete(uid: allSeries.uid, data: allSeries.data);
      expect(concrete.groups, isEmpty);
      expect(concrete.description, contains('$server/opds/v1.2/series'));
      final latestBooks = root.firstWhere((item) => item.uid.endsWith('/opds/v1.2/books/latest'));
      final books = await client.getConcrete(uid: latestBooks.uid, data: latestBooks.data);
      expect(books.groups.expand((group) => group.elements), isNotEmpty);
    });
  });
}
