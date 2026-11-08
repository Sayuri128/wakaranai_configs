import 'dart:io';

import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video_source.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import '../helpers/scraper_helpers.dart';

const String ashdiEpisodeWithSubtitles = 'https://ashdi.vip/vod/214530';
const String ashdiEpisode = 'https://ashdi.vip/vod/292121';
const String fenixEpisode =
    'https://fenixplay.xyz/vod/eyJ0Ijoidm9kIiwicyI6ImNob3JuYS1rb255dXNoeW5hIiwiZSI6MSwidiI6InR2IiwibCI6IkZhblZveFVhIn0.XrVs0mwavrxht_zeDeckfpq7qyB_QvL-BaoeKnPvJUg';
const String mp4UploadEpisode =
    'https://www.mp4upload.com/embed-wsxgd9qfom1j.html';

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

Future<String> readStreamStart(String url, Map<String, String> headers) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll(headers)
      ..headers['Range'] = 'bytes=0-511';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    expect(response.statusCode, anyOf(200, 206));
    final firstChunk = await response.stream.first;
    return String.fromCharCodes(firstChunk.take(16));
  } finally {
    client.close();
  }
}

void expectHttpUrl(String url) {
  expect(Uri.parse(url).scheme, anyOf('http', 'https'));
  expect(Uri.parse(url).host, isNotEmpty);
}

void main() {
  late AnimeApiClient client;

  setUpAll(() {
    client = AnimeApiClient(
      code: File(
        scriptPath('anime/anitube_in_ua/main.capyscript'),
      ).readAsStringSync(),
    );
  });

  test('declares getVideoSources', () async {
    expect(await client.supportsVideoSources(), isTrue);
  });

  group('ashdi.vip', () {
    late List<AnimeVideoSource> sources;

    setUpAll(() async {
      sources = await client.getVideoSources(
        iframeVideo(ashdiEpisodeWithSubtitles),
      );
    });

    test('returns the master hls playlist', () {
      expect(sources, isNotEmpty);
      final master = sources.first;
      expectHttpUrl(master.url);
      expect(master.format, 'hls');
      expect(master.quality, 'Auto');
      expect(master.headers['Referer'], 'https://ashdi.vip/');
    });

    test('playlist is reachable with the returned headers', () async {
      final master = sources.first;
      expect(
        await readStreamStart(master.url, master.headers),
        startsWith('#EXTM3U'),
      );
    });

    test('exposes the player subtitles', () {
      final subtitles = sources.first.subtitles;
      expect(subtitles, isNotEmpty);
      expectHttpUrl(subtitles.first.url);
      expect(subtitles.first.format, 'vtt');
      expect(subtitles.first.label, isNotEmpty);
    });

    test('resolves protocol-relative embed urls', () async {
      final relativeSources = await client.getVideoSources(
        iframeVideo(ashdiEpisode.replaceFirst('https:', '')),
      );
      expect(relativeSources, isNotEmpty);
      expect(relativeSources.first.format, 'hls');
      expectHttpUrl(relativeSources.first.url);
    });
  });

  group('fenixplay.xyz', () {
    late List<AnimeVideoSource> sources;

    setUpAll(() async {
      sources = await client.getVideoSources(iframeVideo(fenixEpisode));
    });

    test('returns an authorized master hls playlist', () {
      expect(sources, isNotEmpty);
      final master = sources.first;
      expectHttpUrl(master.url);
      expect(master.format, 'hls');
      expect(master.quality, 'Auto');
      expect(Uri.parse(master.url).queryParameters['token'], isNotEmpty);
    });

    test('every playlist is reachable with the returned headers', () async {
      for (final source in sources) {
        expect(
          await readStreamStart(source.url, source.headers),
          startsWith('#EXTM3U'),
        );
      }
    });

    test('subtitles carry a media token', () {
      for (final subtitle in sources.first.subtitles) {
        expectHttpUrl(subtitle.url);
        expect(Uri.parse(subtitle.url).queryParameters['token'], isNotEmpty);
      }
    });
  });

  group('mp4upload.com', () {
    late List<AnimeVideoSource> sources;

    setUpAll(() async {
      sources = await client.getVideoSources(iframeVideo(mp4UploadEpisode));
    });

    test('returns a direct mp4 with the embed referer', () {
      expect(sources, hasLength(1));
      expectHttpUrl(sources.first.url);
      expect(sources.first.format, 'mp4');
      expect(sources.first.headers['Referer'], 'https://www.mp4upload.com/');
    });

    test('mp4 is reachable with the returned headers', () async {
      final source = sources.first;
      expect(
        await readStreamStart(source.url, source.headers),
        contains('ftyp'),
      );
    });
  });

  group('hosts without plain http streams fall back to the iframe', () {
    const unsupportedEmbeds = <String>[
      'https://moonanime.net/iframe/jdbrouvufyerpeaawmzqug',
      'https://monstro.online/embed/814799/',
      'https://drive.google.com/file/d/1ijMTPplqF-_Hpdf6Mgb3sDKI_AJeitg9/preview',
      'https://http://drive.google.com/file/d/1yXBre2y1aBx8-k7QwZjDFvXy7DQLm6mb/preview',
      'https://example.com/embed/1',
      '',
    ];

    for (final embed in unsupportedEmbeds) {
      test('returns no sources for "$embed"', () async {
        expect(await client.getVideoSources(iframeVideo(embed)), isEmpty);
      });
    }

    test('tortuga never throws', () async {
      final sources = await client.getVideoSources(
        iframeVideo('https://tortuga.tw/vod/131944'),
      );
      for (final source in sources) {
        expectHttpUrl(source.url);
      }
    });
  });
}
