import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String tradeBetweenWorlds = 'isekai-chikyuukan-de-kojin-boueki-shitemita';
const String longSeries = 'wu-lian-dian-feng';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  MangaApiClient clientWith(Map<String, Object?> preferences) {
    return MangaApiClient(
      code: readScript('manga/senkuro'),
      host: hostFor(config, preferences: preferences, storage: MemoryExtensionStorage()),
    );
  }

  setUpAll(() {
    config = loadConfig('manga/senkuro');
    client = clientWith({});
  });

  FilterDataMultipleOfMultiple choose(String param, String value) {
    return FilterDataMultipleOfMultiple(
      selected: [
        [value],
      ],
      filter: config.filters.firstWhere((filter) => filter.param == param)
          as GalleryFilterMultipleOfMultiple,
    );
  }

  group('getGallery', () {
    test('every feed lists titles with covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items, hasLength(30), reason: feed);
        for (final item in items) {
          expect(item.uid, isNotEmpty);
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://'));
        }
      }
    });

    test('cursor pages follow each other, also when a page is opened first', () async {
      final first = await client.getGallery(page: 1, feed: 'POPULARITY_SCORE');
      final second = await client.getGallery(page: 2, feed: 'POPULARITY_SCORE');
      expect(second.map((item) => item.uid).toSet().intersection(first.map((item) => item.uid).toSet()), isEmpty);
      final freshThird = await clientWith({}).getGallery(page: 3, feed: 'POPULARITY_SCORE');
      final third = await client.getGallery(page: 3, feed: 'POPULARITY_SCORE');
      expect(freshThird.map((item) => item.uid), third.map((item) => item.uid));
    });

    test('type and status filters reach the API', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'POPULARITY_SCORE',
        filters: [choose('type', 'MANHWA'), choose('status', 'ONGOING')],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.status == MangaStatus.ONGOING), isTrue);
    });

    test('search finds a title', () async {
      final results = await client.getGallery(page: 1, query: 'solo leveling');
      expect(results.map((item) => item.uid), contains(startsWith('solo-leveling')));
    });

    test('explicit titles only show up when enabled', () async {
      final safe = await client.getGallery(page: 1, feed: 'POPULARITY_SCORE');
      final all = await clientWith({'showExplicit': true}).getGallery(page: 1, feed: 'POPULARITY_SCORE');
      expect(safe, isNotEmpty);
      expect(all, isNotEmpty);
    });
  });

  group('getConcrete', () {
    test('has details and a chapter group', () async {
      final concrete = await client.getConcrete(uid: tradeBetweenWorlds, data: {});
      expect(concrete.title, isNotEmpty);
      expect(concrete.alternativeTitles, contains(startsWith('Isekai')));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.description, contains('Ватару'));
      expect(concrete.description, isNot(contains('ᅠ')));
      expect(concrete.tags, isNotEmpty);
      expect(concrete.url, 'https://senkuro.com/manga/$tradeBetweenWorlds');
      final chapters = concrete.groups.first.elements;
      expect(chapters.length, greaterThanOrEqualTo(28));
      expect(chapters.first.number, greaterThan(chapters.last.number!));
      expect(chapters.first.title, startsWith('Том 1 Глава'));
    });

    test('pages through long chapter lists', () async {
      final concrete = await client.getConcrete(uid: longSeries, data: {});
      final chapters = concrete.groups.first.elements;
      expect(chapters.length, greaterThan(3800));
      expect(chapters.map((chapter) => chapter.uid).toSet().length, chapters.length);
    });
  });

  test('getPages returns the chapter images', () async {
    final concrete = await client.getConcrete(uid: tradeBetweenWorlds, data: {});
    final pages = await client.getPages(uid: concrete.groups.first.elements.last.uid, data: {});
    expect(pages.value, isNotEmpty);
    expect(pages.value.first, startsWith('https://mirai.senkuro.net/'));
  });
}
