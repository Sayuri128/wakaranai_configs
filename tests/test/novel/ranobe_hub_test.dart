import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/ranobe_hub';
const String hellmodeUid = '822';
const String hellmodePrologue = '822/265707';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;
  late MangaConcreteView hellmode;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    client = novelClientFor(extensionDirectory);
    hellmode = await client.getConcrete(uid: hellmodeUid, data: {});
  });

  GalleryFilterMultipleOfMultiple filterFor(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterMultipleOfMultiple;
  }

  group('getGallery', () {
    test('every feed lists books with absolute covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.length, greaterThan(10), reason: feed);
        for (final item in items) {
          expect(item.uid, matches(r'^\d+$'));
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://ranobehub.org/api/media/'));
        }
      }
    });

    test('pages move forward and end past the last one', () async {
      final first = await client.getGallery(page: 1, feed: 'popular');
      final second = await client.getGallery(page: 2, feed: 'popular');
      expect(second.first.uid, isNot(first.first.uid));
      final beyond = await client.getGallery(page: 9999, feed: 'popular');
      expect(beyond, isEmpty);
    });

    test('genre and status filters narrow the catalog', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'popular',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['8'],
            ],
            filter: filterFor('tag'),
          ),
          FilterDataMultipleOfMultiple(
            selected: [
              ['2'],
            ],
            filter: filterFor('status'),
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.status == MangaStatus.RELEASED), isTrue);
      expect(items.every((item) => item.tags.contains('Фэнтези')), isTrue);
    });

    test('search finds a book and stops after page 1', () async {
      final results = await client.getGallery(page: 1, query: 'bleach');
      expect(results.map((item) => item.uid), contains('1034'));
      final next = await client.getGallery(page: 2, query: 'bleach');
      expect(next, isEmpty);
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(hellmode.title, startsWith('Режим — АД'));
      expect(hellmode.alternativeTitles, contains(startsWith('Hellmode')));
      expect(hellmode.authors, contains('Hamuo'));
      expect(hellmode.year, 2019);
      expect(hellmode.status, MangaStatus.ONGOING);
      expect(hellmode.tags, contains('Фэнтези'));
      expect(hellmode.cover, startsWith('https://ranobehub.org/api/media/'));
      expect(hellmode.description, contains('Ямада Кенчи'));
    });

    test('lists every chapter newest first', () {
      final chapters = hellmode.groups.single.elements;
      expect(chapters.length, greaterThan(830));
      expect(chapters.map((chapter) => chapter.uid).toSet().length, chapters.length);
      expect(chapters.first.volume, greaterThanOrEqualTo(14));
      final prologue = chapters.firstWhere((chapter) => chapter.uid == hellmodePrologue);
      expect(prologue.title, 'Том 1. [1] Пролог.');
      expect(prologue.number, 1);
      expect(prologue.volume, 1);
    });
  });

  test('getChapterText returns the chapter paragraphs', () async {
    final content = await client.getChapterText(uid: hellmodePrologue, data: {});
    expect(content.html, startsWith('<p>'));
    expect(content.html, contains('Ямада Кенчи'));
    expect(content.html, isNot(contains('reader-ad-slot')));
    expect(content.title, '[1] Пролог.');
  });
}
