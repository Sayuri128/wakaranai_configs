import 'dart:io';

import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video_source.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:http/http.dart' as http;
import 'package:puppeteer/puppeteer.dart' show Until;
import 'package:test/test.dart';
import '../helpers/real_browser_interceptor_controller.dart';
import '../helpers/scraper_helpers.dart';

const String moonanimeEpisodeLightMusicClub =
    'https://moonanime.net/iframe/mherrsryeeebxvogkuzugmkrr';
const String moonanimeEpisodeFireflyWedding =
    'https://moonanime.net/iframe/wjpwd2zoh7mr';
const String titleWithMoonanimeEpisodes =
    '4462-klub-legkoyi-muziki-2-sezon.html';
const Duration appVideoSourcesTimeout = Duration(seconds: 20);
const int transportStreamSyncByte = 0x47;

AnimeVideo iframeVideo(String src) {
  return AnimeVideo(
    type: AnimeVideoType.IFRAME,
    uid: src,
    src: src,
    title: src,
    timestamp: null,
    data: {'title': src, 'src': src},
  );
}

Future<http.Response> fetchWithHeaders(
  String url,
  Map<String, String> headers,
) async {
  return http
      .get(Uri.parse(url), headers: headers)
      .timeout(const Duration(seconds: 30));
}

String firstMediaUri(String playlist, String playlistUrl) {
  for (final line in playlist.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      return Uri.parse(playlistUrl).resolve(trimmed).toString();
    }
  }
  return '';
}

Future<List<int>> readFirstSegmentBytes(AnimeVideoSource source) async {
  final master = await fetchWithHeaders(source.url, source.headers);
  expect(master.statusCode, 200);
  expect(master.body, startsWith('#EXTM3U'));
  final variantUrl = firstMediaUri(master.body, source.url);
  expect(variantUrl, isNotEmpty);
  final variant = await fetchWithHeaders(variantUrl, source.headers);
  expect(variant.statusCode, 200);
  expect(variant.body, startsWith('#EXTM3U'));
  final segmentUrl = firstMediaUri(variant.body, variantUrl);
  expect(segmentUrl, isNotEmpty);
  final segment = await fetchWithHeaders(segmentUrl, {
    ...source.headers,
    'Range': 'bytes=0-187',
  });
  expect(segment.statusCode, anyOf(200, 206));
  return segment.bodyBytes;
}

void expectHttpUrl(String url) {
  expect(Uri.parse(url).scheme, anyOf('http', 'https'));
  expect(Uri.parse(url).host, isNotEmpty);
}

AnimeVideo? firstMoonanimeVideo(AnimeConcreteView concrete) {
  for (final group in concrete.groups) {
    for (final video in group.elements) {
      if (video.src.contains('moonanime.')) {
        return video;
      }
    }
  }
  return null;
}

int countVideos(AnimeConcreteView concrete) {
  return concrete.groups.fold<int>(
    0,
    (total, group) => total + group.elements.length,
  );
}

Future<AnimeApiClient> connectAnitube(
  RealBrowserInterceptorController browser,
) async {
  final client = AnimeApiClient(
    code: File(
      scriptPath('anime/anitube_in_ua/main.capyscript'),
    ).readAsStringSync(),
  );
  await browser.launch();
  await client.passWebBrowserInterceptorController(controller: browser);
  await setupBrowserWithCookies(
    client.interpreter,
    browser,
    'https://anitube.in.ua',
  );
  return client;
}

void main() {
  late AnimeApiClient client;
  late RealBrowserInterceptorController browser;

  setUpAll(() async {
    browser = RealBrowserInterceptorController(
      headless: true,
      waitUntil: Until.load,
    );
    client = await connectAnitube(browser);
  });

  tearDownAll(() async {
    await browser.dispose();
  });

  for (final embed in [
    moonanimeEpisodeLightMusicClub,
    moonanimeEpisodeFireflyWedding,
  ]) {
    group('moonanime $embed', () {
      late List<AnimeVideoSource> sources;
      late Duration elapsed;

      setUpAll(() async {
        final stopwatch = Stopwatch()..start();
        sources = await client.getVideoSources(iframeVideo(embed));
        elapsed = stopwatch.elapsed;
      });

      test('resolves within the app timeout', () {
        expect(elapsed, lessThan(appVideoSourcesTimeout));
      });

      test('returns a signed hls master playlist', () {
        expect(sources, isNotEmpty);
        final master = sources.first;
        expectHttpUrl(master.url);
        expect(master.format, 'hls');
        expect(master.quality, 'Auto');
        expect(Uri.parse(master.url).queryParameters['sig'], isNotEmpty);
      });

      test('carries the headers the media cdn checks', () {
        final headers = sources.first.headers;
        expect(headers['Accept'], isNotEmpty);
        expect(headers['Accept-Language'], isNotEmpty);
      });

      test(
        'playlists and segments are reachable with the returned headers',
        () async {
          final segmentBytes = await readFirstSegmentBytes(sources.first);
          expect(segmentBytes, isNotEmpty);
          expect(segmentBytes.first, transportStreamSyncByte);
        },
      );

      test('subtitles are direct links', () {
        for (final subtitle in sources.first.subtitles) {
          expectHttpUrl(subtitle.url);
          expect(subtitle.format, anyOf('vtt', 'srt'));
        }
      });
    });
  }

  group('anitube flow after resolving a moonanime episode', () {
    late RealBrowserInterceptorController flowBrowser;
    late AnimeConcreteView concreteBefore;
    late List<AnimeVideoSource> sources;
    late AnimeConcreteView concreteAfter;

    setUpAll(() async {
      flowBrowser = RealBrowserInterceptorController(headless: true);
      final flowClient = await connectAnitube(flowBrowser);
      final data = {'cover': '', 'title': titleWithMoonanimeEpisodes};
      concreteBefore = await flowClient.getConcrete(
        uid: titleWithMoonanimeEpisodes,
        data: data,
      );
      final moonVideo = firstMoonanimeVideo(concreteBefore);
      sources = moonVideo == null
          ? []
          : await flowClient.getVideoSources(moonVideo);
      concreteAfter = await flowClient.getConcrete(
        uid: titleWithMoonanimeEpisodes,
        data: data,
      );
    });

    tearDownAll(() async {
      await flowBrowser.dispose();
    });

    test('the title lists moonanime episodes', () {
      expect(firstMoonanimeVideo(concreteBefore), isNotNull);
    });

    test('the listed moonanime episode resolves', () {
      expect(sources, isNotEmpty);
      expectHttpUrl(sources.first.url);
    });

    test('getConcrete still reads the episode list afterwards', () {
      expect(concreteAfter.groups, isNotEmpty);
      expect(countVideos(concreteAfter), countVideos(concreteBefore));
      expect(firstMoonanimeVideo(concreteAfter), isNotNull);
    });
  });

  group('failures fall back to the iframe', () {
    test('an unknown moonanime embed returns no sources', () async {
      final sources = await client.getVideoSources(
        iframeVideo('https://moonanime.net/iframe/doesnotexist000000'),
      );
      expect(sources, isEmpty);
    });
  });
}
