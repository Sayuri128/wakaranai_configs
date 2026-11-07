import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String titleDir = 'ranker-who-lives-a-second-time_';
const String removedTitleDir = '<29.04.2026>omniscient-reader_';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/remanga');
    client = MangaApiClient(
      code: readScript('manga/remanga'),
      host: hostFor(config),
    );
  });

  group('getGallery', () {
    test('lists the catalogue with covers and metadata', () async {
      final items = await client.getGallery(page: 1, query: '', filters: []);
      expect(items, hasLength(30));
      for (final item in items) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://remanga.org/media/'));
      }
      expect(items.any((item) => item.tags.isNotEmpty), isTrue);
    });

    test('pages through the catalogue', () async {
      final first = await client.getGallery(page: 1, query: '', filters: []);
      final second = await client.getGallery(page: 2, query: '', filters: []);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('filters by type', () async {
      final typeFilter = config.filters.firstWhere(
        (filter) => filter.param == 'types',
      ) as GalleryFilterMultipleOfMultiple;
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['1'],
            ],
            filter: typeFilter,
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.subtitle == 'Манга'), isTrue);
    });

    test('searches', () async {
      final results =
          await client.getGallery(page: 1, query: 'Solo Leveling', filters: []);
      expect(results.map((item) => item.uid), contains('solo-leveling_'));
    });
  });

  group('title', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: titleDir, data: {});
    });

    test('has details', () {
      expect(concrete.title, 'Ранкер, который живёт второй раз');
      expect(concrete.alternativeTitles, isNotEmpty);
      expect(concrete.authors, isNotEmpty);
      expect(concrete.description, isNotEmpty);
      expect(concrete.tags, isNotEmpty);
      expect(concrete.url, 'https://remanga.org/manga/$titleDir');
    });

    test('lists chapters per translation branch in reading order', () {
      expect(concrete.groups, isNotEmpty);
      final chapters = concrete.groups.first.elements;
      expect(chapters, isNotEmpty);
      expect(chapters.first.title, startsWith('Том 1 Глава 1'));
    });

    test('pages load with the image headers', () async {
      final pages =
          await client.getPages(uid: concrete.groups.first.elements.first.uid, data: {});
      expect(pages.value, isNotEmpty);
      final headers = await client.getImageHeaders(
        uid: concrete.groups.first.elements.first.uid,
        data: {},
      );
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse(pages.value.first));
        headers.forEach(request.headers.set);
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(response.headers.contentType?.primaryType, 'image');
        await response.drain<void>();
      } finally {
        httpClient.close();
      }
    });
  });

  test('opens titles whose dir needs escaping', () async {
    final removed = await client.getConcrete(uid: removedTitleDir, data: {});
    expect(removed.title, 'Всеведущий читатель');
  });

  test('reports a missing title as not found', () async {
    await expectSourceError(
      () => client.getConcrete(uid: 'no-such-title-wakaranai', data: {}),
      SourceErrorKind.notFound,
    );
  });
}
