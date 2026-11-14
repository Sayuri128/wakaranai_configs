import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_status.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

void main() {
  late ConfigInfo config;
  late AnimeApiClient client;

  setUpAll(() {
    config = loadConfig('anime/unimay');
    client = AnimeApiClient(code: readScript('anime/unimay'), host: hostFor(config));
  });

  test('catalog pages through every release and then ends', () async {
    final first = await client.getGallery(page: 1);
    expect(first, isNotEmpty);
    expect(first.every((item) => item.cover.startsWith('https://img.unimay.media/')), isTrue);
    final second = await client.getGallery(page: 2);
    expect(second.map((item) => item.uid).toSet().intersection(first.map((item) => item.uid).toSet()), isEmpty);
    expect(await client.getGallery(page: 50), isEmpty);
  });

  test('search finds a release by title', () async {
    final results = await client.getGallery(page: 1, query: 'Дандадан');
    expect(results.map((item) => item.uid), contains('dandadan'));
  });

  test('a release lists its episodes with HLS qualities', () async {
    final concrete = await client.getConcrete(uid: 'dandadan', data: {});
    expect(concrete.title, isNotEmpty);
    expect(concrete.alternativeTitles, contains('DAN DA DAN'));
    expect(concrete.status, AnimeStatus.RELEASED);
    expect(concrete.tags, isNotEmpty);
    final episodes = concrete.groups.single.elements;
    expect(episodes, hasLength(12));
    expect(episodes.first.number, 1);
    final sources = await client.getVideoSources(episodes.first);
    expect(sources.map((source) => source.quality), containsAll(['1080p', '720p', '480p']));
    expect(sources.every((source) => source.url.contains('.m3u8')), isTrue);
  });
}
