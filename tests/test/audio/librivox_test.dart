import 'package:capyscript/api_clients/audio_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../helpers/audio_client.dart';
import '../helpers/extension_host_helpers.dart';

const String extensionDirectory = 'audio/librivox';
const String monteCristo = '47';

Future<http.StreamedResponse> openStream(String url) async {
  final request = http.Request('GET', Uri.parse(url))
    ..followRedirects = true
    ..headers['Range'] = 'bytes=0-1023';
  return http.Client().send(request);
}

void main() {
  late ConfigInfo config;
  late AudioApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    config = loadConfig(extensionDirectory);
    client = audioClientFor(extensionDirectory);
    concrete = await client.getConcrete(uid: monteCristo, data: {});
  });

  group('config', () {
    test('is an audio extension for the first app release with audiobooks', () {
      expect(config.type, ConfigInfoType.AUDIO);
      expect(config.apiVersion, 2);
      expect(config.minAppVersion, '1.0.0');
      expect(config.contentKinds, ['audiobook']);
      expect(config.feeds.map((feed) => feed.id), ['latest', 'catalog']);
    });
  });

  group('getGallery', () {
    test('lists both feeds with covers and authors', () async {
      final latest = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'latest', pageSize: 20);
      final catalog = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'catalog', pageSize: 20);
      expect(latest, hasLength(20));
      expect(catalog, hasLength(20));
      expect(catalog.first.uid, monteCristo);
      expect(
        latest.map((item) => item.uid).toList(),
        isNot(catalog.map((item) => item.uid).toList()),
      );
      for (final item in catalog) {
        expect(item.title, isNotEmpty);
        expect(item.data['id'], item.uid);
      }
      expect(catalog.first.cover, startsWith('https://archive.org/'));
      expect(catalog.first.subtitle, 'Alexandre Dumas');
    });

    test('pages with the chosen page size', () async {
      final first = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'catalog', pageSize: 20);
      final second = await client.getGallery(
          page: 2, query: '', filters: [], feed: 'catalog', pageSize: 20);
      expect(second, hasLength(20));
      expect(
        second.map((item) => item.uid).toSet().intersection(
              first.map((item) => item.uid).toSet(),
            ),
        isEmpty,
      );
    });

    test('searches titles by prefix and falls back to authors', () async {
      final byTitle = await client.getGallery(
          page: 1, query: 'Count of Monte', filters: [], feed: '', pageSize: 0);
      final byAuthor = await client.getGallery(
          page: 1, query: 'Doyle', filters: [], feed: '', pageSize: 0);
      final nothing = await client.getGallery(
          page: 1, query: 'zzqqxxnothing', filters: [], feed: '', pageSize: 0);
      expect(byTitle.map((item) => item.uid), contains(monteCristo));
      expect(byAuthor, isNotEmpty);
      expect(byAuthor.first.subtitle, contains('Doyle'));
      expect(nothing, isEmpty);
    });
  });

  group('getConcrete', () {
    test('has details and metadata', () {
      expect(concrete.uid, monteCristo);
      expect(concrete.title, 'Count of Monte Cristo');
      expect(concrete.cover, startsWith('https://archive.org/'));
      expect(concrete.description, contains('Dumas'));
      expect(concrete.description, isNot(contains('<i>')));
      expect(concrete.authors, ['Alexandre Dumas']);
      expect(concrete.tags, contains('English'));
      expect(concrete.status, MangaStatus.RELEASED);
      expect(concrete.url, startsWith('https://librivox.org/'));
    });

    test('lists every section as a track', () {
      final tracks = concrete.groups.single.elements;
      expect(tracks, hasLength(greaterThan(100)));
      expect(tracks.first.uid, '$monteCristo/121010');
      expect(tracks.first.title, contains('Marseilles'));
      expect(tracks.first.data['url'], startsWith('https://archive.org/download/'));
      expect(tracks.first.data['playtime'], '1179');
      expect(tracks.map((track) => track.uid).toSet(), hasLength(tracks.length));
    });

    test('an unknown audiobook is a notFound source error', () async {
      await expectSourceError(
        () => client.getConcrete(uid: '999999999', data: {}),
        SourceErrorKind.notFound,
      );
    });
  });

  group('getAudioSources', () {
    test('offers the 64 kbps file first with its duration', () async {
      final track = concrete.groups.single.elements.first;
      final sources = await client.getAudioSources(uid: track.uid, data: track.data);
      expect(sources, hasLength(2));
      expect(sources.first.quality, '64 kbps');
      expect(sources.first.format, 'mp3');
      expect(sources.first.duration, 1179);
      expect(sources.first.url, endsWith('_64kb.mp3'));
      expect(sources.last.quality, '128 kbps');
      expect(sources.last.url, isNot(contains('_64kb')));
    });

    test('the quality preference puts 128 kbps first', () async {
      final preferred = audioClientFor(
        extensionDirectory,
        preferences: {'quality': '128'},
      );
      final track = concrete.groups.single.elements.first;
      final sources = await preferred.getAudioSources(uid: track.uid, data: track.data);
      expect(sources.first.quality, '128 kbps');
    });

    test('both files stream as mp3', () async {
      final track = concrete.groups.single.elements.first;
      final sources = await client.getAudioSources(uid: track.uid, data: track.data);
      for (final source in sources) {
        final response = await openStream(source.url);
        expect(response.statusCode, anyOf(200, 206), reason: source.url);
        expect(response.headers['content-type'], startsWith('audio/mpeg'));
        await response.stream.listen((_) {}).cancel();
      }
    });
  });
}
