import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_gallery_view/anime_gallery_view.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/filter_data.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String extensionDirectory = 'anime/anime365';
const String frierenUid = '30414';
const String haruhiMovieUid = '3483';
const String onePieceUid = '8762';
const String embedPrefix = 'https://smotret-anime.com/translations/embed/';

class NullLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

void main() {
  Logger.level = Level.off;
  Logger.defaultOutput = () => NullLogOutput();

  late ConfigInfo config;
  late AnimeApiClient client;

  AnimeApiClient clientWith(Map<String, Object?> preferences) {
    return AnimeApiClient(
      code: readScript(extensionDirectory),
      host: hostFor(config, preferences: preferences),
    );
  }

  setUpAll(() {
    config = loadConfig(extensionDirectory);
    client = clientWith(const {});
  });

  FilterDataOneOfMultiple oneOf(String param, String value) {
    final definition = config.filters.firstWhere((f) => f.param == param)
        as GalleryFilterOneOfMultiple;
    return FilterDataOneOfMultiple(selected: value, filter: definition);
  }

  FilterDataMultipleOfMultiple genres(List<String> ids) {
    final definition = config.filters.firstWhere((f) => f.param == 'genre')
        as GalleryFilterMultipleOfMultiple;
    return FilterDataMultipleOfMultiple(selected: [ids], filter: definition);
  }

  Future<List<AnimeGalleryView>> gallery({
    int page = 1,
    String query = '',
    List<FilterData> filters = const [],
    String feed = 'latest',
    int pageSize = 20,
  }) {
    return client.getGallery(
      page: page,
      query: query,
      filters: filters,
      feed: feed,
      pageSize: pageSize,
    );
  }

  void expectGalleryItems(List<AnimeGalleryView> items) {
    final uids = items.map((item) => item.uid).toSet();
    expect(uids.length, items.length);
    for (final item in items) {
      expect(int.tryParse(item.uid), isNotNull, reason: item.uid);
      expect(item.title, isNotEmpty);
      expect(item.title, isNot(contains(' / ')));
      expect(item.cover, startsWith('https://smotret-anime.com/posters/'));
      expect(item.data['title'], item.title);
    }
  }

  group('getGallery', () {
    test('the latest feed lists titles with fresh translations', () async {
      final latest = await gallery();
      expect(latest, isNotEmpty);
      expect(latest.length, lessThanOrEqualTo(20));
      expectGalleryItems(latest);
      expect(latest.where((item) => item.latestChapter != null), isNotEmpty);
    });

    test('the top rated feed pages through the catalog', () async {
      final first = await gallery(feed: 'top', pageSize: 40);
      expect(first, hasLength(40));
      expectGalleryItems(first);
      expect(first.map((item) => item.uid), contains(frierenUid));
      final second = await gallery(feed: 'top', pageSize: 40, page: 2);
      expect(second, isNotEmpty);
      final firstUids = first.map((item) => item.uid).toSet();
      expect(second.where((item) => firstUids.contains(item.uid)), isEmpty);
    });

    test('the ongoing feed lists airing titles', () async {
      final ongoing = await gallery(feed: 'ongoing');
      expect(ongoing, isNotEmpty);
      expectGalleryItems(ongoing);
      for (final item in ongoing) {
        expect(item.status, AnimeStatus.ONGOING, reason: item.title);
      }
    });

    test('search finds titles by Russian and romaji names', () async {
      final russian = await gallery(query: 'Фрирен');
      expect(russian.map((item) => item.uid), contains(frierenUid));
      final romaji = await gallery(query: 'Sousou no Frieren');
      expect(romaji.map((item) => item.uid), contains(frierenUid));
    });

    test('a search with no matches is empty rather than an error', () async {
      expect(await gallery(query: 'zzqqxxyyww'), isEmpty);
    });

    test('type and year filters narrow the catalog', () async {
      final movies = await gallery(
        filters: [oneOf('type', 'movie'), oneOf('year', '2010')],
      );
      expect(movies, isNotEmpty);
      for (final item in movies) {
        expect(item.year, 2010, reason: item.title);
        expect(item.tags, contains('Фильм'), reason: item.title);
      }
    });

    test('a genre filter lists titles of that genre', () async {
      final fantasy = await gallery(filters: [genres(['10'])]);
      expect(fantasy, isNotEmpty);
      final concrete = await client.getConcrete(
        uid: fantasy.first.uid,
        data: fantasy.first.data,
      );
      expect(concrete.tags, contains('Фэнтези'));
    });
  });

  group('getConcrete', () {
    late AnimeConcreteView frieren;

    setUpAll(() async {
      frieren = await client.getConcrete(uid: frierenUid, data: {});
    });

    test('reads details from the api', () {
      expect(frieren.title, 'Провожающая в последний путь Фрирен');
      expect(frieren.alternativeTitles, contains('Sousou no Frieren'));
      expect(frieren.description, isNotEmpty);
      expect(frieren.cover, startsWith('https://smotret-anime.com/posters/'));
      expect(frieren.tags, containsAll(['Фэнтези', 'ТВ сериал']));
      expect(frieren.status, AnimeStatus.RELEASED);
      expect(frieren.year, 2023);
      expect(frieren.rating, greaterThan(8));
      expect(frieren.url, startsWith('https://smotret-anime.com/catalog/'));
    });

    test('groups Russian subtitles first, then voiceovers', () {
      final titles = frieren.groups.map((group) => group.title).toList();
      expect(titles, isNotEmpty);
      expect(titles.first, startsWith('Субтитры · '));
      final firstVoice =
          titles.indexWhere((title) => title.startsWith('Озвучка · '));
      expect(firstVoice, greaterThan(0));
      expect(
        titles.skip(firstVoice).where((title) => title.startsWith('Субтитры')),
        isEmpty,
      );
      expect(
        titles.where((title) =>
            !title.startsWith('Субтитры · ') && !title.startsWith('Озвучка · ')),
        isEmpty,
      );
      expect(
        frieren.groups.where((group) => group.elements.length == 28),
        isNotEmpty,
      );
    });

    test('lists every translation as an embed episode in order', () {
      final allUids = <String>{};
      for (final group in frieren.groups) {
        final numbers = group.elements
            .map((video) => video.number)
            .whereType<double>()
            .toList();
        for (var index = 1; index < numbers.length; index++) {
          expect(numbers[index], greaterThan(numbers[index - 1]),
              reason: group.title);
        }
        for (final video in group.elements) {
          expect(video.type, AnimeVideoType.IFRAME);
          expect(video.src, startsWith(embedPrefix));
          expect(video.uid, startsWith('$frierenUid/'));
          expect(video.title, isNotEmpty);
          expect(allUids.add(video.uid), isTrue, reason: video.uid);
          expect(video.data['translationId'], video.src.substring(embedPrefix.length));
        }
      }
    });

    test('the embed player page answers for a guest', () async {
      final video = frieren.groups.first.elements.last;
      final response = await http
          .get(Uri.parse(video.src))
          .timeout(const Duration(seconds: 30));
      expect(response.statusCode, 200);
      expect(response.body, contains('id="main-video"'));
      expect(response.body, contains('data-subtitles="/episodeTranslations/'));
    });

    test('a movie is a single episode', () async {
      final movie = await client.getConcrete(uid: haruhiMovieUid, data: {});
      expect(movie.year, 2010);
      expect(movie.groups, isNotEmpty);
      for (final group in movie.groups) {
        expect(group.elements, hasLength(1));
        expect(group.elements.single.title, 'Фильм');
      }
    });

    test('a long series reads every page of translations', () async {
      final onePiece = await client.getConcrete(uid: onePieceUid, data: {});
      expect(onePiece.status, AnimeStatus.ONGOING);
      final total = onePiece.groups
          .map((group) => group.elements.length)
          .fold<int>(0, (sum, length) => sum + length);
      expect(total, greaterThan(4000));
      expect(
        onePiece.groups.where((group) => group.elements.length > 500),
        isNotEmpty,
      );
    });

    test('an unknown title is reported as not found', () async {
      await expectSourceError(
        () => client.getConcrete(uid: '99999999', data: {}),
        SourceErrorKind.notFound,
      );
      await expectSourceError(
        () => client.getConcrete(uid: 'abc', data: {}),
        SourceErrorKind.notFound,
      );
    });
  });

  test('the sign-in browser result is accepted without changing requests', () async {
    final signedIn = clientWith(const {});
    await signedIn.passProtector(body: '', headers: const {}, cookies: const {});
    final results = await signedIn.getGallery(
      page: 1,
      query: 'Фрирен',
      filters: const [],
      feed: '',
      pageSize: 20,
    );
    expect(results.map((item) => item.uid), contains(frierenUid));
  });

  group('preferences', () {
    test('voiceovers can come first', () async {
      final concrete = await clientWith(const {'firstKind': 'voice'})
          .getConcrete(uid: frierenUid, data: {});
      expect(concrete.groups.first.title, startsWith('Озвучка · '));
    });

    test('preferred teams are listed first', () async {
      final concrete = await clientWith(const {'preferredTeams': 'anilibria'})
          .getConcrete(uid: frierenUid, data: {});
      expect(concrete.groups.first.title, endsWith(' · AniLibria'));
      expect(concrete.groups.first.title, startsWith('Субтитры'));
    });

    test('translation types choose the listed groups', () async {
      final concrete = await clientWith(const {
        'translationTypes': ['subEn'],
      }).getConcrete(uid: frierenUid, data: {});
      expect(concrete.groups, isNotEmpty);
      for (final group in concrete.groups) {
        expect(group.title, startsWith('Англ. субтитры · '));
        expect(group.elements.first.data['kind'], 'subEn');
      }
    });
  });
}
