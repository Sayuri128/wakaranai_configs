import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_gallery_view/anime_gallery_view.dart';
import 'package:test/test.dart';
import '../helpers/auth_session.dart';
import '../helpers/real_browser_interceptor_controller.dart';
import '../helpers/scraper_helpers.dart';

void main() {
  late Interpreter interpreter;
  late RealBrowserInterceptorController browser;
  late List<AnimeGalleryView> galleryPage1;
  late List<AnimeGalleryView> galleryPage2;
  late List<AnimeGalleryView> galleryWithQuery;
  late AnimeConcreteView concrete;

  setUpAll(() async {
    interpreter = Interpreter.fromFile(
      path: scriptPath('anime/anitube_in_ua/main.capyscript'),
    );
    browser = RealBrowserInterceptorController(headless: true);

    final auth = await AuthSession(
      name: 'anitube_in_ua',
      requiresLogin: false,
    ).load();

    await browser.launch(
      cookies: auth.cookies,
      localStorage: auth.localStorage,
    );

    await interpreter.runFunction(
      'passWebBrowserInterceptorController',
      arguments: {'controller': browser},
    );

    await setupBrowserWithCookies(
      interpreter,
      browser,
      'https://anitube.in.ua',
    );

    galleryPage1 = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 1, 'query': '', 'filters': []},
    )) as List)
        .cast<AnimeGalleryView>();

    galleryPage2 = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 2, 'query': '', 'filters': []},
    )) as List)
        .cast<AnimeGalleryView>();

    galleryWithQuery = ((await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 1, 'query': 'наруто', 'filters': []},
    )) as List)
        .cast<AnimeGalleryView>();

    final firstItem = galleryPage1.first;
    concrete = await interpreter.runFunction(
      'getConcrete',
      arguments: {
        'uid': firstItem.uid,
        'data': {'cover': firstItem.cover, 'title': firstItem.title},
      },
    ) as AnimeConcreteView;
  });

  tearDownAll(() async {
    await browser.dispose();
  });

  group('getGallery (no query — plain HTTP path)', () {
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

  group('getGallery (with query — browser path)', () {
    test('search returns results', () {
      expect(galleryWithQuery, isNotEmpty);
    });
  });

  group('getConcrete', () {
    test('returns AnimeConcreteView', () {
      expect(concrete, isA<AnimeConcreteView>());
    });

    test('has non-empty title and uid', () {
      expect(concrete.title, isNotEmpty);
      expect(concrete.uid, isNotEmpty);
    });

    test('groups is a list', () {
      expect(concrete.groups, isA<List>());
    });
  });

  group('getImageHeaders', () {
    test('returns a map', () async {
      final headers = await interpreter.runFunction(
        'getImageHeaders',
        arguments: {'uid': galleryPage1.first.uid},
      );
      expect(headers, isA<Map>());
    });
  });
}
