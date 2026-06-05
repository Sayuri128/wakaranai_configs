import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/chapter/pages/pages.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';
import '../helpers/auth_session.dart';
import '../helpers/real_browser_interceptor_controller.dart';
import '../helpers/scraper_helpers.dart';

void main() {
  late Interpreter interpreter;
  late RealBrowserInterceptorController browser;
  late List<MangaGalleryView> galleryPage1;
  late List<MangaGalleryView> galleryPage2;
  late List<MangaGalleryView> galleryWithQuery;
  late MangaConcreteView concrete;
  late Pages pages;

  setUpAll(() async {
    interpreter = Interpreter.fromFile(
      path: scriptPath('manga/manga_lib/main.capyscript'),
    );
    browser = RealBrowserInterceptorController(headless: true);

    final auth = await AuthSession(
      name: 'mangalib',
      loginUrl: 'https://mangalib.me/manga-list',
      baseUrl: 'https://mangalib.me/manga-list',
      requiresLogin: true,
    ).load();

    await browser.launch(
      cookies: auth.cookies,
      localStorage: auth.localStorage,
      initialUrl: auth.localStorage.isNotEmpty
          ? 'https://mangalib.me/manga-list'
          : null,
    );

    await interpreter.runFunction(
      'passWebBrowserInterceptorController',
      arguments: {'controller': browser},
    );

    await setupBrowserWithCookies(
      interpreter,
      browser,
      'https://mangalib.me/manga-list',
    );

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

    galleryWithQuery = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 1, 'query': 'наруто', 'filters': []},
    )) as List)
        .cast<MangaGalleryView>();

    concrete = await interpreter.runFunction(
      'getConcrete',
      arguments: {'uid': galleryPage1.first.uid},
    ) as MangaConcreteView;

    final chapterUid = concrete.groups.first.elements.first.uid;
    final chapterData = concrete.groups.first.elements.first.data;
    pages = await interpreter.runFunction(
      'getPages',
      arguments: {'uid': chapterUid, 'data': chapterData},
    ) as Pages;
  });

  tearDownAll(() async {
    await browser.dispose();
  });

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

    test('chapters have non-empty uid and title', () {
      final chapter = concrete.groups.first.elements.first;
      expect(chapter.uid, isNotEmpty);
      expect(chapter.title, isNotEmpty);
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
    test('returns a Map with expected headers', () async {
      final headers = await interpreter.runFunction(
        'getImageHeaders',
        arguments: {'uid': galleryPage1.first.uid},
      ) as Map;
      expect(headers, isA<Map>());
      expect(headers['user-agent'], isNotEmpty);
      expect(headers['referer'], equals('https://mangalib.me/'));
    });
  });
}
