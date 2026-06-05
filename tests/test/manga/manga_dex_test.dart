import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/chapter/pages/pages.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';
import '../helpers/scraper_helpers.dart';

void main() {
  late Interpreter interpreter;
  late List<MangaGalleryView> galleryPage1;
  late List<MangaGalleryView> galleryPage2;
  late List<MangaGalleryView> galleryWithQuery;
  late MangaConcreteView concrete;
  late Pages pages;

  setUpAll(() async {
    interpreter = Interpreter.fromFile(
      path: scriptPath('manga/manga_dex/main.capyscript'),
    );

    galleryPage1 = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 0, 'query': '', 'filters': []},
    )) as List)
        .cast<MangaGalleryView>();

    galleryPage2 = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 1, 'query': '', 'filters': []},
    )) as List)
        .cast<MangaGalleryView>();

    galleryWithQuery = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 0, 'query': 'one piece', 'filters': []},
    )) as List)
        .cast<MangaGalleryView>();

    // Use a gallery item (fan-translated manga tend to have free chapters)
    // Iterate to find one that has at least one English chapter
    for (final item in galleryPage1) {
      final c = await interpreter.runFunction(
        'getConcrete',
        arguments: {'uid': item.uid},
      ) as MangaConcreteView;
      if (c.groups.isNotEmpty && c.groups.first.elements.isNotEmpty) {
        concrete = c;
        break;
      }
    }

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

    test('query search returns results', () {
      expect(galleryWithQuery, isNotEmpty);
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
