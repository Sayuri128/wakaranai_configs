import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/scraper_helpers.dart';
import '../helpers/script_bundle.dart';

const String azureLegacy = '1420-lazurnoe-nasledie.html';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig('anime/animedia');
    client = AnimeApiClient(
      code: bundleScript(scriptPath('anime/animedia/main.capyscript')),
      host: hostFor(config),
    );
  });

  test('sections list titles and page forward', () async {
    final latest = await client.getGallery(page: 1);
    expect(latest, isNotEmpty);
    expect(latest.every((item) => item.uid.endsWith('.html')), isTrue);
    final finished = await client.getGallery(
      page: 2,
      filters: [
        FilterDataOneOfMultiple(
          selected: 'zavershennye',
          filter: config.filters.single as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(finished, isNotEmpty);
    expect(finished.first.uid, isNot(latest.first.uid));
  });

  test('search posts the DLE form', () async {
    final results = await client.getGallery(page: 1, query: 'Лазурное наследие');
    expect(results.map((item) => item.uid), contains(azureLegacy));
  });

  test('a title lists every Animedia episode and plays it', () async {
    final concrete = await client.getConcrete(uid: azureLegacy, data: {});
    expect(concrete.title, 'Лазурное наследие');
    expect(concrete.alternativeTitles, contains('Cang Yuan Tu'));
    expect(concrete.status, AnimeStatus.ONGOING);
    expect(concrete.year, 2023);
    expect(concrete.tags, contains('фэнтези'));
    final episodes = concrete.groups.single.elements;
    expect(episodes.length, greaterThanOrEqualTo(100));
    expect(episodes.first.number, 1);
    final sources = await client.getVideoSources(episodes.first);
    expect(sources.first.url, contains('.m3u8'));
    expect(sources.first.audioLabel, 'AniMedia');
  });
}
