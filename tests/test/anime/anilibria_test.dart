import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_skip_marker.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_gallery_view/anime_gallery_view.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/filter_data.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/range/range.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String extensionDirectory = 'anime/anilibria';
const String soloLevelingUid = '9600';
const String soloLevelingSequelUid = '9839';
const String bleachUid = '8452';

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

  Future<List<AnimeGalleryView>> gallery({
    AnimeApiClient? using,
    int page = 1,
    String query = '',
    List<FilterData> filters = const [],
    String feed = 'updates',
    int pageSize = 0,
  }) {
    return (using ?? client).getGallery(
      page: page,
      query: query,
      filters: filters,
      feed: feed,
      pageSize: pageSize,
    );
  }

  Matcher isMirrorMedia() {
    final origins = config.requestPolicy!.mirrors
        .map((mirror) => mirror.substring(0, mirror.indexOf('/api/')))
        .toList();
    return predicate<String>(
      (url) => origins.any((origin) => url.startsWith('$origin/storage/')),
      'a storage url on one of the mirrors',
    );
  }

  FilterData multipleFilter(String param, List<String> values) {
    final definition = config.filters.firstWhere((f) => f.param == param);
    return FilterDataMultipleOfMultiple(selected: [values], filter: definition);
  }

  setUpAll(() {
    config = loadConfig(extensionDirectory);
    client = clientWith(const {});
  });

  group('getGallery', () {
    test('lists recently updated releases with the default page size', () async {
      final items = await gallery();
      expect(items, hasLength(config.pagination!.defaultPageSize));
      for (final item in items) {
        expect(int.tryParse(item.uid), isNotNull);
        expect(item.title, isNotEmpty);
        expect(item.cover, isMirrorMedia());
        expect(item.data['alias'], isNotEmpty);
      }
      expect(items.any((item) => item.tags.isNotEmpty), isTrue);
    });

    test('honours the chosen page size and pages without repeats', () async {
      final first = await gallery(pageSize: 15);
      final second = await gallery(page: 2, pageSize: 15);
      expect(first, hasLength(15));
      expect(second, hasLength(15));
      final firstUids = first.map((item) => item.uid).toSet();
      expect(second.where((item) => firstUids.contains(item.uid)), isEmpty);
    });

    test('popular feed starts with the most followed releases', () async {
      final items = await gallery(feed: 'popular');
      expect(
        items.map((item) => item.uid),
        anyOf(contains(soloLevelingUid), contains(soloLevelingSequelUid)),
      );
    });

    test('ongoing feed only lists ongoing releases', () async {
      final items = await gallery(feed: 'ongoing');
      expect(items, isNotEmpty);
      expect(items.every((item) => item.status == AnimeStatus.ONGOING), isTrue);
    });

    test('newest feed orders by year', () async {
      final items = await gallery(feed: 'newest');
      final years = items.map((item) => item.year ?? 0).toList();
      expect(years.first, greaterThanOrEqualTo(years.last));
      expect(years.first, greaterThanOrEqualTo(2025));
    });

    test('filters by genre', () async {
      final items = await gallery(filters: [multipleFilter('genres', ['12'])]);
      expect(items, isNotEmpty);
      expect(items.every((item) => item.tags.contains('Спорт')), isTrue);
    });

    test('filters by a year range', () async {
      final range = config.filters.firstWhere((f) => f.param == 'years');
      final items = await gallery(
        filters: [FilterDataRange(from: '2000', to: '2005', filter: range)],
      );
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.year, inInclusiveRange(2000, 2005));
      }
    });

    test('searches by russian and english names', () async {
      final russian = await gallery(query: 'Блич', feed: '');
      final english = await gallery(query: 'Bleach', feed: '');
      expect(russian.map((item) => item.uid), contains(bleachUid));
      expect(english.map((item) => item.uid), contains(bleachUid));
    });

    test('a search with no matches is empty rather than an error', () async {
      final items = await gallery(query: 'zzqqxxwakaranainothing', feed: '');
      expect(items, isEmpty);
    });

    test('every declared mirror serves the catalogue', () async {
      for (final mirror in config.requestPolicy!.mirrors) {
        final mirrored = clientWith({'__mirror': mirror});
        final items = await gallery(using: mirrored, pageSize: 15);
        final origin = mirror.substring(0, mirror.indexOf('/api/'));
        expect(items, isNotEmpty, reason: mirror);
        expect(items.first.cover, startsWith('$origin/storage/'), reason: mirror);
      }
    });
  });

  group('title', () {
    late AnimeConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: soloLevelingUid, data: {});
    });

    test('has details', () {
      expect(concrete.title, 'Поднятие уровня в одиночку');
      expect(concrete.alternativeTitles, contains('Ore dake Level Up na Ken'));
      expect(concrete.alternativeTitles, contains('Solo Leveling'));
      expect(concrete.description, contains('\n\nОзвучка: '));
      expect(concrete.description, isNot(contains('\r')));
      expect(concrete.tags, containsAll(['Экшен', 'Фэнтези']));
      expect(concrete.year, 2024);
      expect(concrete.status, AnimeStatus.RELEASED);
      expect(concrete.cover, isMirrorMedia());
      expect(
        concrete.url,
        'https://aniliberty.top/anime/releases/release/ore-dake-level-up-na-ken',
      );
    });

    test('lists one dub group with numbered direct episodes', () {
      expect(concrete.groups, hasLength(1));
      final group = concrete.groups.single;
      expect(group.title, 'AniLibria');
      expect(group.elements, hasLength(12));
      for (var index = 0; index < group.elements.length; index++) {
        final episode = group.elements[index];
        expect(episode.number, index + 1);
        expect(episode.type, AnimeVideoType.DIRECT);
        expect(episode.src, contains('.m3u8'));
        expect(episode.title, startsWith('Серия ${index + 1}'));
      }
    });

    test('resolves an episode to hls sources per quality with skip markers', () async {
      final episode = concrete.groups.single.elements[1];
      final sources = await client.getVideoSources(episode);
      expect(sources.map((source) => source.quality), ['1080p', '720p', '480p']);
      for (final source in sources) {
        expect(source.format, 'hls');
        expect(source.audioLabel, 'AniLibria');
        expect(source.preferForDownload, isTrue);
        expect(source.url, startsWith('https://'));
      }
      final skip = sources.first.skip;
      final intro = skip.firstWhere((marker) => marker.type == AnimeSkipType.intro);
      final outro = skip.firstWhere((marker) => marker.type == AnimeSkipType.outro);
      expect(intro.end, greaterThan(intro.start));
      expect(outro.start, greaterThan(intro.end));

      final response = await http
          .get(Uri.parse(sources[1].url), headers: sources[1].headers)
          .timeout(const Duration(seconds: 30));
      expect(response.statusCode, 200);
      expect(response.body, startsWith('#EXTM3U'));
    });

    test('lists related franchise releases without the title itself', () async {
      final related = await client.getRelated(uid: soloLevelingUid, data: {});
      final uids = related.map((item) => item.uid).toList();
      expect(uids, contains(soloLevelingSequelUid));
      expect(uids, isNot(contains(soloLevelingUid)));
    });
  });

  test('keeps long releases in episode order', () async {
    final bleach = await client.getConcrete(uid: bleachUid, data: {});
    final numbers = bleach.groups.single.elements.map((e) => e.number!).toList();
    expect(numbers.length, greaterThan(300));
    expect(numbers.first, 1);
    for (var index = 1; index < numbers.length; index++) {
      expect(numbers[index], greaterThan(numbers[index - 1]));
    }
  });

  test('reports a missing release as not found', () async {
    await expectSourceError(
      () => client.getConcrete(uid: '99999999', data: {}),
      SourceErrorKind.notFound,
    );
  });

  test('reports a missing episode as not found', () async {
    final concrete = await client.getConcrete(uid: soloLevelingUid, data: {});
    final episode = concrete.groups.single.elements.first;
    final missing = episode.copyWith(uid: '00000000-0000-0000-0000-000000000000');
    await expectSourceError(
      () => client.getVideoSources(missing),
      SourceErrorKind.notFound,
    );
  });
}
