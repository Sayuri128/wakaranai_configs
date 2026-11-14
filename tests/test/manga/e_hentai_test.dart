import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/e_hentai');
    client = MangaApiClient(
      code: readScript('manga/e_hentai'),
      host: hostFor(config, storage: MemoryExtensionStorage()),
    );
  });

  test('latest follows the next cursor between pages', () async {
    final first = await client.getGallery(page: 1, feed: 'latest');
    final second = await client.getGallery(page: 2, feed: 'latest');
    expect(first.length, greaterThan(20));
    expect(first.every((item) => RegExp(r'^\d+/[0-9a-f]+$').hasMatch(item.uid)), isTrue);
    expect(second.map((item) => item.uid).toSet().intersection(first.map((item) => item.uid).toSet()), isEmpty);
  });

  test('popular is a single page', () async {
    expect(await client.getGallery(page: 1, feed: 'popular'), isNotEmpty);
    expect(await client.getGallery(page: 2, feed: 'popular'), isEmpty);
  });

  test('search with a category filter', () async {
    final items = await client.getGallery(
      page: 1,
      query: 'english',
      filters: [
        FilterDataMultipleOfMultiple(
          selected: [
            ['2'],
          ],
          filter: config.filters.single as GalleryFilterMultipleOfMultiple,
        ),
      ],
    );
    expect(items, isNotEmpty);
    final concrete = await client.getConcrete(uid: items.first.uid, data: {});
    expect(concrete.tags.first, 'Doujinshi');
  });

  test('a gallery splits into 20-page chapters with real image links', () async {
    final items = await client.getGallery(page: 1, feed: 'popular');
    final concrete = await client.getConcrete(uid: items.first.uid, data: {});
    expect(concrete.title, isNotEmpty);
    expect(concrete.cover, startsWith('https://'));
    final chapters = concrete.groups.single.elements;
    expect(chapters, isNotEmpty);
    expect(chapters.first.uid, '${items.first.uid}/0');
    final pages = await client.getPages(uid: chapters.first.uid, data: {});
    expect(pages.value.length, inInclusiveRange(1, 20));
    expect(pages.value.first, startsWith('https://'));
  });
}
