import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String kenganOmega = 'kengan-omega.22093';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    config = loadConfig('manga/manga_katana');
    client = MangaApiClient(code: readScript('manga/manga_katana'), host: hostFor(config));
    concrete = await client.getConcrete(uid: kenganOmega, data: {});
  });

  group('getGallery', () {
    test('every feed lists titles with covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.length, greaterThanOrEqualTo(15), reason: feed);
        for (final item in items) {
          expect(item.uid, matches(r'^[^/]+\.\d+$'));
          expect(item.cover, startsWith('https://mangakatana.com/imgs/cover/'));
        }
      }
    });

    test('pages move forward and end past the last one', () async {
      final first = await client.getGallery(page: 1, feed: 'latest');
      final second = await client.getGallery(page: 2, feed: 'latest');
      expect(second.first.uid, isNot(first.first.uid));
      expect(await client.getGallery(page: 99999, feed: 'latest'), isEmpty);
    });

    test('genre and status filters narrow the list', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'latest',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['martial-arts'],
            ],
            filter: config.filters.firstWhere((filter) => filter.param == 'include')
                as GalleryFilterMultipleOfMultiple,
          ),
          FilterDataOneOfMultiple(
            selected: '2',
            filter: config.filters.firstWhere((filter) => filter.param == 'status')
                as GalleryFilterOneOfMultiple,
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.status == MangaStatus.RELEASED), isTrue);
      final detailed = await client.getConcrete(uid: items.first.uid, data: {});
      expect(detailed.tags, contains('Martial Arts'));
    });

    test('search finds a title', () async {
      final results = await client.getGallery(page: 1, query: 'kengan omega');
      expect(results.map((item) => item.uid), contains(kenganOmega));
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(concrete.title, 'Kengan Omega');
      expect(concrete.alternativeTitles, contains('Kengan Asura 2'));
      expect(concrete.authors, contains('Sandrovich Yabako'));
      expect(concrete.tags, contains('Martial Arts'));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.description, contains('Kengan Asura'));
    });

    test('lists chapters with numbers and dates', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(370));
      expect(chapters.last.uid, '$kenganOmega/c0');
      expect(chapters.map((chapter) => chapter.uid), contains('$kenganOmega/c1'));
      expect(chapters.first.timestamp, matches(r'^\d{4}-\d{2}-\d{2}$'));
    });
  });

  test('getPages returns real image bytes', () async {
    final pages = await client.getPages(uid: '$kenganOmega/c377', data: {});
    expect(pages.value.length, greaterThan(10));
    final headers = await client.getImageHeaders(uid: '$kenganOmega/c377', data: {});
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(pages.value.first));
      headers.forEach(request.headers.set);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      expect(response.statusCode, 200);
      final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
      final isPng = bytes[0] == 0x89 && bytes[1] == 0x50;
      final isWebp = bytes.length > 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
      expect(isJpeg || isPng || isWebp, isTrue);
    } finally {
      httpClient.close();
    }
  });
}
