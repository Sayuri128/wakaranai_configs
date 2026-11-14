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

const String boruto = 'boruto-novoe-pokolenie-naruto-70';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig('anime/animego');
    client = AnimeApiClient(
      code: bundleScript(scriptPath('anime/animego/main.capyscript')),
      host: hostFor(config),
    );
  });

  test('feeds list titles and page forward', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, hasLength(20), reason: feed);
      expect(items.every((item) => RegExp(r'-\d+$').hasMatch(item.uid)), isTrue, reason: feed);
      expect(items.first.cover, startsWith('https://img.cdngos.com/'));
    }
    final first = await client.getGallery(page: 1, feed: 'rating');
    final second = await client.getGallery(page: 2, feed: 'rating');
    expect(second.first.uid, isNot(first.first.uid));
  });

  test('a genre filter and search narrow the catalog', () async {
    final romance = await client.getGallery(
      page: 1,
      feed: 'rating',
      filters: [
        FilterDataOneOfMultiple(
          selected: 'romance',
          filter: config.filters.firstWhere((filter) => filter.param == 'genre') as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(romance, isNotEmpty);
    final results = await client.getGallery(page: 1, query: 'наруто');
    expect(results.map((item) => item.uid), contains(boruto));
  });

  test('a long series lists every episode and plays Kodik dubs', () async {
    final concrete = await client.getConcrete(uid: boruto, data: {});
    expect(concrete.title, 'Боруто: Новое поколение Наруто');
    expect(concrete.alternativeTitles, isNotEmpty);
    expect(concrete.status, AnimeStatus.RELEASED);
    expect(concrete.authors, contains('Studio Pierrot'));
    expect(concrete.tags, contains('Экшен'));
    expect(concrete.description, isNotEmpty);
    final episodes = concrete.groups.single.elements;
    expect(episodes, hasLength(293));
    expect(episodes.first.title, 'Серия 1');
    final sources = await client.getVideoSources(episodes.first);
    expect(sources, isNotEmpty);
    expect(sources.map((source) => source.audioLabel).toSet().length, greaterThan(1));
    expect(sources.first.url, startsWith('https://'));
  });
}
