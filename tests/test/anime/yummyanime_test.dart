import 'dart:io';

import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video_source.dart';
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
import '../helpers/scraper_helpers.dart';
import '../helpers/script_bundle.dart';

const String extensionDirectory = 'anime/yummyanime';
const Duration appVideoSourcesTimeout = Duration(seconds: 20);

final String? yummyToken = Platform.environment['YUMMYANIME_TOKEN'];

class NullLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

class YummySession {
  final AnimeApiClient client;
  final ConfigInfo config;

  YummySession(this.client, this.config);

  factory YummySession.open({Map<String, Object?> preferences = const {}}) {
    final config = loadConfig(extensionDirectory);
    final client = AnimeApiClient(
      code: bundleScript(scriptPath('$extensionDirectory/main.capyscript')),
      host: hostFor(
        config,
        preferences: <String, Object?>{
          'applicationToken': yummyToken ?? '',
          ...preferences,
        },
        storage: MemoryExtensionStorage(),
      ),
    );
    return YummySession(client, config);
  }

  FilterData filter(String param, List<String> values) {
    final definition = config.filters.firstWhere((f) => f.param == param);
    return FilterDataMultipleOfMultiple(selected: [values], filter: definition);
  }

  FilterData years(String from, String to) {
    final definition = config.filters.firstWhere((f) => f.param == 'year');
    return FilterDataRange(from: from, to: to, filter: definition);
  }

  Future<List<AnimeGalleryView>> gallery({
    int page = 1,
    String query = '',
    List<FilterData> filters = const [],
    String feed = 'updates',
  }) {
    return client.getGallery(
      page: page,
      query: query,
      filters: filters,
      feed: feed,
      pageSize: 0,
    );
  }

  Future<AnimeConcreteView> concrete(AnimeGalleryView item) {
    return client.getConcrete(uid: item.uid, data: item.data);
  }
}

AnimeVideo? firstVideoOf(AnimeConcreteView concrete, String player) {
  for (final group in concrete.groups) {
    for (final video in group.elements) {
      if (video.data['player'] == player) {
        return video;
      }
    }
  }
  return null;
}

Future<AnimeVideo?> findVideo(YummySession session, String player) async {
  final items = await session.gallery(feed: 'popular');
  for (final item in items.take(12)) {
    final AnimeConcreteView concrete;
    try {
      concrete = await session.concrete(item);
    } on SourceError {
      continue;
    }
    final video = firstVideoOf(concrete, player);
    if (video != null) {
      return video;
    }
  }
  return null;
}

Future<String> fetchText(AnimeVideoSource source) async {
  final response = await http
      .get(Uri.parse(source.url), headers: source.headers)
      .timeout(const Duration(seconds: 30));
  expect(response.statusCode, 200, reason: Uri.parse(source.url).host);
  return response.body;
}

