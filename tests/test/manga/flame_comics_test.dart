import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String thirtyYears = '165';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig('manga/flame_comics');
    client = MangaApiClient(
      code: readScript('manga/flame_comics'),
      host: hostFor(config, storage: MemoryExtensionStorage()),
    );
  });

  test('every feed lists series with covers', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, isNotEmpty, reason: feed);
      expect(items.every((item) => RegExp(r'^\d+$').hasMatch(item.uid)), isTrue, reason: feed);
      expect(items.first.cover, startsWith('https://cdn.flamecomics.xyz/uploads/images/series/'));
    }
    final first = await client.getGallery(page: 1, feed: 'popular');
    final second = await client.getGallery(page: 2, feed: 'popular');
    expect(first, hasLength(30));
    expect(second.map((item) => item.uid), isNot(contains(first.first.uid)));
  });

  test('search and genre filter work on the catalog', () async {
    final results = await client.getGallery(page: 1, query: '30 years have passed');
    expect(results.map((item) => item.uid), contains(thirtyYears));
    final romance = await client.getGallery(
      page: 1,
      feed: 'latest',
      filters: [
        FilterDataMultipleOfMultiple(
          selected: [
            ['Romance'],
          ],
          filter: config.filters.firstWhere((filter) => filter.param == 'categories')
              as GalleryFilterMultipleOfMultiple,
        ),
      ],
    );
    expect(romance, isNotEmpty);
    final detailed = await client.getConcrete(uid: romance.first.uid, data: {});
    expect(detailed.tags, contains('Romance'));
  });

  test('a series has details, chapters and pages', () async {
    final concrete = await client.getConcrete(uid: thirtyYears, data: {});
    expect(concrete.title, '30 Years Have Passed Since the Prologue');
    expect(concrete.alternativeTitles, contains('30 Years Since the Prologue'));
    expect(concrete.authors, contains('Markellaha'));
    expect(concrete.tags, containsAll(['Manhwa', 'Academy']));
    expect(concrete.status, MangaStatus.ONGOING);
    expect(concrete.description, startsWith("I 'transmigrated'"));
    expect(concrete.description, isNot(contains('<p')));
    final chapters = concrete.groups.single.elements;
    expect(chapters.length, greaterThan(20));
    expect(chapters.first.title, startsWith('Chapter 2'));
    final pages = await client.getPages(uid: chapters.last.uid, data: {});
    expect(pages.value.length, greaterThan(3));
    expect(pages.value.first, startsWith('https://cdn.flamecomics.xyz/uploads/images/series/165/'));
  });
}
