@Timeout(Duration(minutes: 10))
library;

import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_skip_marker.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:puppeteer/puppeteer.dart' show Until;
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/real_browser_interceptor_controller.dart';
import '../helpers/scraper_helpers.dart';

const String extensionDirectory = 'anime/anitube_in_ua';
const String titleWithManyDubs = '6129-vesllya-svtlyachkv.html';
const String fenixEpisode =
    'https://fenixplay.xyz/vod/eyJ0Ijoidm9kIiwicyI6ImNob3JuYS1rb255dXNoeW5hIiwiZSI6MSwidiI6InR2IiwibCI6IkZhblZveFVhIn0.XrVs0mwavrxht_zeDeckfpq7qyB_QvL-BaoeKnPvJUg';
const String ashdiEpisode = 'https://ashdi.vip/vod/214530';
const Duration requestSpacing = Duration(seconds: 4);
const List<String> nativeHostMarkers = [
  'ashdi.',
  'fenixplay.',
  'moonanime.',
  'mp4upload.',
];

Map<String, Object?> syntheticGroup(String title, String host, String dub) {
  return {
    'title': title,
    'host': host,
    'dub': dub,
    'videos': [
      {'title': '1', 'src': 'https://$host/vod/$title', 'dub': dub},
    ],
  };
}

final List<Map<String, Object?>> syntheticGroups = [
  syntheticGroup('Amanogawa · ASHDI', 'ashdi.vip', 'Amanogawa'),
  syntheticGroup('Amanogawa · FENIXPLAY', 'fenixplay.xyz', 'Amanogawa'),
  syntheticGroup('FanVoxUA · ASHDI', 'ashdi.vip', 'FanVoxUA'),
  syntheticGroup('FanVoxUA · TORTUGA', 'tortuga.tw', 'FanVoxUA'),
  syntheticGroup('FanVoxUA · MOONANIME', 'moonanime.net', 'FanVoxUA'),
];

AnimeVideo iframeVideo(String src, [Map<String, dynamic>? data]) {
  return AnimeVideo(
    type: AnimeVideoType.IFRAME,
    uid: src,
    src: src,
    title: src,
    timestamp: null,
    data: data ?? {'title': src, 'src': src},
  );
}

String hostOfSrc(String src) {
  var embedUrl = src.trim();
  if (embedUrl.startsWith('//')) {
    embedUrl = 'https:$embedUrl';
  }
  if (!embedUrl.contains('://')) {
    return '';
  }
  return embedUrl.split('://')[1].split('/')[0].toLowerCase();
}

Set<String> uidSet(AnimeConcreteView concrete) {
  return concrete.groups
      .expand((group) => group.elements)
      .map((video) => video.uid)
      .toSet();
}