void main() {
  test('works without an application token', () async {
    final session = YummySession.open(preferences: <String, Object?>{'applicationToken': ''});
    final gallery = await session.client.getGallery(page: 1, query: '', filters: [], feed: '');
    expect(gallery, isNotEmpty);
  });

  Logger.level = Level.off;
  Logger.defaultOutput = () => NullLogOutput();

  late YummySession session;

  setUpAll(() {
    session = YummySession.open();
  });

  group('getGallery', () {
    test('the new episodes feed lists titles with their latest episode', () async {
      final items = await session.gallery();
      expect(items, isNotEmpty);
      expect(items.map((item) => item.uid).toSet().length, items.length);
      for (final item in items) {
        expect(int.tryParse(item.uid), isNotNull, reason: item.uid);
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://'));
        expect(item.latestChapter, startsWith('Серия '));
      }
      expect(await session.gallery(page: 2), isEmpty);
    });

    test('the popular feed pages through the catalog without repeats', () async {
      final first = await session.gallery(feed: 'popular');
      final second = await session.gallery(feed: 'popular', page: 2);
      expect(first.length, 30);
      expect(second, isNotEmpty);
      final firstUids = first.map((item) => item.uid).toSet();
      expect(second.where((item) => firstUids.contains(item.uid)), isEmpty);
      expect(first.first.data['title'], first.first.title);
    });

    test('type, genre and year filters narrow the catalog', () async {
      final movies = await session.gallery(
        feed: 'popular',
        filters: [
          session.filter('types', ['movie']),
          session.filter('genres', ['sport']),
          session.years('2015', '2024'),
        ],
      );
      expect(movies, isNotEmpty);
      for (final item in movies) {
        expect(item.subtitle, 'Полнометражный фильм');
        expect(item.year, inInclusiveRange(2015, 2024));
      }
    });

    test('filters on the new episodes feed fall back to the catalog', () async {
      final ongoing = await session.gallery(
        filters: [session.filter('status', ['ongoing'])],
      );
      expect(ongoing.length, 30);
    });

    test('search finds titles by name', () async {
      final results = await session.gallery(query: 'Наруто');
      expect(results, isNotEmpty);
      expect(results.any((item) => item.title.contains('Наруто')), isTrue);
    });

    test('a search with no matches is empty rather than an error', () async {
      expect(await session.gallery(query: 'zzqqxxyyww'), isEmpty);
    });
  });

  group('getConcrete', () {
    late AnimeConcreteView concrete;

    setUpAll(() async {
      final items = await session.gallery(feed: 'popular');
      concrete = await session.concrete(items.first);
    });

    test('reads details from the api', () {
      expect(concrete.title, isNotEmpty);
      expect(concrete.description, isNotEmpty);
      expect(concrete.cover, startsWith('https://'));
      expect(concrete.tags, isNotEmpty);
      expect(concrete.alternativeTitles, isNotEmpty);
      expect(concrete.url, startsWith('https://yummyani.me/catalog/item/'));
    });

    test('groups are one dub and player each', () {
      expect(concrete.groups, isNotEmpty);
      final titles = <String>{};
      for (final group in concrete.groups) {
        expect(group.title, contains(' · '));
        expect(titles.add(group.title), isTrue, reason: group.title);
        expect(group.elements, isNotEmpty);
        final numbers = group.elements
            .map((video) => video.number)
            .whereType<double>()
            .toList();
        for (var index = 1; index < numbers.length; index++) {
          expect(numbers[index], greaterThanOrEqualTo(numbers[index - 1]));
        }
        for (final video in group.elements) {
          expect(video.type, AnimeVideoType.IFRAME);
          expect(int.tryParse(video.uid), isNotNull);
          expect(video.src, startsWith('https://'));
          expect(group.title, startsWith(video.data['dub'] as String));
          expect(video.title, startsWith('Серия'));
        }
      }
    });

    test('an unknown title is reported as not found', () async {
      await expectSourceError(
        () => session.client.getConcrete(uid: '999999999', data: {}),
        SourceErrorKind.notFound,
      );
    });
  });

  group('getVideoSources', () {
    test('resolves kodik to hls streams labelled with the dub', () async {
      final video = await findVideo(session, 'kodik');
      expect(video, isNotNull, reason: 'no kodik episode found');
      final stopwatch = Stopwatch()..start();
      final sources = await session.client.getVideoSources(video!);
      expect(stopwatch.elapsed, lessThan(appVideoSourcesTimeout));
      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(source.format, 'hls');
        expect(source.quality, endsWith('p'));
        expect(source.audioLabel, video.data['dub']);
      }
      expect(await fetchText(sources.first), startsWith('#EXTM3U'));
    });

    test('resolves cvh to hls plus mp4 files for downloads', () async {
      final video = await findVideo(session, 'cvh');
      expect(video, isNotNull, reason: 'no cvh episode found');
      final sources = await session.client.getVideoSources(video!);
      expect(sources, isNotEmpty);
      expect(sources.first.format, 'hls');
      expect(sources.first.preferForDownload, isFalse);
      final files = sources.where((source) => source.format == 'mp4');
      expect(files, isNotEmpty);
      expect(files.every((source) => source.preferForDownload), isTrue);
      expect(sources.every((s) => s.audioLabel == video.data['dub']), isTrue);
      expect(await fetchText(sources.first), startsWith('#EXTM3U'));
    });

    test('resolves aksor to dash manifests', () async {
      final video = await findVideo(session, 'aksor');
      if (video == null) {
        markTestSkipped('no aksor episode among popular titles');
        return;
      }
      final sources = await session.client.getVideoSources(video);
      expect(sources, isNotEmpty);
      expect(sources.first.format, 'dash');
      expect(await fetchText(sources.first), contains('<MPD'));
    });

    test('leaves alloha to the web player', () async {
      final video = await findVideo(session, 'alloha');
      expect(video, isNotNull, reason: 'no alloha episode found');
      expect(await session.client.getVideoSources(video!), isEmpty);
    });
  });

  group('preferences', () {
    test('the preferred player comes first within a dub', () async {
      final preferred = YummySession.open(
        preferences: {'preferredPlayer': 'alloha'},
      );
      final items = await preferred.gallery(feed: 'popular');
      final concrete = await preferred.concrete(items.first);
      final firstDub = concrete.groups.first.elements.first.data['dub'];
      final sameDub = concrete.groups
          .where((group) => group.elements.first.data['dub'] == firstDub)
          .toList();
      final hasAlloha = sameDub.any(
        (group) => group.elements.first.data['player'] == 'alloha',
      );
      if (hasAlloha) {
        expect(concrete.groups.first.elements.first.data['player'], 'alloha');
      }
    });

    test('preferred dubs are listed first', () async {
      final items = await session.gallery(feed: 'popular');
      final plain = await session.concrete(items.first);
      final dubs = plain.groups
          .map((group) => group.elements.first.data['dub'] as String)
          .toSet()
          .toList();
      if (dubs.length < 2) {
        markTestSkipped('only one dub');
        return;
      }
      final preferred = YummySession.open(
        preferences: {'preferredDubs': dubs.last},
      );
      final concrete = await preferred.concrete(items.first);
      final firstDub = concrete.groups.first.elements.first.data['dub'] as String;
      expect(firstDub.toLowerCase(), contains(dubs.last.toLowerCase()));
    });
  });
}
