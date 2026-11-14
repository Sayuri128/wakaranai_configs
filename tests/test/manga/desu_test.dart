import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String rentAGirlfriendUid = '2911';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/desu');
    client = MangaApiClient(
      code: readScript('manga/desu'),
      host: hostFor(config),
    );
  });

  GalleryFilterMultipleOfMultiple filterFor(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterMultipleOfMultiple;
  }

  group('getGallery', () {
    test('feeds list numeric uids with covers', () async {
      for (final feed in ['popular', 'updates', 'new']) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.length, greaterThan(10), reason: feed);
        for (final item in items) {
          expect(item.uid, matches(r'^\d+$'));
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://static.desu.uno/'));
        }
      }
    });

    test('pages move forward', () async {
      final first = await client.getGallery(page: 1, feed: 'popular');
      final second = await client.getGallery(page: 2, feed: 'popular');
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('search finds a title and stops after page 1', () async {
      final results = await client.getGallery(page: 1, query: 'naruto');
      expect(results.map((item) => item.uid), contains('29'));
      final next = await client.getGallery(page: 2, query: 'naruto');
      expect(next, isEmpty);
    });

    test('kind and genre filters narrow the catalog', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'popular',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['manhwa'],
            ],
            filter: filterFor('kinds'),
          ),
          FilterDataMultipleOfMultiple(
            selected: [
              ['50-Drama'],
            ],
            filter: filterFor('genres'),
          ),
        ],
      );
      expect(items, isNotEmpty);
      final concrete =
          await client.getConcrete(uid: items.first.uid, data: {});
      expect(concrete.tags, containsAll(['Манхва', 'Драма']));
    });
  });

  group('title', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: rentAGirlfriendUid, data: {});
    });

    test('has details', () {
      expect(concrete.title, 'Девушка на час');
      expect(concrete.alternativeTitles, contains('Rent-A-Girlfriend'));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.year, 2017);
      expect(concrete.tags, contains('Романтика'));
      expect(concrete.url, 'https://desu.uno/manga/rent-a-girlfriend.2911/');
    });

    test('lists chapters with volume and number', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(400));
      final first = chapters.last;
      expect(first.uid, '2911/246039');
      expect(first.title, 'Том 1 Глава 1 - Она - Мизухара Чизуру');
      expect(first.number, 1);
      expect(first.volume, 1);
      expect(first.timestamp, isNotEmpty);
    });

    test('pages load with the image headers', () async {
      final pages = await client.getPages(uid: '2911/246039', data: {});
      expect(pages.value.length, greaterThan(10));
      expect(pages.value.first, startsWith('https://img'));
      final headers = await client.getImageHeaders(uid: '2911/246039', data: {});
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
}
