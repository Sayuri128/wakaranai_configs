import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/rulate';
const String dadAndBaby = '199181';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    client = novelClientFor(extensionDirectory);
  });

  test('feeds list books and page forward', () async {
    for (final feed in config.feeds.map((feed) => feed.id)) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, isNotEmpty, reason: feed);
      expect(items.every((item) => RegExp(r'^\d+$').hasMatch(item.uid)), isTrue);
    }
    final first = await client.getGallery(page: 1, feed: '6');
    final second = await client.getGallery(page: 2, feed: '6');
    expect(second.first.uid, isNot(first.first.uid));
  });

  test('a book gathers every chapter page, oldest last, free chapters only by default', () async {
    final concrete = await client.getConcrete(uid: dadAndBaby, data: {});
    expect(concrete.title, isNotEmpty);
    expect(concrete.alternativeTitles, contains('Dad And Adorable Baby Have A Blast!'));
    expect(concrete.tags, contains('комедия'));
    expect(concrete.cover, startsWith('https://tl.rulate.ru/i/book/'));
    final chapters = concrete.groups.single.elements;
    expect(chapters.length, greaterThan(50));
    expect(chapters.last.uid, '$dadAndBaby/22894246');
    expect(chapters.any((chapter) => chapter.title.endsWith('(платная)')), isFalse);
  });

  test('the paid-chapter setting lists purchasable chapters too', () async {
    final withPaid = novelClientFor(extensionDirectory, preferences: {'showPaid': true});
    final free = await client.getConcrete(uid: dadAndBaby, data: {});
    final all = await withPaid.getConcrete(uid: dadAndBaby, data: {});
    expect(all.groups.single.elements.length, greaterThan(free.groups.single.elements.length));
    expect(all.groups.single.elements.any((chapter) => chapter.title.endsWith('(платная)')), isTrue);
  });

  test('a free chapter reads as paragraphs', () async {
    final content = await client.getChapterText(uid: '$dadAndBaby/22894246', data: {});
    expect(content.html, startsWith('<p>'));
    expect(content.html.length, greaterThan(2000));
  });
}
