import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/scraper_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String heavyKnight = '8313-vygnanyi-vazhkoozbroienyi-lycar-staie-neperemozhnym-zavdiaky-znanniam-gry.html';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig('anime/animeua_club');
    client = AnimeApiClient(
      code: bundleScript(scriptPath('anime/animeua_club/main.capyscript')),
      host: hostFor(config),
    );
  });

  test('feeds list titles and page forward', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, isNotEmpty, reason: feed);
      expect(items.every((item) => item.uid.endsWith('.html')), isTrue, reason: feed);
      expect(items.first.cover, startsWith('https://animeua.club/uploads/'));
    }
    final first = await client.getGallery(page: 1, feed: 'anime');
    final second = await client.getGallery(page: 2, feed: 'anime');
    expect(second.map((item) => item.uid), isNot(contains(first.first.uid)));
    expect(await client.getGallery(page: 999, feed: 'anime'), isEmpty);
  });

  test('genre filter and search', () async {
    final comedy = await client.getGallery(
      page: 1,
      filters: [
        FilterDataOneOfMultiple(
          selected: 'komik',
          filter: config.filters.single as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(comedy, isNotEmpty);
    final results = await client.getGallery(page: 1, query: 'naruto');
    expect(results.map((item) => item.uid), contains(startsWith('388-boruto')));
  });

  test('a series lists Ashdi episodes and plays them', () async {
    final concrete = await client.getConcrete(uid: heavyKnight, data: {});
    expect(concrete.title, 'Вигнаний важкоозброєний лицар стає непереможним завдяки знанням гри');
    expect(concrete.alternativeTitles, contains('The Exiled Heavy Knight Knows How to Game the System'));
    expect(concrete.status, AnimeStatus.ONGOING);
    expect(concrete.authors, contains('GoHands'));
    expect(concrete.year, 2026);
    expect(concrete.tags, contains('Фентезі'));
    final episodes = concrete.groups.first.elements;
    expect(episodes, isNotEmpty);
    final sources = await client.getVideoSources(episodes.first);
    expect(sources.first.url, contains('.m3u8'));
  });

  test('a film plays its Ashdi video', () async {
    final films = await client.getGallery(page: 1, feed: 'film');
    final concrete = await client.getConcrete(uid: films.first.uid, data: {});
    expect(concrete.groups, isNotEmpty);
    final sources = await client.getVideoSources(concrete.groups.first.elements.first);
    expect(sources, isNotEmpty);
  });
}
