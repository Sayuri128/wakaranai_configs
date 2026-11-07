@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/http/http_interceptor_controller.dart';
import 'package:puppeteer/puppeteer.dart' show Until;
import 'package:test/test.dart';
import '../helpers/real_browser_interceptor_controller.dart';
import '../helpers/scraper_helpers.dart';

const String previousScriptRevision = '9af9b27';
const String titleWithManyDubs = '6129-vesllya-svtlyachkv.html';
const String titleWithSubtitlesAndDub = '4462-klub-legkoyi-muziki-2-sezon.html';
const String longFinishedTitle = '3008-chorna-konyushina.html';
const List<String> checkedTitles = [
  titleWithManyDubs,
  titleWithSubtitlesAndDub,
  longFinishedTitle,
];
const List<String> nativeHostMarkers = [
  'ashdi.',
  'fenixplay.',
  'moonanime.',
  'mp4upload.',
];
const List<String> playerPrefixWords = ['ПЛЕЄР', 'ОЗВУЧЕННЯ', 'СУБТИТРИ'];
const Duration requestSpacing = Duration(seconds: 4);
const Duration rateLimitCooldown = Duration(seconds: 20);

class PlaylistReadyBrowser extends RealBrowserInterceptorController {
  PlaylistReadyBrowser() : super(headless: true, waitUntil: Until.load);

  @override
  Future<HttpInterceptorControllerResponse> loadPage({
    required String url,
    String? method,
    Map<String, String>? headers,
    String? body,
  }) async {
    final response = await super.loadPage(
      url: url,
      method: method,
      headers: headers,
      body: body,
    );
    try {
      await page.waitForSelector(
        '.playlists-videos .playlists-items li',
        timeout: const Duration(seconds: 30),
      );
    } catch (_) {}
    return response;
  }
}

String embedHostOf(String src) {
  var embedUrl = src.trim();
  if (embedUrl.startsWith('//')) {
    embedUrl = 'https:$embedUrl';
  }
  if (embedUrl.startsWith('https://http://') ||
      embedUrl.startsWith('https://https://')) {
    embedUrl = embedUrl.substring(8);
  }
  if (!embedUrl.contains('://')) {
    return '';
  }
  return embedUrl
      .split('://')[1]
      .split('/')[0]
      .split('?')[0]
      .toLowerCase();
}

bool isNativeHost(String host) {
  return nativeHostMarkers.any(host.contains);
}

Iterable<AnimeVideo> allVideos(AnimeConcreteView concrete) {
  return concrete.groups.expand((group) => group.elements);
}

Set<String> uidSet(AnimeConcreteView concrete) {
  return allVideos(concrete).map((video) => video.uid).toSet();
}

Future<AnimeApiClient> connectAnitube(
  RealBrowserInterceptorController browser,
  String scriptCode,
) async {
  final client = AnimeApiClient(code: scriptCode);
  await browser.launch();
  await client.passWebBrowserInterceptorController(controller: browser);
  await setupBrowserWithCookies(
    client.interpreter,
    browser,
    'https://anitube.in.ua',
  );
  return client;
}

