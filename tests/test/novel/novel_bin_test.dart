import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/novel_bin';
const String eldritchTheatre = 'eldritch-horror-theatre';
const String firstChapter = 'eldritch-horror-theatre/chapter-1-this-job-entails-certain-risks';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;
  late MangaConcreteView novel;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    client = novelClientFor(extensionDirectory);
    novel = await client.getConcrete(uid: eldritchTheatre, data: {});
  });

  FilterDataOneOfMultiple choose(String param, String value) {
    return FilterDataOneOfMultiple(
      selected: value,
      filter: config.filters.firstWhere((filter) => filter.param == param)
          as GalleryFilterOneOfMultiple,
    );
  }

  group('getGallery', () {
    test('every feed lists novels with full-size covers', () async {
      for (final feed in config.feeds.map((feed) => feed.id)) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.length, greaterThan(10), reason: feed);
        for (final item in items) {
          expect(item.uid, isNot(contains('/')));
          expect(item.title, isNotEmpty);
          expect(item.cover, isNot(contains('novel_80_113')));
        }
      }
    });

    test('pages move forward', () async {
      final first = await client.getGallery(page: 1, feed: 'ALL_TIME');
      final second = await client.getGallery(page: 2, feed: 'ALL_TIME');
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('genre and status filters change the list', () async {
      final genre = await client.getGallery(page: 1, filters: [choose('genre', 'horror')]);
      expect(genre, isNotEmpty);
      final detailed = await client.getConcrete(uid: genre.first.uid, data: {});
      expect(detailed.tags, contains('Horror'));
      final completed = await client.getGallery(page: 1, filters: [choose('status', 'completed')]);
      expect(completed, isNotEmpty);
    });

    test('search finds a novel and ends past the last page', () async {
      final results = await client.getGallery(page: 1, query: 'Eldritch Horror Theatre');
      expect(results.map((item) => item.uid), contains(eldritchTheatre));
      expect(await client.getGallery(page: 500, query: 'Eldritch Horror Theatre'), isEmpty);
    });
  });

  group('getConcrete', () {
    test('has details', () {
      expect(novel.title, 'Eldritch Horror Theatre');
      expect(novel.authors, isNotEmpty);
      expect(novel.tags, contains('Horror'));
      expect(novel.status, MangaStatus.ONGOING);
      expect(novel.cover, 'https://images.novelbin.com/novel/eldritch-horror-theatre.jpg');
      expect(novel.description, startsWith('“Do not look directly at a God.”'));
      expect(novel.description, contains('\n'));
    });

    test('lists every chapter newest first', () {
      final chapters = novel.groups.single.elements;
      expect(chapters.length, greaterThan(3000));
      expect(chapters.last.uid, firstChapter);
      expect(chapters.last.title, 'Chapter 1: This Job Entails Certain Risks');
      expect(chapters.last.number, 1);
    });
  });

  test('getChapterText keeps only the story paragraphs', () async {
    final content = await client.getChapterText(uid: firstChapter, data: {});
    expect(content.html, startsWith('<p>'));
    expect(content.html, isNot(contains('<div')));
    expect(content.html.length, greaterThan(3000));
    expect(content.title, 'Chapter 1: This Job Entails Certain Risks');
  });
}
