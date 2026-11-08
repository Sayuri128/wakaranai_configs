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

const String onePieceUid = 'manga/2/one-piece';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/mangapill');
    client = MangaApiClient(
      code: readScript('manga/mangapill'),
      host: hostFor(config),
    );
  });

  GalleryFilterOneOfMultiple oneOfFilter(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterOneOfMultiple;
  }

  GalleryFilterMultipleOfMultiple genreFilter() {
    return config.filters.firstWhere((filter) => filter.param == 'genre')
        as GalleryFilterMultipleOfMultiple;
  }

  group('getGallery', () {
    test('latest chapters list unique titles with their chapter', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [],
        feed: 'latest',
      );
      expect(items.length, greaterThan(20));
      expect(items.map((item) => item.uid).toSet().length, items.length);
      for (final item in items) {
        expect(item.uid, startsWith('manga/'));
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://'));
        expect(item.latestChapter, startsWith('Chapter '));
      }
      final next = await client.getGallery(
        page: 2,
        query: '',
        filters: [],
        feed: 'latest',
      );
      expect(next, isEmpty);
    });

    test('trending lists titles with type, year and status', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [],
        feed: 'trending',
      );
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.uid, startsWith('manga/'));
        expect(item.subtitle, isNotNull);
        expect(item.year, isNotNull);
        expect(item.status, isNot(MangaStatus.UNDEFINED));
      }
    });

    test('browse pages through manga', () async {
      final first = await client.getGallery(
        page: 1,
        query: '',
        filters: [],
        feed: 'browse',
      );
      final second = await client.getGallery(
        page: 2,
        query: '',
        filters: [],
        feed: 'browse',
      );
      expect(first.length, 50);
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
      expect(first.every((item) => item.subtitle == 'manga'), isTrue);
      expect(first.first.tags, isNotEmpty);
    });

    test('searches across feeds', () async {
      final results = await client.getGallery(
        page: 1,
        query: 'one piece',
        filters: [],
        feed: 'latest',
      );
      expect(results.map((item) => item.uid), contains(onePieceUid));
    });

    test('filters by type, status and genre', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [
          FilterDataOneOfMultiple(
            selected: 'manhua',
            filter: oneOfFilter('type'),
          ),
          FilterDataOneOfMultiple(
            selected: 'finished',
            filter: oneOfFilter('status'),
          ),
          FilterDataMultipleOfMultiple(
            selected: [
              ['Fantasy'],
            ],
            filter: genreFilter(),
          ),
        ],
        feed: 'trending',
      );
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.subtitle, 'manhua');
        expect(item.status, MangaStatus.RELEASED);
        expect(item.tags, contains('Fantasy'));
      }
    });
  });

  group('title', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: onePieceUid, data: {});
    });

    test('has details', () {
      expect(concrete.uid, onePieceUid);
      expect(concrete.title, 'One Piece');
      expect(concrete.description, contains('Pirate King'));
      expect(concrete.tags, containsAll(['Action', 'Adventure']));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.year, 1997);
      expect(concrete.url, 'https://mangapill.com/$onePieceUid');
      expect(concrete.cover, startsWith('https://'));
    });

    test('lists numbered chapters newest first', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(1000));
      expect(chapters.first.uid, startsWith('chapters/2-'));
      expect(chapters.last.title, 'Chapter 1');
      expect(chapters.last.number, 1);
      expect(chapters.first.number, greaterThan(chapters.last.number!));
    });

    test('pages load with the image headers', () async {
      final chapter = concrete.groups.single.elements.last;
      final pages = await client.getPages(uid: chapter.uid, data: {});
      expect(pages.value.length, greaterThan(10));
      final headers = await client.getImageHeaders(uid: chapter.uid, data: {});
      expect(headers['Referer'], 'https://mangapill.com/');
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

  test('reads the alternative title', () async {
    final concrete = await client.getConcrete(
      uid: 'https://mangapill.com/manga/9463/splatoon-bankara',
      data: {},
    );
    expect(concrete.uid, 'manga/9463/splatoon-bankara');
    expect(concrete.alternativeTitles, contains('Splatoon 3: Splatlands'));
  });

  test('reports a missing title as not found', () async {
    await expectSourceError(
      () => client.getConcrete(uid: 'manga/99999999/missing', data: {}),
      SourceErrorKind.notFound,
    );
  });

  test('reports a missing chapter as not found', () async {
    await expectSourceError(
      () => client.getPages(
        uid: 'chapters/99999999-10001000/missing-chapter-1',
        data: {},
      ),
      SourceErrorKind.notFound,
    );
  });
}
