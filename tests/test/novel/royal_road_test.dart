import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/royal_road';
const String motherOfLearning = '21220';
const String firstChapter = '21220/301778';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;
  late MangaConcreteView fiction;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    client = novelClientFor(extensionDirectory);
    fiction = await client.getConcrete(uid: motherOfLearning, data: {});
  });

  group('getGallery', () {
    test('every feed lists fictions with covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.length, greaterThanOrEqualTo(20), reason: feed);
        for (final item in items) {
          expect(item.uid, matches(r'^\d+$'));
          expect(item.title, isNotEmpty);
        }
      }
    });

    test('trending is a single page', () async {
      expect(await client.getGallery(page: 2, feed: 'trending'), isEmpty);
    });

    test('search finds a fiction and ends past the last page', () async {
      final results = await client.getGallery(page: 1, query: 'mother of learning');
      expect(results.map((item) => item.uid), contains(motherOfLearning));
      final beyond = await client.getGallery(page: 50, query: 'mother of learning');
      expect(beyond, isEmpty);
    });

    test('genre and status filters use the search page', () async {
      final genres = config.filters.firstWhere((filter) => filter.param == 'genres')
          as GalleryFilterMultipleOfMultiple;
      final status = config.filters.firstWhere((filter) => filter.param == 'status')
          as GalleryFilterOneOfMultiple;
      final items = await client.getGallery(
        page: 1,
        feed: 'best-rated',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['fantasy'],
            ],
            filter: genres,
          ),
          FilterDataOneOfMultiple(selected: 'COMPLETED', filter: status),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.status == MangaStatus.RELEASED), isTrue);
      expect(items.every((item) => item.tags.contains('Fantasy')), isTrue);
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(fiction.title, 'Mother of Learning');
      expect(fiction.authors, ['nobody103']);
      expect(fiction.status, MangaStatus.RELEASED);
      expect(fiction.tags, containsAll(['Original', 'Time Loop']));
      expect(fiction.cover, startsWith('https://www.royalroadcdn.com/'));
      expect(fiction.description, startsWith('Zorian is a teenage mage'));
      expect(fiction.url, 'https://www.royalroad.com/fiction/21220/mother-of-learning');
    });

    test('lists chapters newest first', () {
      final chapters = fiction.groups.single.elements;
      expect(chapters.length, greaterThan(100));
      expect(chapters.last.uid, firstChapter);
      expect(chapters.last.title, '1. Good Morning Brother');
      expect(chapters.last.number, 1);
    });
  });

  group('getChapterText', () {
    test('drops the hidden anti-piracy line and keeps author notes', () async {
      final content = await client.getChapterText(uid: firstChapter, data: {});
      expect(content.title, '1. Good Morning Brother');
      expect(content.html, contains('Zorian'));
      expect(content.html, isNot(contains('lifted from the author')));
      expect(content.html, contains("Author's note"));
    });

    test('leaves author notes out when asked', () async {
      final quiet = novelClientFor(extensionDirectory, preferences: {'authorNotes': false});
      final content = await quiet.getChapterText(uid: firstChapter, data: {});
      expect(content.html, isNot(contains("Author's note")));
      expect(content.html, startsWith('<p'));
    });
  });
}
