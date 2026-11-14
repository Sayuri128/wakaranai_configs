import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/scraper_helpers.dart';
import '../helpers/script_bundle.dart';

const String pacificRim = '415-tyhookeanskyj-rubizh.html';
const String mareOfEasttown = '5326-meyr-z-isttauna.html';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig('anime/kinoukr');
    client = AnimeApiClient(
      code: bundleScript(scriptPath('anime/kinoukr/main.capyscript')),
      host: hostFor(config),
    );
  });

  FilterDataOneOfMultiple section(String value) {
    return FilterDataOneOfMultiple(
      selected: value,
      filter: config.filters.firstWhere((filter) => filter.param == 'section')
          as GalleryFilterOneOfMultiple,
    );
  }

  group('getGallery', () {
    test('lists the newest titles and moves through pages', () async {
      final first = await client.getGallery(page: 1);
      final second = await client.getGallery(page: 2);
      expect(first.length, greaterThan(10));
      expect(first.every((item) => item.uid.endsWith('.html')), isTrue);
      expect(first.every((item) => item.cover.startsWith('https://kinoukr.tv/')), isTrue);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('section filter switches the listing', () async {
      final series = await client.getGallery(page: 1, filters: [section('series')]);
      final films = await client.getGallery(page: 1, filters: [section('filmss')]);
      expect(series, isNotEmpty);
      expect(films, isNotEmpty);
      expect(series.first.uid, isNot(films.first.uid));
    });
  });

  test('a film plays from its Ashdi player', () async {
    final concrete = await client.getConcrete(uid: pacificRim, data: {});
    expect(concrete.title, 'Тихоокеанський рубіж');
    expect(concrete.alternativeTitles, contains('Pacific Rim'));
    final video = concrete.groups.single.elements.single;
    final sources = await client.getVideoSources(video);
    expect(sources, isNotEmpty);
    expect(sources.first.url, contains('.m3u8'));
    expect(sources.first.subtitles, isNotEmpty);
  });

  test('a series gets seasons from the Ashdi playlist with one source per dub', () async {
    final concrete = await client.getConcrete(uid: mareOfEasttown, data: {});
    expect(concrete.title, 'Мейр з Істтауна');
    expect(concrete.tags, contains('Драма'));
    expect(concrete.year, 2021);
    final season = concrete.groups.first;
    expect(season.title, 'Сезон 1');
    expect(season.elements.length, 7);
    final firstEpisode = season.elements.first;
    expect(firstEpisode.number, 1);
    final sources = await client.getVideoSources(firstEpisode);
    expect(sources.length, greaterThanOrEqualTo(2));
    expect(sources.map((source) => source.audioLabel), containsAll(['HDrezka Studio', 'MGG']));
  });
}
