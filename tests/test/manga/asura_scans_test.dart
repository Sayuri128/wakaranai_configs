import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String overgeared = 'overgeared';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig('manga/asura_scans');
    client = MangaApiClient(code: readScript('manga/asura_scans'), host: hostFor(config));
    concrete = await client.getConcrete(uid: overgeared, data: {});
  });

  test('every feed lists series with covers and pages move forward', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, hasLength(20), reason: feed);
      expect(items.every((item) => item.cover.startsWith('https://cdn.asurascans.com/')), isTrue);
    }
    final first = await client.getGallery(page: 1, feed: 'popular');
    final second = await client.getGallery(page: 2, feed: 'popular');
    expect(first.first.uid, overgeared);
    expect(second.map((item) => item.uid), isNot(contains(first.first.uid)));
  });

  test('search and genre filter narrow the catalog', () async {
    final results = await client.getGallery(page: 1, query: 'overgeared');
    expect(results.map((item) => item.uid), contains(overgeared));
    final romance = await client.getGallery(
      page: 1,
      feed: 'latest',
      filters: [
        FilterDataMultipleOfMultiple(
          selected: [
            ['romance'],
          ],
          filter: config.filters.firstWhere((filter) => filter.param == 'genres')
              as GalleryFilterMultipleOfMultiple,
        ),
      ],
    );
    expect(romance, isNotEmpty);
    final detailed = await client.getConcrete(uid: romance.first.uid, data: {});
    expect(detailed.tags, contains('Romance'));
  });

  test('a series has details and free chapters newest first', () async {
    expect(concrete.title, 'Overgeared');
    expect(concrete.tags, containsAll(['Manhwa', 'Action']));
    expect(concrete.status, MangaStatus.ONGOING);
    expect(concrete.alternativeTitles, contains('Temppal'));
    expect(concrete.description, isNotEmpty);
    final chapters = concrete.groups.single.elements;
    expect(chapters.length, greaterThan(300));
    expect(chapters.last.title, 'Chapter 0: Prologue');
    expect(chapters.map((chapter) => chapter.uid), contains('$overgeared/chapter-1'));
  });

  test('a chapter has webp pages on the cdn', () async {
    final pages = await client.getPages(uid: '$overgeared/chapter-340', data: {});
    expect(pages.value.length, greaterThan(5));
    expect(pages.value.first, startsWith('https://cdn.asurascans.com/asura-images/chapters/overgeared/340/'));
  });
}
