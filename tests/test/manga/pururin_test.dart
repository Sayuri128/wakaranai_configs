import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String ameriChan = '68160/welcome-to-the-compilation-ameri-chan';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/pururin');
    client = MangaApiClient(code: readScript('manga/pururin'), host: hostFor(config));
  });

  test('every feed lists galleries and pages end past the last one', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, hasLength(20), reason: feed);
      expect(items.every((item) => RegExp(r'^\d+/').hasMatch(item.uid)), isTrue);
      expect(items.every((item) => item.cover.startsWith('https://i.pururin.me/')), isTrue);
    }
    final second = await client.getGallery(page: 2, feed: 'newest');
    final first = await client.getGallery(page: 1, feed: 'newest');
    expect(second.first.uid, isNot(first.first.uid));
    expect(await client.getGallery(page: 99999, feed: 'newest'), isEmpty);
  });

  test('search finds a gallery', () async {
    final results = await client.getGallery(page: 1, query: 'Ameri-chan');
    expect(results.map((item) => item.uid), contains(ameriChan));
  });

  test('a gallery has details and every page in order', () async {
    final concrete = await client.getConcrete(uid: ameriChan, data: {});
    expect(concrete.title, 'Welcome To The Compilation! Ameri-chan!');
    expect(concrete.alternativeTitles, contains('Ma tomemashita! Ameri-chan!'));
    expect(concrete.authors, contains('Ento'));
    expect(concrete.tags, contains('Mairimashita Iruma-Kun'));
    final chapter = concrete.groups.single.elements.single;
    expect(chapter.title, 'Gallery (33 pages)');
    final pages = await client.getPages(uid: chapter.uid, data: {});
    expect(pages.value, hasLength(33));
    expect(pages.value.first, endsWith('/1.jpg'));
    expect(pages.value[9], endsWith('/10.jpg'));
    expect(pages.value.last, endsWith('/33.jpg'));
  });
}
