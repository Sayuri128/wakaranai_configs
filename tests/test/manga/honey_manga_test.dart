import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String pickMeUpId = '52e6a78a-8930-4265-b0eb-f77c0dcb6b96';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/honey_manga');
    client = MangaApiClient(
      code: readScript('manga/honey_manga'),
      host: hostFor(config),
    );
  });

  group('getGallery', () {
    test('lists the catalogue with covers', () async {
      final items = await client.getGallery(page: 1, query: '', filters: []);
      expect(items, hasLength(30));
      for (final item in items) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://hmvolumestorage.b-cdn.net/'));
      }
    });

    test('pages through the catalogue', () async {
      final first = await client.getGallery(page: 1, query: '', filters: []);
      final second = await client.getGallery(page: 2, query: '', filters: []);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('filters by type and genre', () async {
      final typeFilter = config.filters.firstWhere(
        (filter) => filter.param == 'type',
      ) as GalleryFilterOneOfMultiple;
      final genreFilter = config.filters.firstWhere(
        (filter) => filter.param == 'genres',
      ) as GalleryFilterMultipleOfMultiple;
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [
          FilterDataOneOfMultiple(selected: 'Манґа', filter: typeFilter),
          FilterDataMultipleOfMultiple(
            selected: [
              ['Драма'],
            ],
            filter: genreFilter,
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.subtitle == 'Манґа'), isTrue);
      expect(items.every((item) => item.tags.contains('Драма')), isTrue);
    });

    test('searches', () async {
      final results =
          await client.getGallery(page: 1, query: 'Обери мене', filters: []);
      expect(results.map((item) => item.uid), contains(pickMeUpId));
    });
  });

  group('title', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: pickMeUpId, data: {});
    });

    test('has details', () {
      expect(concrete.title, 'Обери мене!');
      expect(concrete.alternativeTitles, contains('Pick Me Up!'));
      expect(concrete.description, isNotEmpty);
      expect(concrete.authors, isNotEmpty);
      expect(concrete.status, MangaStatus.ONGOING);
    });

    test('lists free chapters in reading order', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(200));
      expect(chapters.first.title, 'Том 1 Розділ 1');
    });

    test('pages load with the image headers', () async {
      final chapter = concrete.groups.single.elements.first;
      final pages = await client.getPages(uid: chapter.uid, data: {});
      expect(pages.value.length, greaterThan(10));
      final headers = await client.getImageHeaders(uid: chapter.uid, data: {});
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

  test('reports a missing title as not found', () async {
    await expectSourceError(
      () => client.getConcrete(
        uid: '00000000-0000-0000-0000-000000000000',
        data: {},
      ),
      SourceErrorKind.notFound,
    );
  });
}
