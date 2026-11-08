import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video_source.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_gallery_view/anime_gallery_view.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/config_info/preferences/extension_preference.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_any/one_of_any.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'anime/jellyfin';

final String serverUrl = environmentValue('JELLYFIN_URL', 'http://localhost:8096');
final String username = environmentValue('JELLYFIN_USERNAME');
final String password = environmentValue('JELLYFIN_PASSWORD');
final String apiKey = environmentValue('JELLYFIN_API_KEY');

const String unavailableReason =
    'Jellyfin is not reachable; set JELLYFIN_URL and JELLYFIN_USERNAME + JELLYFIN_PASSWORD (or JELLYFIN_API_KEY)';

AnimeApiClient clientWith(
  ConfigInfo config,
  Map<String, Object?> preferences, {
  MemoryExtensionStorage? storage,
}) {
  return AnimeApiClient(
    code: readScript(extensionDirectory),
    host: hostFor(
      config,
      preferences: preferences,
      storage: storage ?? MemoryExtensionStorage(),
    ),
  );
}

Map<String, Object?> credentialPreferences([Map<String, Object?> extra = const {}]) {
  if (username.isEmpty && apiKey.isNotEmpty) {
    return {'serverUrl': serverUrl, 'apiKey': apiKey, ...extra};
  }
  return {'serverUrl': serverUrl, 'username': username, 'password': password, ...extra};
}

Future<http.Response> fetch(String url, Map<String, String> headers) {
  return http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 60));
}

List<AnimeVideo> videosOf(Iterable<dynamic> groups) {
  return groups.expand((group) => group.elements as List).cast<AnimeVideo>().toList();
}

