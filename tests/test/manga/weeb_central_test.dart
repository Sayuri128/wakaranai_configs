import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String onePiece = '01J76XY7E9FNDZ1DBBM6PBJPFK';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    config = loadConfig('manga/weeb_central');
    client = MangaApiClient(code: readScript('manga/weeb_central'), host: hostFor(config));
    concrete = await client.getConcrete(uid: onePiece, data: {});
  });

  group('getGallery', () {
    test('every feed lists series with covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items, hasLength(32), reason: feed);
        for (final item in items) {
          expect(item.uid, matches(r'^[0-9A-Z]{26}$'));
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://temp.compsci88.com/cover/'));
        }
      }
    });

    test('pages move forward', () async {
      final first = await client.getGallery(page: 1, feed: 'Popularity');
      final second = await client.getGallery(page: 2, feed: 'Popularity');
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('type filter narrows the catalog', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'Popularity',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['Manhwa'],
            ],
            filter: config.filters.firstWhere((filter) => filter.param == 'included_type')
                as GalleryFilterMultipleOfMultiple,
          ),
        ],
      );
      expect(items, isNotEmpty);
      final detailed = await client.getConcrete(uid: items.first.uid, data: {});
      expect(detailed.tags, contains('Manhwa'));
    });

    test('search finds a series', () async {
      final results = await client.getGallery(page: 1, query: 'one piece');
      expect(results.map((item) => item.uid), contains(onePiece));
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(concrete.title, 'One Piece');
      expect(concrete.authors, contains('ODA Eiichiro'));
      expect(concrete.tags, containsAll(['Manga', 'Action']));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.year, 1997);
      expect(concrete.description, startsWith('As a child, Monkey D. Luffy'));
    });

    test('lists every chapter newest first', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThan(1190));
      expect(chapters.last.title, 'Chapter 1');
      expect(chapters.last.number, 1);
      expect(chapters.first.number, greaterThan(1190));
      expect(chapters.first.timestamp, matches(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'));
    });
  });

  test('getPages returns the chapter images', () async {
    final pages = await client.getPages(uid: concrete.groups.single.elements.last.uid, data: {});
    expect(pages.value, isNotEmpty);
    expect(pages.value.first, startsWith('https://'));
  });
}
