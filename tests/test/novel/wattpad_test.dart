import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/wattpad';
const String dragonPrincess = '26327373';
const String paidStory = '10922127';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    client = novelClientFor(extensionDirectory);
  });

  test('hot and new feeds page forward', () async {
    for (final feed in ['hot', 'new']) {
      final first = await client.getGallery(page: 1, feed: feed);
      final second = await client.getGallery(page: 2, feed: feed);
      expect(first, isNotEmpty, reason: feed);
      expect(first.every((item) => RegExp(r'^\d+$').hasMatch(item.uid)), isTrue);
      expect(second.first.uid, isNot(first.first.uid));
    }
  });

  test('tag filter and search', () async {
    final fantasy = await client.getGallery(
      page: 1,
      feed: 'hot',
      filters: [
        FilterDataOneOfMultiple(
          selected: 'fantasy',
          filter: config.filters.single as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(fantasy, isNotEmpty);
    final results = await client.getGallery(page: 1, query: 'The Dragon and the Princess');
    expect(results.map((item) => item.uid), contains(dragonPrincess));
  });

  test('a story lists its parts newest first and reads one', () async {
    final concrete = await client.getConcrete(uid: dragonPrincess, data: {});
    expect(concrete.title, 'The Dragon and the Princess');
    expect(concrete.authors, ['Dragon__Wolf']);
    expect(concrete.status, MangaStatus.RELEASED);
    expect(concrete.tags, contains('dragon'));
    final parts = concrete.groups.single.elements;
    expect(parts.length, greaterThanOrEqualTo(30));
    expect(parts.last.title, 'Declaration');
    final content = await client.getChapterText(uid: parts.last.uid, data: {});
    expect(content.html, startsWith('<p'));
    expect(content.html, contains('Declaration'));
  });

  test('paid parts report that they need the Paid Stories program', () async {
    final concrete = await client.getConcrete(uid: paidStory, data: {});
    expect(concrete.tags, contains('Paid Story'));
    await expectLater(
      client.getChapterText(uid: concrete.groups.single.elements.first.uid, data: {}),
      throwsA(isA<SourceError>().having((error) => error.kind, 'kind', SourceErrorKind.loginRequired)),
    );
  });
}
