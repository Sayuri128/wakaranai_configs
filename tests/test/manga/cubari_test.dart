import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String onePunchMan = 'gist/OPM';
const String scrappedGistSlug =
    'Z2lzdC9mdW5reWhpcHBvL2RkMTlkNjU3NjhjOGJlMTk3MTFmZTllMjAwNDVkOGY1L3Jhdy9vcG0tc2NyYXBwZWQuanNvbg';

void main() {
  late MangaApiClient client;
  late MangaConcreteView series;

  setUpAll(() async {
    final config = loadConfig('manga/cubari');
    client = MangaApiClient(
      code: readScript('manga/cubari'),
      host: hostFor(config),
    );
    series = await client.getConcrete(uid: onePunchMan, data: {});
  });

  group('getGallery', () {
    test('is empty until a link is pasted', () async {
      expect(await client.getGallery(page: 1), isEmpty);
    });

    test('opens a cubari.moe reader link', () async {
      final items = await client.getGallery(
          page: 1, query: 'https://cubari.moe/read/gist/OPM/');
      expect(items.single.uid, onePunchMan);
      expect(items.single.title, 'One Punch Man');
      expect(items.single.cover, startsWith('https://'));
      expect(await client.getGallery(page: 2, query: 'https://cubari.moe/read/gist/OPM/'), isEmpty);
    });

    test('turns a raw gist link into the cubari slug', () async {
      final items = await client.getGallery(
        page: 1,
        query: 'https://gist.githubusercontent.com/funkyhippo/dd19d65768c8be19711fe9e20045d8f5/raw/opm-scrapped.json',
      );
      expect(items.single.uid, 'gist/$scrappedGistSlug');
    });

    test('rejects text it cannot read', () async {
      await expectLater(
        client.getGallery(page: 1, query: 'one punch man'),
        throwsA(isA<SourceError>()
            .having((error) => error.kind, 'kind', SourceErrorKind.unsupported)),
      );
    });
  });

  group('series', () {
    test('has details', () {
      expect(series.title, 'One Punch Man');
      expect(series.description, contains('Redraws'));
      expect(series.url, 'https://cubari.moe/read/gist/OPM/');
    });

    test('lists chapters newest first under the group name', () {
      final group = series.groups.single;
      expect(group.title, '/r/OnePunchMan');
      expect(group.elements.length, greaterThan(200));
      final numbers = group.elements.map((chapter) => chapter.number!).toList();
      for (var index = 1; index < numbers.length; index++) {
        expect(numbers[index - 1], greaterThan(numbers[index]));
      }
      final first = group.elements.last;
      expect(first.uid, 'gist/OPM/1/0');
      expect(first.title, 'Chapter 1: One Punch');
      expect(first.timestamp, isNotEmpty);
    });

    test('pages come from the chapter group', () async {
      final pages = await client.getPages(uid: 'gist/OPM/1/0', data: {});
      expect(pages.value.length, greaterThan(10));
      expect(pages.value.first, startsWith('https://'));
    });
  });
}
