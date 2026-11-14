import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String revengeOfOthers = 'dorama/389-revenge-of-others.html';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig('anime/bambooua');
    client = AnimeApiClient(code: readScript('anime/bambooua'), host: hostFor(config));
  });

  test('feeds list titles and page forward', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, isNotEmpty, reason: feed);
      expect(items.every((item) => item.uid.endsWith('.html')), isTrue, reason: feed);
      expect(items.first.cover, startsWith('https://bambooua.com/uploads/'));
    }
    final first = await client.getGallery(page: 1, feed: 'dorama');
    final second = await client.getGallery(page: 2, feed: 'dorama');
    expect(second.map((item) => item.uid), isNot(contains(first.first.uid)));
    expect(await client.getGallery(page: 400, feed: 'dorama'), isEmpty);
  });

  test('genre filter and search', () async {
    final drama = await client.getGallery(
      page: 1,
      filters: [
        FilterDataOneOfMultiple(
          selected: 'drama',
          filter: config.filters.firstWhere((filter) => filter.param == 'genre') as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(drama, isNotEmpty);
    final results = await client.getGallery(page: 1, query: 'Revenge of Others');
    expect(results.map((item) => item.uid), contains(revengeOfOthers));
  });

  test('a title splits subtitles and dub and hides supporter-only episodes', () async {
    final concrete = await client.getConcrete(uid: revengeOfOthers, data: {});
    expect(concrete.title, isNotEmpty);
    expect(concrete.alternativeTitles, contains('Revenge of Others'));
    expect(concrete.status, AnimeStatus.RELEASED);
    expect(concrete.tags, contains('Драма'));
    expect(concrete.description, isNotEmpty);
    expect(concrete.groups.map((group) => group.title), containsAll(['Субтитри', 'Дубляж']));
    final dub = concrete.groups.firstWhere((group) => group.title == 'Дубляж');
    expect(dub.elements.length, lessThan(10));
    expect(dub.elements.every((video) => video.src.endsWith('.m3u8')), isTrue);
    final sources = await client.getVideoSources(dub.elements.first);
    expect(sources.single.audioLabel, 'Дубляж');
    expect(sources.single.url, contains('hls8.bambooua.com'));
  });
}
