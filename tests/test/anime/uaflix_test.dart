import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video_source.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_gallery_view/anime_gallery_view.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String movieUid = 'films/ziplaun/';
const String seasonsSeriesUid = 'serials/monolog-travnici/';
const String ashdiSeriesUid = 'serials/karas/';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig('anime/uaflix');
    client = AnimeApiClient(
      code: readScript('anime/uaflix'),
      host: hostFor(config),
    );
  });

  Future<List<AnimeGalleryView>> section(String value, {int page = 1}) {
    final filter = config.filters.first as GalleryFilterOneOfMultiple;
    return client.getGallery(
      page: page,
      query: '',
      filters: [FilterDataOneOfMultiple(selected: value, filter: filter)],
    );
  }

  group('getGallery', () {
    test('lists movies by default with covers', () async {
      final items = await client.getGallery(page: 1, query: '', filters: []);
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://uafix.net/'));
        expect(item.uid, isNot(startsWith('http')));
      }
    });

    test('pages through a section', () async {
      final first = await section('anime');
      final second = await section('anime', page: 2);
      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('searches across sections', () async {
      final results =
          await client.getGallery(page: 1, query: 'Наруто', filters: []);
      expect(results, isNotEmpty);
      expect(results.any((item) => item.title.contains('Наруто')), isTrue);
    });
  });

  group('movie', () {
    late AnimeConcreteView movie;

    setUpAll(() async {
      movie = await client.getConcrete(uid: movieUid, data: {});
    });

    test('has details and one video', () {
      expect(movie.title, 'Зіплайн');
      expect(movie.alternativeTitles, contains('Zip Wire'));
      expect(movie.description, isNotEmpty);
      expect(movie.tags, isNotEmpty);
      expect(movie.status, AnimeStatus.RELEASED);
      expect(movie.groups, hasLength(1));
      expect(movie.groups.single.elements, hasLength(1));
    });

    test('resolves the player to an hls stream', () async {
      final sources =
          await client.getVideoSources(movie.groups.single.elements.single);
      expect(sources, isNotEmpty);
      expect(sources.first.format, 'hls');
      expect(sources.first.url, contains('.m3u8'));
    });
  });

  group('series with season pages', () {
    late AnimeConcreteView series;

    setUpAll(() async {
      series = await client.getConcrete(uid: seasonsSeriesUid, data: {});
    });

    test('groups episodes by season in order', () {
      expect(series.groups.length, greaterThanOrEqualTo(3));
      expect(series.groups.first.title, 'Сезон 1');
      final firstSeason = series.groups.first.elements;
      expect(firstSeason.length, greaterThanOrEqualTo(24));
      expect(firstSeason.first.number, 1);
      expect(firstSeason.first.season, 1);
      expect(firstSeason[1].number, 2);
    });

    test('labels each player tab as an audio track', () async {
      final episode = series.groups[1].elements.first;
      final List<AnimeVideoSource> sources =
          await client.getVideoSources(episode);
      expect(sources, isNotEmpty);
      expect(sources.every((source) => source.format == 'hls'), isTrue);
      if (sources.length > 1) {
        expect(
          sources.map((source) => source.audioLabel).toSet().length,
          sources.length,
        );
      }
    });
  });

  group('series from an ashdi playlist', () {
    late AnimeConcreteView series;

    setUpAll(() async {
      series = await client.getConcrete(uid: ashdiSeriesUid, data: {});
    });

    test('groups episodes by dub and season', () {
      expect(series.groups.length, greaterThanOrEqualTo(2));
      expect(series.groups.first.title, contains('Сезон 1'));
      expect(series.groups.first.elements.first.uid,
          startsWith('https://ashdi.vip/vod/'));
    });

    test('labels the stream with the dub', () async {
      final group = series.groups.first;
      final sources = await client.getVideoSources(group.elements.first);
      expect(sources, isNotEmpty);
      expect(sources.first.format, 'hls');
      expect(group.title, startsWith(sources.first.audioLabel!));
    });
  });
}
