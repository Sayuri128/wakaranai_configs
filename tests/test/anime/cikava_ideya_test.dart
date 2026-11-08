import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String seriesUid = '70-resident-alien.html';
const String movieUid = '284-zadum-vsesvitu.html';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig('anime/cikava_ideya');
    client = AnimeApiClient(
      code: readScript('anime/cikava_ideya'),
      host: hostFor(config),
    );
  });

  group('getGallery', () {
    test('lists the latest releases with covers', () async {
      final items = await client.getGallery(page: 1, query: '', filters: []);
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://cikava-ideya.top/'));
        expect(item.uid, endsWith('.html'));
      }
    });

    test('pages through a section', () async {
      final filter = config.filters.first as GalleryFilterOneOfMultiple;
      final selection = [FilterDataOneOfMultiple(selected: 'serialy', filter: filter)];
      final first =
          await client.getGallery(page: 1, query: '', filters: selection);
      final second =
          await client.getGallery(page: 2, query: '', filters: selection);
      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('searches', () async {
      final results =
          await client.getGallery(page: 1, query: 'Постоялець', filters: []);
      expect(results.map((item) => item.uid), contains(seriesUid));
    });
  });

  group('series', () {
    late AnimeConcreteView series;

    setUpAll(() async {
      series = await client.getConcrete(uid: seriesUid, data: {});
    });

    test('has details', () {
      expect(series.title, 'Постоялець з космосу');
      expect(series.alternativeTitles, contains('Resident Alien'));
      expect(series.description, isNotEmpty);
      expect(series.tags, contains('фантастика'));
      expect(series.authors, isNotEmpty);
    });

    test('groups episodes by season', () {
      expect(series.groups.length, greaterThanOrEqualTo(4));
      expect(series.groups.first.title, '1 сезон');
      final first = series.groups.first.elements.first;
      expect(first.number, 1);
      expect(first.season, 1);
      expect(first.uid, startsWith('https://ashdi.vip/vod/'));
    });

    test('resolves an episode to hls', () async {
      final sources =
          await client.getVideoSources(series.groups.first.elements.first);
      expect(sources, isNotEmpty);
      expect(sources.first.format, 'hls');
      expect(sources.first.url, contains('.m3u8'));
    });
  });

  group('movie', () {
    late AnimeConcreteView movie;

    setUpAll(() async {
      movie = await client.getConcrete(uid: movieUid, data: {});
    });

    test('has one video', () {
      expect(movie.status, AnimeStatus.RELEASED);
      expect(movie.groups, hasLength(1));
      expect(movie.groups.single.elements, hasLength(1));
    });

    test('resolves the player to hls', () async {
      final sources =
          await client.getVideoSources(movie.groups.single.elements.single);
      expect(sources, isNotEmpty);
      expect(sources.first.format, 'hls');
    });
  });
}
