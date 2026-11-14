import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String pickMeUp = 'vyberi-menya';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    config = loadConfig('manga/manga_buff');
    client = MangaApiClient(code: readScript('manga/manga_buff'), host: hostFor(config));
    concrete = await client.getConcrete(uid: pickMeUp, data: {});
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
    test('every feed lists titles with full covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.length, greaterThan(10), reason: feed);
        for (final item in items) {
          expect(item.uid, isNot(contains('/')));
          expect(item.cover, startsWith('https://mangabuff.ru/img/manga/posters/'));
        }
      }
    });

    test('pages move forward and end past the last one', () async {
      final first = await client.getGallery(page: 1, feed: 'real_views');
      final second = await client.getGallery(page: 2, feed: 'real_views');
      expect(second.first.uid, isNot(first.first.uid));
      expect(await client.getGallery(page: 5000, feed: 'real_views'), isEmpty);
    });

    test('type and genre filters narrow the catalog', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'real_views',
        filters: [choose('type_id', '3'), choose('genres', '36')],
      );
      expect(items, isNotEmpty);
      MangaConcreteView? detailed;
      for (final item in items) {
        try {
          detailed = await client.getConcrete(uid: item.uid, data: {});
          break;
        } on SourceError catch (error) {
          expect(error.kind, SourceErrorKind.notFound);
        }
      }
      expect(detailed, isNotNull);
      expect(detailed!.tags, containsAll(['Манхва', 'Фэнтези']));
    });

    test('search finds a title', () async {
      final results = await client.getGallery(page: 1, query: 'Выбери меня');
      expect(results.map((item) => item.uid), contains(pickMeUp));
      expect(await client.getGallery(page: 2, query: 'Выбери меня'), isEmpty);
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(concrete.title, 'Выбери меня!');
      expect(concrete.alternativeTitles, contains('Pick Me Up!'));
      expect(concrete.status, MangaStatus.ONGOING);
      expect(concrete.year, 2023);
      expect(concrete.authors, contains('Hermod'));
      expect(concrete.tags, containsAll(['Манхва', 'Экшен']));
      expect(concrete.cover, startsWith('https://mangabuff.ru/img/manga/posters/'));
      expect(concrete.description, isNotEmpty);
    });

    test('loads the chapters past the first hundred', () {
      final chapters = concrete.groups.single.elements;
      expect(chapters.length, greaterThanOrEqualTo(227));
      expect(chapters.map((chapter) => chapter.uid).toSet().length, chapters.length);
      expect(chapters.last.uid, 'vyberi-menya/1/1');
      expect(chapters.last.title, 'Том 1 Глава 1');
      expect(chapters.last.number, 1);
      expect(chapters.last.timestamp, matches(r'^\d{4}-\d{2}-\d{2}$'));
    });
  });

  test('getPages returns the chapter images', () async {
    final pages = await client.getPages(uid: 'vyberi-menya/1/1', data: {});
    expect(pages.value.length, greaterThanOrEqualTo(10));
    expect(pages.value.first, contains('mangabuff.ru/img2/chapters/'));
  });
}
