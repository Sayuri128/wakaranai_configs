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
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:puppeteer/puppeteer.dart' show Until;
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/real_browser_interceptor_controller.dart';

const String extensionDirectory = 'anime/anihub';
const Duration appVideoSourcesTimeout = Duration(seconds: 20);

class NullLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

class AnihubSession {
  final RealBrowserInterceptorController browser;
  final AnimeApiClient client;
  final ConfigInfo config;

  AnihubSession(this.browser, this.client, this.config);

  static Future<AnihubSession> open({
    Map<String, Object?> preferences = const {},
  }) async {
    final config = loadConfig(extensionDirectory);
    final client = AnimeApiClient(
      code: readScript(extensionDirectory),
      host: hostFor(config, preferences: preferences),
    );
    final browser = RealBrowserInterceptorController(
      headless: true,
      waitUntil: Until.domContentLoaded,
    );
    await browser.launch();
    await client.passWebBrowserInterceptorController(controller: browser);
    await client.passProtector(body: '', headers: {}, cookies: {});
    return AnihubSession(browser, client, config);
  }

  FilterData filter(String param, List<String> values) {
    final definition = config.filters.firstWhere((f) => f.param == param);
    return FilterDataMultipleOfMultiple(selected: [values], filter: definition);
  }

  Future<List<AnimeGalleryView>> gallery({
    int page = 1,
    String query = '',
    List<FilterData> filters = const [],
    String feed = 'updated',
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

  Future<void> close() => browser.dispose();
}

Future<AnihubSession?> tryOpenSession({
  Map<String, Object?> preferences = const {},
}) async {
  try {
    return await AnihubSession.open(preferences: preferences);
  } catch (error) {
    print('skipping anihub browser tests: $error');
    return null;
  }
}

bool skipWithoutBrowser(AnihubSession? session) {
  if (session == null) {
    markTestSkipped('puppeteer/chrome is unavailable');
    return true;
  }
  return false;
}

Future<AnimeConcreteView?> firstConcreteWithEpisodes(
  AnihubSession session,
  List<AnimeGalleryView> items, {
  String? player,
}) async {
  final candidates = items.take(4);
  for (final item in candidates) {
    final concrete = await session.concrete(item);
    final hasEpisodes = concrete.groups.any(
      (group) => group.elements.any(
        (video) => player == null || video.data['player'] == player,
      ),
    );
    if (hasEpisodes) {
      return concrete;
    }
  }
  return null;
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

Future<String> fetchPlaylist(AnimeVideoSource source) async {
  final response = await http
      .get(Uri.parse(source.url), headers: source.headers)
      .timeout(const Duration(seconds: 30));
  expect(response.statusCode, 200);
  return response.body;
}

void main() {
  Logger.level = Level.off;
  Logger.defaultOutput = () => NullLogOutput();

  AnihubSession? session;

  setUpAll(() async {
    session = await tryOpenSession();
  });

  tearDownAll(() async {
    await session?.close();
  });

  group('getGallery', () {
    late List<AnimeGalleryView> page1;
    late List<AnimeGalleryView> page2;

    setUpAll(() async {
      final active = session;
      if (active == null) {
        return;
      }
      page1 = await active.gallery(page: 1);
      page2 = await active.gallery(page: 2);
    });

    test('first catalogue page has one site page of titles', () {
      if (skipWithoutBrowser(session)) {
        return;
      }
      expect(page1, isNotEmpty);
      expect(page1.length, lessThanOrEqualTo(24));
      for (final item in page1) {
        expect(item.uid, isNot(contains('/')));
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://'));
        expect(item.data['title'], item.title);
      }
    });

    test('second page continues the infinite scroll without repeats', () {
      if (skipWithoutBrowser(session)) {
        return;
      }
      expect(page2, isNotEmpty);
      final firstUids = page1.map((item) => item.uid).toSet();
      expect(page2.where((item) => firstUids.contains(item.uid)), isEmpty);
    });

    test('search finds titles by name', () async {
      if (skipWithoutBrowser(session)) {
        return;
      }
      final results = await session!.gallery(query: 'наруто');
      expect(results, isNotEmpty);
      expect(
        results.any((item) => item.title.toLowerCase().contains('наруто')),
        isTrue,
      );
    });

    test('a search with no matches is empty rather than an error', () async {
      if (skipWithoutBrowser(session)) {
        return;
      }
      final results = await session!.gallery(query: 'zzqqxxyyww');
      expect(results, isEmpty);
    });

    test('type and genre filters narrow the catalogue', () async {
      if (skipWithoutBrowser(session)) {
        return;
      }
      final results = await session!.gallery(
        filters: [
          session!.filter('type', ['movie']),
          session!.filter('genres', ['Slice of Life']),
        ],
      );
      expect(results, isNotEmpty);
      final unfiltered = page1.map((item) => item.uid).toList();
      expect(results.map((item) => item.uid).toList(), isNot(unfiltered));
    });
  });

  group('getConcrete', () {
    AnimeConcreteView? concrete;

    setUpAll(() async {
      final active = session;
      if (active == null) {
        return;
      }
      concrete = await firstConcreteWithEpisodes(
        active,
        await active.gallery(feed: 'episodes'),
      );
    });

    test('reads details from the rendered title page', () {
      if (skipWithoutBrowser(session)) {
        return;
      }
      expect(concrete, isNotNull);
      expect(concrete!.title, isNotEmpty);
      expect(concrete!.description, isNotEmpty);
      expect(concrete!.cover, startsWith('https://'));
      expect(concrete!.tags, isNotEmpty);
      expect(concrete!.description, isNot(contains('](/characters/')));
    });

    test('groups are one dub and player each, keyed by embed url', () {
      if (skipWithoutBrowser(session)) {
        return;
      }
      expect(concrete!.groups, isNotEmpty);
      final titles = <String>{};
      for (final group in concrete!.groups) {
        expect(group.title, contains(' · '));
        expect(titles.add(group.title), isTrue, reason: group.title);
        expect(group.elements, isNotEmpty);
        for (final video in group.elements) {
          expect(video.type, AnimeVideoType.IFRAME);
          expect(video.uid, video.src);
          expect(video.src, startsWith('https://'));
          expect(video.data['dub'], isNotEmpty);
          expect(
            video.data['player'],
            anyOf('fenix', 'ashdi', 'moonanime'),
          );
          expect(video.title, startsWith('Серія'));
        }
      }
    });

    test('a removed title is reported as not found', () async {
      if (skipWithoutBrowser(session)) {
        return;
      }
      await expectSourceError(
        () => session!.client.getConcrete(
          uid: 'does-not-exist-999999999',
          data: {'title': 'missing', 'cover': ''},
        ),
        SourceErrorKind.notFound,
      );
    });
  });

  for (final player in ['ashdi', 'fenix', 'moonanime']) {
    group('getVideoSources for $player', () {
      AnimeVideo? video;
      List<AnimeVideoSource> sources = [];
      Duration elapsed = Duration.zero;

      setUpAll(() async {
        final active = session;
        if (active == null) {
          return;
        }
        final items = await active.gallery(
          feed: 'episodes',
          filters: [active.filter('players', [player])],
        );
        final concrete = await firstConcreteWithEpisodes(
          active,
          items,
          player: player,
        );
        video = concrete == null ? null : firstVideoOf(concrete, player);
        if (video == null) {
          return;
        }
        final stopwatch = Stopwatch()..start();
        sources = await active.client.getVideoSources(video!);
        elapsed = stopwatch.elapsed;
      });

      test('resolves the embedded player to a playable hls stream', () async {
        if (skipWithoutBrowser(session)) {
          return;
        }
        expect(video, isNotNull, reason: 'no $player episode found');
        expect(sources, isNotEmpty);
        expect(elapsed, lessThan(appVideoSourcesTimeout));
        final source = sources.first;
        expect(source.format, 'hls');
        expect(source.audioLabel, video!.data['dub']);
        expect(source.headers['Referer'], isNotEmpty);
        expect(await fetchPlaylist(source), startsWith('#EXTM3U'));
      });
    });
  }

  group('preferences', () {
    AnihubSession? preferred;

    setUpAll(() async {
      preferred = await tryOpenSession(
        preferences: {'preferredPlayer': 'moonanime'},
      );
    });

    tearDownAll(() async {
      await preferred?.close();
    });

    test('the preferred player comes first within a dub', () async {
      if (skipWithoutBrowser(preferred)) {
        return;
      }
      final active = preferred!;
      final items = await active.gallery(
        feed: 'episodes',
        filters: [active.filter('players', ['moonanime'])],
      );
      final concrete = await firstConcreteWithEpisodes(
        active,
        items,
        player: 'moonanime',
      );
      expect(concrete, isNotNull);
      final firstDubGroup = concrete!.groups.first;
      final firstDub = firstDubGroup.elements.first.data['dub'];
      final sameDub = concrete.groups
          .where((group) => group.elements.first.data['dub'] == firstDub)
          .toList();
      final hasMoon = sameDub.any(
        (group) => group.elements.first.data['player'] == 'moonanime',
      );
      if (hasMoon) {
        expect(firstDubGroup.elements.first.data['player'], 'moonanime');
      }
    });
  });
}
