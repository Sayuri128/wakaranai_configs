import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String onePiecePath = 'manga/one-piece';
const String kakalotMirror = 'https://www.kakamanga.com';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  MangaApiClient clientWith(Map<String, Object?> preferences) {
    return MangaApiClient(
      code: readScript('manga/manganato'),
      host: hostFor(config, preferences: preferences),
    );
  }

  setUpAll(() {
    config = loadConfig('manga/manganato');
    client = clientWith({});
  });

  FilterDataOneOfMultiple genre(String slug) {
    final filter =
        config.filters.firstWhere((filter) => filter.param == 'genre')
            as GalleryFilterOneOfMultiple;
    return FilterDataOneOfMultiple(selected: slug, filter: filter);
  }

  group('getGallery', () {
    test('declares the four feeds and no search', () {
      expect(config.feeds.map((feed) => feed.id), [
        'latest',
        'popular',
        'new',
        'completed',
      ]);
      expect(config.searchAvailable, isFalse);
    });

    for (final feed in ['latest', 'popular', 'new', 'completed']) {
      test('lists the $feed feed', () async {
        final items = await client.getGallery(page: 1, query: '', feed: feed);
        expect(items.length, greaterThanOrEqualTo(20));
        for (final item in items) {
          expect(item.uid, startsWith('manga/'));
          expect(item.uid.split('/'), hasLength(2));
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://'));
        }
      });
    }

    test('pages through a feed', () async {
      final first = await client.getGallery(
        page: 1,
        query: '',
        feed: 'popular',
      );
      final second = await client.getGallery(
        page: 2,
        query: '',
        feed: 'popular',
      );
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('filters by genre', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        feed: 'popular',
        filters: [genre('yuri')],
      );
      expect(items, isNotEmpty);
      final concrete = await client.getConcrete(uid: items.first.uid, data: {});
      expect(concrete.tags, contains('Yuri'));
    });

    test('returns nothing past the last page', () async {
      final items = await client.getGallery(
        page: 9999,
        query: '',
        feed: 'completed',
        filters: [genre('yuri')],
      );
      expect(items, isEmpty);
    });

    test('reports search as unsupported', () async {
      await expectSourceError(
        () => client.getGallery(page: 1, query: 'one piece', feed: 'latest'),
        SourceErrorKind.unsupported,
      );
    });
  });

  group('title', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: onePiecePath, data: {});
    });

    test('has details', () {
      expect(concrete.uid, onePiecePath);
      expect(concrete.title, 'One Piece');
      expect(concrete.authors.join(' '), contains('Oda Eiichirou'));
      expect(concrete.tags, containsAll(['Action', 'Adventure']));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.description, isNotEmpty);
      expect(concrete.description, isNot(contains('summary:')));
      expect(concrete.rating, greaterThan(5));
      expect(concrete.cover, startsWith('https://'));
      expect(concrete.url, 'https://www.manganato.gg/$onePiecePath');
    });

    test('lists every chapter through the paged chapter api', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(1000));
      expect(
        chapters.map((chapter) => chapter.uid).toSet().length,
        chapters.length,
      );
      final first = chapters.firstWhere(
        (chapter) => chapter.uid == '$onePiecePath/chapter-1',
      );
      expect(first.title, 'Chapter 1');
      expect(first.number, 1);
      expect(
        first.timestamp,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')),
      );
    });

    test('pages load with the image headers', () async {
      final pages = await client.getPages(
        uid: '$onePiecePath/chapter-1',
        data: {},
      );
      expect(pages.value.length, greaterThan(10));
      final headers = await client.getImageHeaders(
        uid: '$onePiecePath/chapter-1',
        data: {},
      );
      expect(headers['Referer'], 'https://www.manganato.gg/');
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

  test('reads the same paths through the Mangakakalot mirror', () async {
    final mirrored = clientWith({'__mirror': kakalotMirror});
    final items = await mirrored.getGallery(page: 1, query: '', feed: 'latest');
    expect(items, isNotEmpty);
    expect(items.first.uid, startsWith('manga/'));
    final headers = await mirrored.getImageHeaders(uid: '', data: {});
    expect(headers['Referer'], '$kakalotMirror/');
  });

  test('reports a missing title as not found', () async {
    await expectSourceError(
      () => client.getConcrete(uid: 'manga/zzzz-no-such-title-qq', data: {}),
      SourceErrorKind.notFound,
    );
  });
}
