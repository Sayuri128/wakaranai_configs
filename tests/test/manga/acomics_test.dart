import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String niochom = 'NIOCHOM';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;
  late MangaConcreteView comic;

  setUpAll(() async {
    config = loadConfig('manga/acomics');
    client = MangaApiClient(
      code: readScript('manga/acomics'),
      host: hostFor(config),
    );
    comic = await client.getConcrete(uid: niochom, data: {});
  });

  group('getGallery', () {
    test('feeds list comics with covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items, isNotEmpty, reason: feed);
        for (final item in items) {
          expect(item.uid, isNot(contains('/')));
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://acomics.ru/upload/'));
        }
      }
    });

    test('pages move forward', () async {
      final first = await client.getGallery(page: 1, feed: 'subscr_count');
      final second = await client.getGallery(page: 2, feed: 'subscr_count');
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('category filter keeps to the chosen genre', () async {
      final categories = config.filters.firstWhere((filter) => filter.param == 'categories')
          as GalleryFilterMultipleOfMultiple;
      final items = await client.getGallery(
        page: 1,
        feed: 'subscr_count',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['5'],
            ],
            filter: categories,
          ),
        ],
      );
      expect(items, isNotEmpty);
      final first = await client.getConcrete(uid: items.first.uid, data: {});
      expect(first.tags, contains('Юмор'));
    });

    test('search finds a comic and ignores short queries', () async {
      final results = await client.getGallery(page: 1, query: 'dragon');
      expect(results.map((item) => item.uid), contains('dragonfrogs'));
      final adult = await client.getGallery(page: 1, query: 'Hermits');
      expect(adult.map((item) => item.uid), isNot(contains('Hermits')));
      expect(await client.getGallery(page: 1, query: 'ко'), isEmpty);
    });
  });

  group('comic', () {
    test('has details', () {
      expect(comic.title, 'НИОЧЁМ');
      expect(comic.authors, ['Alex-Miner']);
      expect(comic.tags, containsAll(['Юмор', 'Бытовое']));
      expect(comic.cover, startsWith('https://acomics.ru/upload/'));
      expect(comic.description, contains('юмористических зарисовок'));
    });

    test('groups issues into blocks of 24, newest first', () {
      final chapters = comic.groups.single.elements;
      expect(chapters.length, greaterThanOrEqualTo(3));
      expect(chapters.last.uid, 'NIOCHOM/0');
      expect(chapters.last.title, 'Выпуски 1–24');
      expect(chapters.last.number, 1);
    });

    test('pages are the full issue images in order', () async {
      final pages = await client.getPages(uid: 'NIOCHOM/24', data: {});
      expect(pages.value, hasLength(24));
      expect(pages.value.first, 'https://acomics.ru/upload/!c/Alex-Miner/NIOCHOM/000025-' +
          pages.value.first.split('/000025-').last);
      expect(pages.value.every((page) => !page.contains('/thumb/')), isTrue);
    });
  });
}
