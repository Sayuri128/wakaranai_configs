import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_gallery_view/anime_gallery_view.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String extensionDirectory = 'anime/animevost';
const String narutoUid = '7';

class NullLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

Future<bool> fetchesVideo(String url) async {
  final response = await http.get(
    Uri.parse(url),
    headers: {'Range': 'bytes=0-1023'},
  ).timeout(const Duration(seconds: 30));
  final isOk = response.statusCode == 200 || response.statusCode == 206;
  return isOk && (response.headers['content-type'] ?? '').contains('video/mp4');
}

void main() {
  Logger.level = Level.off;
  Logger.defaultOutput = () => NullLogOutput();

  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig(extensionDirectory);
    client = AnimeApiClient(
      code: readScript(extensionDirectory),
      host: hostFor(config),
    );
  });

  FilterDataOneOfMultiple filter(String param, String value) {
    final definition = config.filters.firstWhere((f) => f.param == param)
        as GalleryFilterOneOfMultiple;
    return FilterDataOneOfMultiple(selected: value, filter: definition);
  }

  Future<List<AnimeGalleryView>> gallery({
    int page = 1,
    String query = '',
    List<FilterDataOneOfMultiple> filters = const [],
    String feed = 'latest',
  }) {
    return client.getGallery(
      page: page,
      query: query,
      filters: filters,
      feed: feed,
      pageSize: 0,
    );
  }

  group('getGallery', () {
    late List<AnimeGalleryView> latest;

    setUpAll(() async {
      latest = await gallery();
    });

    test('lists the latest updates from the api', () {
      expect(latest, isNotEmpty);
      expect(latest.length, lessThanOrEqualTo(20));
      for (final item in latest) {
        expect(int.tryParse(item.uid), isNotNull, reason: item.uid);
        expect(item.title, isNotEmpty);
        expect(item.title, isNot(contains(' / ')));
        expect(item.title, isNot(contains('[')));
        expect(item.cover, startsWith('https://'));
        expect(item.data['title'], item.title);
      }
    });

    test('the second page continues without repeats', () async {
      final second = await gallery(page: 2);
      expect(second, isNotEmpty);
      final firstUids = latest.map((item) => item.uid).toSet();
      expect(second.where((item) => firstUids.contains(item.uid)), isEmpty);
    });

    test('the ongoing feed reads the site listing', () async {
      final ongoing = await gallery(feed: 'ongoing');
      expect(ongoing, isNotEmpty);
      expect(ongoing.length, lessThanOrEqualTo(10));
      final secondPage = await gallery(feed: 'ongoing', page: 2);
      expect(secondPage, isNotEmpty);
      expect(secondPage.first.uid, isNot(ongoing.first.uid));
    });

    test('a genre filter lists titles of that genre', () async {
      final comedies = await gallery(filters: [filter('genre', 'komediya')]);
      expect(comedies, isNotEmpty);
      final concrete = await client.getConcrete(
        uid: comedies.first.uid,
        data: comedies.first.data,
      );
      expect(concrete.tags, contains('Комедия'));
    });

    test('a year filter lists titles from that year', () async {
      final titles = await gallery(filters: [filter('year', '2010')]);
      expect(titles, isNotEmpty);
      final concrete = await client.getConcrete(
        uid: titles.first.uid,
        data: titles.first.data,
      );
      expect(concrete.year, 2010);
    });

    test('a page past the end of a category is empty', () async {
      final titles = await gallery(
        filters: [filter('year', '1971')],
        page: 50,
      );
      expect(titles, isEmpty);
    });

    test('search finds titles by name and has a single page', () async {
      final results = await gallery(query: 'Наруто');
      expect(results.map((item) => item.uid), contains(narutoUid));
      expect(await gallery(query: 'Наруто', page: 2), isEmpty);
    });

    test('a search with no matches is empty rather than an error', () async {
      expect(await gallery(query: 'zzqqxxyyww'), isEmpty);
    });
  });

  group('getConcrete', () {
    late AnimeConcreteView naruto;

    setUpAll(() async {
      naruto = await client.getConcrete(uid: narutoUid, data: {});
    });

    test('reads details from the api', () {
      expect(naruto.title, 'Наруто');
      expect(naruto.alternativeTitles, contains('Naruto'));
      expect(naruto.description, isNotEmpty);
      expect(naruto.description, isNot(contains('<br')));
      expect(naruto.cover, startsWith('https://'));
      expect(naruto.tags, isNotEmpty);
      expect(naruto.status, AnimeStatus.RELEASED);
      expect(naruto.url, startsWith('https://animevost.org/'));
    });

    test('lists every episode in one group ordered by number', () {
      expect(naruto.groups, hasLength(1));
      final group = naruto.groups.single;
      expect(group.title, 'AnimeVost');
      expect(group.elements.length, greaterThanOrEqualTo(220));
      final numbers = group.elements
          .map((video) => video.number)
          .whereType<double>()
          .toList();
      expect(numbers.first, 1);
      for (var index = 1; index < numbers.length; index++) {
        expect(numbers[index], greaterThanOrEqualTo(numbers[index - 1]));
      }
      final uids = group.elements.map((video) => video.uid).toSet();
      expect(uids.length, group.elements.length);
      for (final video in group.elements) {
        expect(video.type, AnimeVideoType.DIRECT);
        expect(video.uid, startsWith('$narutoUid/'));
        expect(video.src, startsWith('https://'));
      }
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

    test('offers only the sd file when an old title has no hd one', () async {
      final episode = naruto.groups.single.elements.first;
      final sources = await client.getVideoSources(episode);
      expect(sources.map((source) => source.quality), ['480p']);
      expect(await fetchesVideo(sources.single.url), isTrue);
    });
  });

  group('getVideoSources for a recent title', () {
    test('resolves hd and sd mp4 files labelled with the dub', () async {
      final latest = await gallery();
      final concrete = await client.getConcrete(
        uid: latest.first.uid,
        data: latest.first.data,
      );
      final episode = concrete.groups.single.elements.last;
      final sources = await client.getVideoSources(episode);
      expect(sources.map((source) => source.quality), ['720p', '480p']);
      for (final source in sources) {
        expect(source.format, 'mp4');
        expect(source.audioLabel, 'AnimeVost');
        expect(source.url, startsWith('https://'));
        expect(await fetchesVideo(source.url), isTrue, reason: source.url);
      }
    });
  });
}
