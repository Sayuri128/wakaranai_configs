import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/chapter/pages/pages.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';
import '../helpers/auth_session.dart';
import '../helpers/scraper_helpers.dart';

void main() {
  late Interpreter interpreter;
  late List<MangaGalleryView> galleryPage1;
  late List<MangaGalleryView> galleryPage2;
  late MangaConcreteView concrete;
  late Pages pages;

  setUpAll(() async {
    interpreter = Interpreter.fromFile(
      path: scriptPath('manga/nhentai/main.capyscript'),
    );

    final auth = await AuthSession(name: 'nhentai').load();
    final cookieHeader =
        auth.cookies.map((c) => '${c.name}=${c.value}').join('; ');
    await interpreter.runFunction('passProtector', arguments: {
      'body': '',
      'headers': {
        'cookie': cookieHeader,
        'user-agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      'cookies': {for (final c in auth.cookies) c.name: c.value},
    });

    galleryPage1 = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 1, 'query': '', 'filters': []},
    )) as List)
        .cast<MangaGalleryView>();

    galleryPage2 = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 2, 'query': '', 'filters': []},
    )) as List)
        .cast<MangaGalleryView>();

    concrete = await interpreter.runFunction(
      'getConcrete',
      arguments: {'uid': galleryPage1.first.uid},
    ) as MangaConcreteView;

    pages = await interpreter.runFunction(
      'getPages',
      arguments: {'uid': concrete.groups.first.elements.first.uid},
    ) as Pages;
  });

  tearDownAll(() {});

  group('getGallery', () {
    test('returns a non-empty list', () {
      expect(galleryPage1, isNotEmpty);
    });

    test('items have non-empty title and valid cover URL', () {
      for (final item in galleryPage1) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https'));
      }
    });

    test('page 2 returns a different set than page 1', () {
      expect(galleryPage2.first.uid, isNot(equals(galleryPage1.first.uid)));
    });
  });

  group('getConcrete', () {
    test('returns a MangaConcreteView', () {
      expect(concrete, isA<MangaConcreteView>());
    });

    test('has non-empty title and valid cover URL', () {
      expect(concrete.title, isNotEmpty);
      expect(concrete.cover, startsWith('https'));
    });

    test('has at least one group with chapters', () {
      expect(concrete.groups, isNotEmpty);
      expect(concrete.groups.first.elements, isNotEmpty);
    });
  });

  group('getPages', () {
    test('returns a non-empty page list', () {
      expect(pages.value, isNotEmpty);
    });

    test('page URLs are valid https URLs', () {
      for (final url in pages.value) {
        expect(url, startsWith('https'));
      }
    });
  });

  group('getImageHeaders', () {
    test('returns a Map', () async {
      final headers = await interpreter.runFunction(
        'getImageHeaders',
        arguments: {'uid': galleryPage1.first.uid},
      );
      expect(headers, isA<Map>());
    });
  });
}
