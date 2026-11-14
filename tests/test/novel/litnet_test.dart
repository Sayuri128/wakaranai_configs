import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/one_of_multiple/one_of_multiple.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String dragon = 'drakon-s-diagnozom-b614600';
const String paidBook = 'otkaznaya-nevesta-ego-velichestva-b612329';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;

  setUpAll(() {
    silenceInterpreterLogs();
    config = loadConfig('novel/litnet');
    client = novelClientFor('novel/litnet');
  });

  test('the top list pages forward and a genre narrows it', () async {
    final first = await client.getGallery(page: 1);
    final second = await client.getGallery(page: 2);
    expect(first, isNotEmpty);
    expect(first.every((item) => RegExp(r'-b\d+$').hasMatch(item.uid)), isTrue);
    expect(first.first.cover, startsWith('https://'));
    expect(second.map((item) => item.uid), isNot(contains(first.first.uid)));
    final fantasy = await client.getGallery(
      page: 1,
      filters: [
        FilterDataOneOfMultiple(
          selected: 'bytovoe-fentezi',
          filter: config.filters.single as GalleryFilterOneOfMultiple,
        ),
      ],
    );
    expect(fantasy, isNotEmpty);
  });

  test('search finds books', () async {
    final results = await client.getGallery(page: 1, query: 'Дракон с диагнозом');
    expect(results.map((item) => item.uid), contains(dragon));
  });

  test('a book lists its chapters in reading order and a free chapter reads as paragraphs', () async {
    final concrete = await client.getConcrete(uid: dragon, data: {});
    expect(concrete.title, 'Дракон с ... диагнозом');
    expect(concrete.authors, contains('Елена Байм'));
    expect(concrete.tags, contains('Любовное фэнтези'));
    expect(concrete.description, isNot(contains('<br')));
    final chapters = concrete.groups.single.elements;
    expect(chapters.length, greaterThan(100));
    expect(chapters.first.uid, '$dragon/8271172');
    final text = await client.getChapterText(uid: chapters.first.uid, data: {});
    expect(text.html, startsWith('<p'));
    expect(text.html.length, greaterThan(3000));
  });

  test('a purchase-only chapter reports that it needs sign-in', () async {
    final concrete = await client.getConcrete(uid: paidBook, data: {});
    final latest = concrete.groups.single.elements.last;
    await expectSourceError(
      () => client.getChapterText(uid: latest.uid, data: {}),
      SourceErrorKind.loginRequired,
    );
  });
}