void main() {
  late ConfigInfo config;
  var available = false;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    final hasCredentials = username.isNotEmpty || apiKey.isNotEmpty;
    available = hasCredentials && await isReachable('$serverUrl/System/Info/Public');
  });

  group('config', () {
    test('declares a multi-instance api 2 video extension with feeds and settings', () {
      expect(config.apiVersion, 2);
      expect(config.multiInstance, isTrue);
      expect(config.feeds.map((feed) => feed.id), ['all', 'latest', 'resume', 'nextup', 'favorites']);
      final keys = config.preferences.map((preference) => preference.key);
      expect(keys, containsAll(['serverUrl', 'username', 'password', 'apiKey', 'library', 'playback', 'maxBitrate']));
      final secrets = config.preferences.where((preference) => preference.secret).map((preference) => preference.key);
      expect(secrets, containsAll(['password', 'apiKey']));
    });
  });

  group('settings', () {
    test('asks for the server address when it is missing', () async {
      final client = clientWith(config, const {});
      final error = await expectSourceError(
          () => client.getGallery(page: 1), SourceErrorKind.loginRequired);
      expect(error.message, contains('server address'));
    });

    test('reports an unreachable server as down', () async {
      final client = clientWith(config, {'serverUrl': 'http://127.0.0.1:9', 'username': 'x'});
      await expectSourceError(() => client.getGallery(page: 1), SourceErrorKind.sourceDown);
    });

    test('asks for credentials when only the address is set', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final client = clientWith(config, {'serverUrl': serverUrl});
      await expectSourceError(() => client.getGallery(page: 1), SourceErrorKind.loginRequired);
    });
  });

  group('live server', () {
    late AnimeApiClient client;
    late MemoryExtensionStorage storage;
    late List<AnimeGalleryView> catalogue;

    setUpAll(() async {
      if (available == false) {
        return;
      }
      storage = MemoryExtensionStorage();
      client = clientWith(config, credentialPreferences(), storage: storage);
      catalogue = await client.getGallery(page: 1, feed: 'all');
    });

    test('lists movies and shows with reachable covers', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      expect(catalogue, isNotEmpty);
      final movie = catalogue.where((item) => item.subtitle == 'Movie');
      if (movie.isNotEmpty) {
        expect(await probeContentType(movie.first.cover, const {}), startsWith('image/'));
      }
    });

    test('keeps a stable device id and a cached session', () async {
      if (skipUnless(available && username.isNotEmpty, available ? 'set JELLYFIN_USERNAME and JELLYFIN_PASSWORD to test password sign-in' : unavailableReason)) {
        return;
      }
      expect(storage.values['deviceId'], startsWith('"wakaranai'));
      final sessionKeys = storage.values.keys.where((key) => key.startsWith('session|'));
      expect(sessionKeys, hasLength(1));
    });

    test('signs in again when the cached token is revoked', () async {
      if (skipUnless(available && username.isNotEmpty, available ? 'set JELLYFIN_USERNAME and JELLYFIN_PASSWORD to test password sign-in' : unavailableReason)) {
        return;
      }
      final staleStorage = MemoryExtensionStorage();
      final stale = clientWith(config, credentialPreferences(), storage: staleStorage);
      await stale.getGallery(page: 1, feed: 'all');
      final sessionKey = staleStorage.values.keys.firstWhere((key) => key.startsWith('session|'));
      final cached = staleStorage.values[sessionKey]!;
      staleStorage.values[sessionKey] = cached.replaceFirst(RegExp(r'"token":"[^"]+"'), '"token":"revoked"');
      expect(await stale.getGallery(page: 1, feed: 'all'), isNotEmpty);
      expect(staleStorage.values[sessionKey], isNot(contains('revoked')));
    });

    test('pages do not overlap', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final sized = clientWith(config, credentialPreferences({ExtensionPreference.pageSizeKey: 20}));
      final first = await sized.getGallery(page: 1, feed: 'all');
      final second = await sized.getGallery(page: 2, feed: 'all');
      final firstUids = first.map((item) => item.uid).toSet();
      expect(second.map((item) => item.uid).toSet().intersection(firstUids), isEmpty);
    });

    test('every feed loads', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      for (final feed in ['latest', 'resume', 'nextup', 'favorites']) {
        final items = await client.getGallery(page: 1, feed: feed);
        expect(items.map((item) => item.uid).toSet(), hasLength(items.length), reason: feed);
      }
    });

    test('search finds a title by name', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final wanted = catalogue.first;
      final results = await client.getGallery(page: 1, query: wanted.title);
      expect(results.map((item) => item.uid), contains(wanted.uid));
    });

    test('the type filter keeps only movies', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final typeFilter = config.filters.firstWhere((filter) => filter.param == 'itemType');
      final movies = await client.getGallery(
        page: 1,
        feed: 'all',
        filters: [FilterDataOneOfAny(selected: 'Movie', filter: typeFilter)],
      );
      for (final item in movies) {
        expect(item.subtitle, 'Movie');
      }
    });

    test('an unknown library is reported', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final filtered = clientWith(config, credentialPreferences({'library': 'no such library'}));
      await expectLater(filtered.getGallery(page: 1), throwsA(anything));
    });

    test('opens a show and streams an episode with subtitles and labelled audio', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final shows = catalogue.where((item) => item.subtitle == 'Series');
      if (skipUnless(shows.isNotEmpty, 'the server has no shows')) {
        return;
      }
      final concrete = await client.getConcrete(uid: shows.first.uid, data: shows.first.data);
      expect(concrete.groups, isNotEmpty);
      final episodes = videosOf(concrete.groups);
      expect(episodes, isNotEmpty);
      expect(episodes.first.number, isNotNull);
      var sawSubtitles = false;
      for (final episode in episodes) {
        final sources = await client.getVideoSources(episode);
        expect(sources, isNotEmpty);
        final hls = sources.where((source) => source.format == 'hls').toList();
        expect(hls, isNotEmpty);
        final master = await fetch(hls.first.url, hls.first.headers);
        expect(master.statusCode, 200);
        expect(master.body, startsWith('#EXTM3U'));
        final labels = hls.map((source) => source.audioLabel).toSet();
        expect(labels, hasLength(hls.length));
        for (final subtitle in sources.first.subtitles) {
          sawSubtitles = true;
          final track = await fetch(subtitle.url, subtitle.headers);
          expect(track.statusCode, 200);
          expect(track.body, startsWith('WEBVTT'));
        }
      }
      expect(sawSubtitles, isTrue, reason: 'no episode has a text subtitle track');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('opens a movie and plays the original file', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final movies = catalogue.where((item) => item.subtitle == 'Movie');
      if (skipUnless(movies.isNotEmpty, 'the server has no movies')) {
        return;
      }
      final concrete = await client.getConcrete(uid: movies.first.uid, data: movies.first.data);
      final videos = videosOf(concrete.groups);
      expect(videos, hasLength(1));
      final sources = await client.getVideoSources(videos.first);
      final original = sources.where((source) => source.quality == 'Original').toList();
      if (original.isNotEmpty) {
        expect(original.first.preferForDownload, isTrue);
        final request = http.Request('GET', Uri.parse(original.first.url))
          ..headers['Range'] = 'bytes=0-1023';
        final response = await request.send().timeout(const Duration(seconds: 30));
        expect(response.statusCode, anyOf(200, 206));
        expect(response.headers['content-type'], startsWith('video/'));
        await response.stream.drain<void>();
      }
    });

    test('converted-only playback leaves out the original file', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final converted = clientWith(config, credentialPreferences({'playback': 'hls', 'maxBitrate': '4000000'}));
      final concrete = await converted.getConcrete(uid: catalogue.first.uid, data: catalogue.first.data);
      final sources = await converted.getVideoSources(videosOf(concrete.groups).first);
      expect(sources, isNotEmpty);
      for (final AnimeVideoSource source in sources) {
        expect(source.format, 'hls');
        expect(source.quality, '4 Mbps');
        expect(source.url, contains('MaxStreamingBitrate=4000000'));
      }
    });

    test('an unknown item is reported as not found', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      await expectSourceError(
          () => client.getConcrete(uid: '0123456789abcdef0123456789abcdef', data: const {}),
          SourceErrorKind.notFound);
    });

    test('a wrong password asks the user to sign in again', () async {
      if (skipUnless(available && username.isNotEmpty, available ? 'set JELLYFIN_USERNAME and JELLYFIN_PASSWORD to test password sign-in' : unavailableReason)) {
        return;
      }
      final wrong = clientWith(config, {'serverUrl': serverUrl, 'username': username, 'password': 'not-the-password'});
      await expectSourceError(() => wrong.getGallery(page: 1), SourceErrorKind.loginRequired);
    });

    test('a wrong API key asks the user to sign in again', () async {
      if (skipUnless(available, unavailableReason)) {
        return;
      }
      final wrong = clientWith(config, {'serverUrl': serverUrl, 'apiKey': 'not-a-key'});
      await expectSourceError(() => wrong.getGallery(page: 1), SourceErrorKind.loginRequired);
    });

    test('an API key browses as the chosen user', () async {
      if (skipUnless(available && apiKey.isNotEmpty, 'set JELLYFIN_API_KEY to test API key access')) {
        return;
      }
      final keyed = clientWith(config, {'serverUrl': serverUrl, 'apiKey': apiKey, 'username': username});
      final items = await keyed.getGallery(page: 1, feed: 'all');
      expect(items.map((item) => item.uid).toSet(), catalogue.map((item) => item.uid).toSet());
    });
  });
}
