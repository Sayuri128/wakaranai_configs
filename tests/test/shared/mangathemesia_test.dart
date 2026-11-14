import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/scraper_helpers.dart';
import '../helpers/script_bundle.dart';

MangaApiClient clientFor(String directory, ConfigInfo config) {
  return MangaApiClient(code: bundleScript(scriptPath('$directory/main.capyscript')), host: hostFor(config));
}

void main() {
  group('Kingofshojo', () {
    late ConfigInfo config;
    late MangaApiClient client;

    setUpAll(() {
      config = loadConfig('manga/king_of_shojo');
      client = clientFor('manga/king_of_shojo', config);
    });

    test('every feed lists series under the manga directory', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items, isNotEmpty, reason: feed);
        for (final item in items) {
          expect(item.uid, startsWith('manga/'));
          expect(item.cover, startsWith('https://'));
        }
      }
    });

    test('pages, search and status filter', () async {
      final first = await client.getGallery(page: 1, feed: 'popular');
      final second = await client.getGallery(page: 2, feed: 'popular');
      expect(second.first.uid, isNot(first.first.uid));
      expect(await client.getGallery(page: 9999, feed: 'popular'), isEmpty);
      final results = await client.getGallery(page: 1, query: 'fake princess');
      expect(results.map((item) => item.uid), contains('manga/no-place-for-the-fake-princess'));
      final completed = await client.getGallery(
        page: 1,
        feed: 'popular',
        filters: [
          FilterDataOneOfMultiple(
            selected: 'completed',
            filter: config.filters.firstWhere((filter) => filter.param == 'status')
                as GalleryFilterOneOfMultiple,
          ),
        ],
      );
      final detailed = await client.getConcrete(uid: completed.first.uid, data: {});
      expect(detailed.status, MangaStatus.RELEASED);
    });

    test('title, chapters and pages', () async {
      final concrete = await client.getConcrete(uid: 'manga/no-place-for-the-fake-princess', data: {});
      expect(concrete.title, 'No Place for the Fake Princess');
      expect(concrete.tags, contains('Manhwa'));
      expect(concrete.alternativeTitles, isNotEmpty);
      expect(concrete.year, 2023);
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(100));
      expect(chapters.first.number, greaterThan(chapters.last.number!));
      expect(chapters.first.timestamp, matches(r'^\d{4}-\d{2}-\d{2}$'));
      final pages = await client.getPages(uid: chapters.first.uid, data: {});
      expect(pages.value, isNotEmpty);
      expect(pages.value.first, startsWith('https://'));
    });
  });

  group('Sushiscan', () {
    late ConfigInfo config;
    late MangaApiClient client;

    setUpAll(() {
      config = loadConfig('manga/sushiscan');
      client = clientFor('manga/sushiscan', config);
    });

    test('lists the catalogue directory', () async {
      final items = await client.getGallery(page: 1, feed: 'popular');
      expect(items, isNotEmpty);
      expect(items.every((item) => item.uid.startsWith('catalogue/')), isTrue);
    });

    test('reads French details and dates', () async {
      final concrete = await client.getConcrete(uid: 'catalogue/dragon-ball-super', data: {});
      expect(concrete.title, 'Dragon Ball Super');
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.authors, contains('Toriyama Akira'));
      expect(concrete.artists, contains('Toyotaro'));
      expect(concrete.year, 2015);
      expect(concrete.tags, containsAll(['Manga', 'Action']));
      final chapters = concrete.groups.single.elements;
      expect(chapters.first.title, 'Volume 24');
      expect(chapters.first.timestamp, '2025-11-20');
      final pages = await client.getPages(uid: chapters.first.uid, data: {});
      expect(pages.value.length, greaterThan(100));
    });
  });
}
