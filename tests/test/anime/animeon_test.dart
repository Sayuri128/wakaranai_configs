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

const String naruto = '913-naruto';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig('anime/animeon');
    client = AnimeApiClient(
      code: bundleScript(scriptPath('anime/animeon/main.capyscript')),
      host: hostFor(config),
    );
  });

  test('feeds list titles with covers and page forward', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, hasLength(30), reason: feed);
      expect(items.every((item) => RegExp(r'^\d+-').hasMatch(item.uid)), isTrue, reason: feed);
      expect(items.first.cover, startsWith('https://animeon.club/api/uploads/images/'));
    }
    final first = await client.getGallery(page: 1, feed: 'views');
    final second = await client.getGallery(page: 2, feed: 'views');
    expect(second.map((item) => item.uid), isNot(contains(first.first.uid)));
  });

  test('a type filter and search narrow the catalog', () async {
    final movies = await client.getGallery(
      page: 1,
      feed: 'created',
      filters: [
        FilterDataOneOfMultiple(
          selected: 'movie',
          filter: config.filters.firstWhere((filter) => filter.param == 'type') as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(movies, isNotEmpty);
    final detailed = await client.getConcrete(uid: movies.first.uid, data: {});
    expect(detailed.tags, contains('MOVIE'));
    final results = await client.getGallery(page: 1, query: 'naruto');
    expect(results.map((item) => item.uid), contains(naruto));
  });

  test('a title groups episodes per dub and player and plays Ashdi', () async {
    final concrete = await client.getConcrete(uid: naruto, data: {});
    expect(concrete.title, 'Наруто');
    expect(concrete.alternativeTitles, contains('Naruto'));
    expect(concrete.status, AnimeStatus.RELEASED);
    expect(concrete.authors, contains('Studio Pierrot'));
    expect(concrete.year, 2002);
    expect(concrete.groups.length, greaterThan(2));
    final ashdi = concrete.groups.first;
    expect(ashdi.title, endsWith('· Ashdi'));
    expect(ashdi.elements.length, greaterThan(200));
    final sources = await client.getVideoSources(ashdi.elements.first);
    expect(sources, isNotEmpty);
    expect(sources.first.url, contains('.m3u8'));
    expect(sources.first.audioLabel, isNotEmpty);
  });
}
