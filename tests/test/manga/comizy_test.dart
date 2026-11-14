import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String yiansBinding = 'yians-binding';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    config = loadConfig('manga/comizy');
    client = MangaApiClient(code: readScript('manga/comizy'), host: hostFor(config));
    concrete = await client.getConcrete(uid: yiansBinding, data: {});
  });

  group('getGallery', () {
    test('every feed lists titles with covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items, hasLength(24), reason: feed);
        for (final item in items) {
          expect(item.uid, isNot(contains('/')));
          expect(item.cover, startsWith('https://'));
        }
      }
    });

    test('pages move forward', () async {
      final first = await client.getGallery(page: 1, feed: 'views');
      final second = await client.getGallery(page: 2, feed: 'views');
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('status filter reaches the API', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'views',
        filters: [
          FilterDataOneOfMultiple(
            selected: 'completed',
            filter: config.filters.firstWhere((filter) => filter.param == 'status')
                as GalleryFilterOneOfMultiple,
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.status == MangaStatus.RELEASED), isTrue);
    });

    test('search finds a title', () async {
      final results = await client.getGallery(page: 1, query: "yian's binding");
      expect(results.map((item) => item.uid), contains(yiansBinding));
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(concrete.title, "Yian's Binding");
      expect(concrete.alternativeTitles, contains("Yian's Restraint"));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.description, contains('Benjamin'));
      expect(concrete.tags, isNotEmpty);
    });

    test('lists chapters newest first with numbers', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThanOrEqualTo(50));
      expect(chapters.first.uid, startsWith('$yiansBinding/chapter-'));
      expect(chapters.first.number, greaterThan(chapters.last.number!));
    });
  });

  test('getPages returns every page, not the three-image preview', () async {
    final pages = await client.getPages(uid: '$yiansBinding/chapter-49', data: {});
    expect(pages.value.length, greaterThan(20));
    expect(pages.value.first, contains('cmzcdn.org'));
  });
}
