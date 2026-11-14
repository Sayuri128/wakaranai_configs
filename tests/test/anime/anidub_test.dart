import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String tokyoRevengers = '12459-tokijskie-mstiteli-bitva-treh-nebozhitelej.html';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig('anime/anidub');
    client = AnimeApiClient(code: readScript('anime/anidub'), host: hostFor(config));
  });

  FilterDataOneOfMultiple section(String value) {
    return FilterDataOneOfMultiple(
      selected: value,
      filter: config.filters.firstWhere((filter) => filter.param == 'section')
          as GalleryFilterOneOfMultiple,
    );
  }

  group('getGallery', () {
    test('latest list pages forward and ends', () async {
      final first = await client.getGallery(page: 1);
      final second = await client.getGallery(page: 2);
      expect(first, hasLength(32));
      expect(first.every((item) => item.uid.endsWith('.html')), isTrue);
      expect(first.every((item) => item.cover.startsWith('https://anidub.com/uploads/')), isTrue);
      expect(second.first.uid, isNot(first.first.uid));
      expect(await client.getGallery(page: 5000), isEmpty);
    });

    test('section filter switches to movies', () async {
      final movies = await client.getGallery(page: 1, filters: [section('anime_movie')]);
      final ongoing = await client.getGallery(page: 1, filters: [section('anime_ongoing')]);
      expect(movies, isNotEmpty);
      expect(ongoing, isNotEmpty);
      expect(movies.first.uid, isNot(ongoing.first.uid));
    });

    test('search finds titles', () async {
      final results = await client.getGallery(page: 1, query: 'Токийские мстители');
      expect(results.map((item) => item.uid), contains(tokyoRevengers));
    });
  });

  test('a title lists every episode from the AniDub player and plays it', () async {
    final concrete = await client.getConcrete(uid: tokyoRevengers, data: {});
    expect(concrete.title, 'Токийские мстители: Битва трёх небожителей');
    expect(concrete.alternativeTitles, contains('Tokyo Revengers: Santen Sensou-hen'));
    expect(concrete.tags, contains('Драма'));
    expect(concrete.year, 2026);
    final group = concrete.groups.single;
    expect(group.title, startsWith('Озвучка: '));
    expect(group.elements.length, greaterThanOrEqualTo(7));
    expect(group.elements.first.number, 1);
    final sources = await client.getVideoSources(group.elements.first);
    expect(sources.single.url, contains('/vid.php?v='));
    expect(sources.single.headers['Referer'], startsWith('https://'));
  });
}