Future<String> readPreviousScript() async {
  final result = await Process.run(
    'git',
    ['show', '$previousScriptRevision:anime/anitube_in_ua/main.capyscript'],
    workingDirectory: Directory.current.parent.path,
  );
  if (result.exitCode != 0) {
    throw StateError('cannot read the previous script: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<AnimeConcreteView> fetchConcrete(AnimeApiClient client, String slug) {
  return Future.delayed(
    requestSpacing,
    () => client.getConcrete(uid: slug, data: {'cover': '', 'title': slug}),
  );
}

Future<AnimeConcreteView> fetchPreviousBaseline(
  AnimeApiClient client,
  String slug,
) async {
  var concrete = await fetchConcrete(client, slug);
  for (var retry = 0; retry < 2 && uidSet(concrete).isEmpty; retry++) {
    await Future.delayed(rateLimitCooldown);
    concrete = await fetchConcrete(client, slug);
  }
  return concrete;
}

void main() {
  late RealBrowserInterceptorController currentBrowser;
  late PlaylistReadyBrowser previousBrowser;
  late AnimeApiClient currentClient;
  late AnimeApiClient previousClient;
  final currentConcretes = <String, AnimeConcreteView>{};
  final previousConcretes = <String, AnimeConcreteView>{};

  setUpAll(() async {
    currentBrowser = RealBrowserInterceptorController(
      headless: true,
      waitUntil: Until.load,
    );
    previousBrowser = PlaylistReadyBrowser();
    currentClient = await connectAnitube(
      currentBrowser,
      File(scriptPath('anime/anitube_in_ua/main.capyscript'))
          .readAsStringSync(),
    );
    previousClient = await connectAnitube(
      previousBrowser,
      await readPreviousScript(),
    );
    for (final slug in checkedTitles) {
      currentConcretes[slug] = await fetchConcrete(currentClient, slug);
      previousConcretes[slug] = await fetchPreviousBaseline(
        previousClient,
        slug,
      );
    }
  });

  tearDownAll(() async {
    await currentBrowser.dispose();
    await previousBrowser.dispose();
  });

  for (final slug in checkedTitles) {
    group(slug, () {
      test('lists episode groups', () {
        expect(currentConcretes[slug]!.groups, isNotEmpty);
        for (final group in currentConcretes[slug]!.groups) {
          expect(group.elements, isNotEmpty);
        }
      });

      test('every group plays from a single embed host', () {
        for (final group in currentConcretes[slug]!.groups) {
          final hosts = group.elements.map((video) => embedHostOf(video.src));
          expect(hosts.toSet(), hasLength(1), reason: group.title);
        }
      });

      test('groups are titled by dub and player', () {
        for (final group in currentConcretes[slug]!.groups) {
          expect(group.title, contains(' · '));
          expect(group.title.toUpperCase(), isNot(contains('ПЛЕЄР')));
        }
      });

      test('episode titles carry no type or player prefix', () {
        for (final group in currentConcretes[slug]!.groups) {
          for (final video in group.elements) {
            expect(video.title, isNotEmpty);
            final upperTitle = video.title.toUpperCase();
            for (final prefixWord in playerPrefixWords) {
              expect(upperTitle, isNot(contains(prefixWord)));
            }
          }
        }
      });

      test('episodes are numbered and sorted ascending', () {
        final videos = allVideos(currentConcretes[slug]!).toList();
        final numbered = videos.where((video) => video.number != null);
        expect(numbered.length, greaterThan(videos.length * 0.9));
        for (final group in currentConcretes[slug]!.groups) {
          var previousNumber = -1.0;
          var seenUnnumbered = false;
          for (final video in group.elements) {
            final number = video.number;
            if (number == null) {
              seenUnnumbered = true;
              continue;
            }
            expect(seenUnnumbered, isFalse, reason: group.title);
            expect(number, greaterThanOrEqualTo(previousNumber));
            previousNumber = number;
          }
        }
      });

      test('a group never repeats a src', () {
        for (final group in currentConcretes[slug]!.groups) {
          final sources = group.elements.map((video) => video.src).toList();
          expect(sources.toSet(), hasLength(sources.length));
        }
      });

      test('natively resolved hosts come first', () {
        var seenOtherHost = false;
        for (final group in currentConcretes[slug]!.groups) {
          final native = isNativeHost(embedHostOf(group.elements.first.src));
          if (native) {
            expect(seenOtherHost, isFalse, reason: group.title);
          } else {
            seenOtherHost = true;
          }
        }
      });

      test('uid stays the src', () {
        for (final video in allVideos(currentConcretes[slug]!)) {
          expect(video.uid, video.src);
        }
      });

      test('uids match the previous script', () {
        final previousUids = uidSet(previousConcretes[slug]!);
        expect(previousUids, isNotEmpty);
        expect(uidSet(currentConcretes[slug]!), equals(previousUids));
      });

      test('fills title metadata', () {
        final concrete = currentConcretes[slug]!;
        expect(concrete.tags, isNotEmpty);
        expect(concrete.year, greaterThan(2000));
        expect(concrete.alternativeTitles, isNotEmpty);
        expect(concrete.url, 'https://anitube.in.ua/$slug');
        expect(concrete.description, isNotEmpty);
        expect(concrete.status, isNot(AnimeStatus.UNDEFINED));
      });
    });
  }

  test('a finished title is released', () {
    expect(currentConcretes[longFinishedTitle]!.status, AnimeStatus.RELEASED);
  });

  test('a title with several dubs splits them per player', () {
    final groups = currentConcretes[titleWithManyDubs]!.groups;
    final dubNames = groups.map((group) => group.title.split(' · ').first);
    expect(dubNames.toSet().length, greaterThan(2));
    expect(groups.length, greaterThan(dubNames.toSet().length));
  });

  test('a title with subtitles and dub names the type in its groups', () {
    final titles = currentConcretes[titleWithSubtitlesAndDub]!
        .groups
        .map((group) => group.title);
    expect(titles.any((title) => title.contains('Субтитри')), isTrue);
    expect(titles.any((title) => title.contains('Озвучення')), isTrue);
  });

  test('repeated getConcrete right after the load event keeps the episodes',
      () async {
    final expectedUids = uidSet(currentConcretes[titleWithManyDubs]!);
    for (var attempt = 0; attempt < 3; attempt++) {
      final concrete = await fetchConcrete(currentClient, titleWithManyDubs);
      expect(concrete.groups, isNotEmpty);
      expect(uidSet(concrete), equals(expectedUids));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
