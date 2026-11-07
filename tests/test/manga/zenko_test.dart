import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String barbarianId = '34';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/zenko');
    client = MangaApiClient(
      code: readScript('manga/zenko'),
      host: hostFor(config),
    );
  });

  GalleryFilterMultipleOfMultiple filterFor(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterMultipleOfMultiple;
  }

  group('getGallery', () {
    test('lists the catalogue without novels', () async {
      final items = await client.getGallery(page: 1, query: '', filters: []);
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://storage.zenko.online/'));
        expect(item.subtitle, isNot('Ранобе'));
      }
    });

    test('pages through the catalogue', () async {
      final first = await client.getGallery(page: 1, query: '', filters: []);
      final second = await client.getGallery(page: 2, query: '', filters: []);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('filters by type and genre names', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['MANGA'],
            ],
            filter: filterFor('categories'),
          ),
          FilterDataMultipleOfMultiple(
            selected: [
              ['Наукова фантастика'],
            ],
            filter: filterFor('genres'),
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.subtitle == 'Манґа'), isTrue);
    });

    test('searches', () async {
      final results =
          await client.getGallery(page: 1, query: 'варвар', filters: []);
      expect(results.map((item) => item.uid), contains(barbarianId));
    });
  });

  group('title', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: barbarianId, data: {});
    });

    test('has details', () {
      expect(concrete.title, 'Виживання у грі за варвара');
      expect(concrete.alternativeTitles,
          contains('Surviving the Game as a Barbarian'));
      expect(concrete.description, isNotEmpty);
      expect(concrete.tags, contains('Ісекай'));
      expect(concrete.url, 'https://zenko.online/titles/$barbarianId');
    });

    test('groups chapters by team with decoded names', () {
      final chapters = concrete.groups.first.elements;
      expect(chapters, isNotEmpty);
      expect(chapters.first.title, 'Том 1 Розділ 1 - Навчання');
      expect(chapters.first.number, 1);
      expect(int.tryParse(chapters.first.timestamp ?? ''), isNotNull);
    });

    test('pages load with the image headers', () async {
      final chapter = concrete.groups.first.elements.first;
      final pages = await client.getPages(uid: chapter.uid, data: {});
      expect(pages.value, isNotEmpty);
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
      () => client.getConcrete(uid: '99999999', data: {}),
      SourceErrorKind.notFound,
    );
  });
}