void main() {
  late ConfigInfo config;

  setUpAll(() {
    config = loadConfig(extensionDirectory);
  });

  group('config', () {
    test('declares api 2 preferences and a request rate limit', () {
      expect(config.apiVersion, 2);
      expect(config.preferences.map((preference) => preference.key), [
        'preferredPlayer',
        'preferredDubs',
        'hideUnsupportedPlayers',
      ]);
      expect(config.preferences.first.effectiveDefault, 'auto');
      expect(config.requestPolicy?.rateLimit?.requests, 3);
      expect(config.requestPolicy?.rateLimit?.perSeconds, 2);
    });
  });

  group('episode group ordering', () {
    Future<List<String>> orderedTitles(Map<String, Object?> preferences) async {
      final client = AnimeApiClient(
        code: readScript(extensionDirectory),
        host: hostFor(config, preferences: preferences),
      );
      final resolved = await client.interpreter.runFunction(
        'readGroupPreferences',
      );
      final ordered = await client.interpreter.runFunction(
        'orderEpisodeGroups',
        arguments: {'rawGroups': syntheticGroups, 'groupPreferences': resolved},
      ) as List;
      return ordered.map((group) => (group as Map)['title'] as String).toList();
    }

    test('defaults keep the site order with native players first', () async {
      expect(await orderedTitles({}), [
        'Amanogawa · ASHDI',
        'Amanogawa · FENIXPLAY',
        'FanVoxUA · ASHDI',
        'FanVoxUA · MOONANIME',
        'FanVoxUA · TORTUGA',
      ]);
    });

    test('a preferred player leads within each dub', () async {
      expect(await orderedTitles({'preferredPlayer': 'fenixplay'}), [
        'Amanogawa · FENIXPLAY',
        'Amanogawa · ASHDI',
        'FanVoxUA · ASHDI',
        'FanVoxUA · MOONANIME',
        'FanVoxUA · TORTUGA',
      ]);
    });

    test('preferred dubs come first, in the listed order', () async {
      expect(
        await orderedTitles({
          'preferredDubs': ' fanvoxua , Amanogawa',
          'preferredPlayer': 'moonanime',
        }),
        [
          'FanVoxUA · MOONANIME',
          'FanVoxUA · ASHDI',
          'FanVoxUA · TORTUGA',
          'Amanogawa · ASHDI',
          'Amanogawa · FENIXPLAY',
        ],
      );
    });

    test('hiding unsupported players drops other hosts', () async {
      final titles = await orderedTitles({'hideUnsupportedPlayers': true});
      expect(titles, isNot(contains('FanVoxUA · TORTUGA')));
      expect(titles, hasLength(4));
    });

    test('hiding never empties a title without native players', () async {
      final client = AnimeApiClient(
        code: readScript(extensionDirectory),
        host: hostFor(config, preferences: {'hideUnsupportedPlayers': true}),
      );
      final ordered = await client.interpreter.runFunction(
        'orderEpisodeGroups',
        arguments: {
          'rawGroups': [syntheticGroup('Dub · TORTUGA', 'tortuga.tw', 'Dub')],
          'groupPreferences': await client.interpreter.runFunction(
            'readGroupPreferences',
          ),
        },
      ) as List;
      expect(ordered, hasLength(1));
    });
  });

  group('video sources', () {
    late AnimeApiClient client;

    setUpAll(() {
      client = AnimeApiClient(
        code: readScript(extensionDirectory),
        host: hostFor(config),
      );
    });

    test('fenixplay sources carry the track dub and API skip markers',
        () async {
      final sources = await client.getVideoSources(iframeVideo(fenixEpisode));
      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(source.audioLabel, isNotEmpty);
        expect(source.skip, isNotEmpty);
        for (final marker in source.skip) {
          expect(marker.type, isIn([AnimeSkipType.intro, AnimeSkipType.outro]));
          expect(marker.end, greaterThan(marker.start));
          expect(marker.start, greaterThanOrEqualTo(0));
        }
      }
      expect(
        sources.first.skip.map((marker) => marker.type),
        contains(AnimeSkipType.outro),
      );
    });

    test('the episode dub from the site wins over the player label', () async {
      final sources = await client.getVideoSources(iframeVideo(fenixEpisode, {
        'title': '1',
        'src': fenixEpisode,
        'dub': 'FanVoxUA',
      }));
      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(source.audioLabel, 'FanVoxUA');
      }
    });

    test('ashdi sources get the episode dub and no invented markers',
        () async {
      final labelled = await client.getVideoSources(iframeVideo(ashdiEpisode, {
        'title': '1',
        'src': ashdiEpisode,
        'dub': 'Tviytatko',
      }));
      expect(labelled, isNotEmpty);
      expect(labelled.first.audioLabel, 'Tviytatko');
      expect(labelled.first.skip, isEmpty);
      final unlabelled = await client.getVideoSources(iframeVideo(ashdiEpisode));
      expect(unlabelled.first.audioLabel, isNull);
    });
  });

  group('live episode groups', () {
    late RealBrowserInterceptorController browser;
    late AnimeConcreteView defaults;
    late AnimeConcreteView preferred;
    late AnimeConcreteView hidden;
    late String preferredDub;

    Future<AnimeConcreteView> concreteWith(Map<String, Object?> preferences) {
      final client = AnimeApiClient(
        code: readScript(extensionDirectory),
        host: hostFor(config, preferences: preferences),
      );
      return Future.delayed(requestSpacing, () async {
        await client.passWebBrowserInterceptorController(controller: browser);
        await setupBrowserWithCookies(
          client.interpreter,
          browser,
          'https://anitube.in.ua',
        );
        return client.getConcrete(
          uid: titleWithManyDubs,
          data: {'cover': '', 'title': titleWithManyDubs},
        );
      });
    }

    setUpAll(() async {
      browser = RealBrowserInterceptorController(
        headless: true,
        waitUntil: Until.load,
      );
      await browser.launch();
      defaults = await concreteWith({});
      preferredDub = defaults.groups.last.title.split(' · ').first;
      preferred = await concreteWith({
        'preferredDubs': preferredDub,
        'preferredPlayer': 'ashdi',
      });
      hidden = await concreteWith({'hideUnsupportedPlayers': true});
    });

    tearDownAll(() async {
      await browser.dispose();
    });

    test('episode data carries the dub for audio labels', () {
      expect(defaults.groups, isNotEmpty);
      for (final group in defaults.groups) {
        for (final video in group.elements) {
          expect(video.data['dub'], isA<String>());
        }
      }
    });

    test('preferences reorder groups without changing uids', () {
      expect(uidSet(preferred), equals(uidSet(defaults)));
      expect(preferred.groups.first.title, startsWith(preferredDub));
    });

    test('hiding unsupported players keeps only native hosts', () {
      expect(hidden.groups, isNotEmpty);
      for (final group in hidden.groups) {
        final host = hostOfSrc(group.elements.first.src);
        expect(nativeHostMarkers.any(host.contains), isTrue, reason: host);
      }
    });

    test('a missing title is reported as not found', () async {
      final client = AnimeApiClient(
        code: readScript(extensionDirectory),
        host: hostFor(config),
      );
      await client.passWebBrowserInterceptorController(controller: browser);
      await expectSourceError(
        () => client.getConcrete(
          uid: '999999-does-not-exist.html',
          data: {'cover': '', 'title': 'missing'},
        ),
        SourceErrorKind.notFound,
      );
    });
  });
}
