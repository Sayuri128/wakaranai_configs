import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/http/http_interceptor_controller.dart';
import 'package:test/test.dart';

import '../helpers/scraper_helpers.dart';

const String mobileTitlePage = '''<!doctype html>
<html><head><title>Мій миленький тиран аніме українською онлайн</title></head>
<body><div class="wrap"><div class="full_blc-title">Мій миленький тиран</div>
<a href="/index.php?action=mobiledisable">Повна версія</a></div></body></html>''';

const String desktopTitlePage = '''<!doctype html>
<html><head><title>Мій миленький тиран аніме українською онлайн</title></head>
<body><div id="dle-content"><div class="story">
<div class="story_c"><div class="rcol"><div class="story_c_r">Рік виходу аніме: 2025</div></div>
<div class="story_c_text"><div class="my-text">Опис</div></div></div>
</div></div></body></html>''';

const String mobileSearchPage = '''<!doctype html>
<html><head><title>Пошук на сайті</title></head>
<body><div class="wrap"><a href="/index.php?action=mobiledisable">Повна версія</a></div></body></html>''';

const String desktopSearchPage = '''<!doctype html>
<html><head><title>Пошук на сайті</title></head>
<body><div id="dle-content">
<div class="story"><div class="story_c"><h2><a href="https://anitube.in.ua/4549-my-milenkiy-tiran.html">Мій миленький тиран</a></h2></div>
<div class="story_post"><img data-src="/uploads/cover.jpg"></div></div>
</div></body></html>''';

class MobileFirstInterceptor implements HttpInterceptorController {
  MobileFirstInterceptor({required this.mobileBody, required this.desktopBody});

  final String mobileBody;
  final String desktopBody;
  final List<String> loadedUrls = <String>[];
  bool desktopEnabled = false;

  @override
  Future<HttpInterceptorControllerResponse> loadPage({
    required String url,
    String? method,
    Map<String, String>? headers,
    String? body,
  }) async {
    loadedUrls.add(url);
    if (url.contains('action=mobiledisable')) {
      desktopEnabled = true;
    }
    return HttpInterceptorControllerResponse(
      body: desktopEnabled ? desktopBody : mobileBody,
      data: const {},
      statusCode: 200,
      headers: const {},
      cookies: const {},
    );
  }

  @override
  Future<dynamic> executeJsScript(String code) async => [];
}

Future<Interpreter> anitubeBehind(HttpInterceptorController controller) async {
  final interpreter = Interpreter.fromFile(
    path: scriptPath('anime/anitube_in_ua/main.capyscript'),
  );
  await interpreter.runFunction(
    'passWebBrowserInterceptorController',
    arguments: {'controller': controller},
  );
  return interpreter;
}

void main() {
  test('title details switch a mobile layout to the full version', () async {
    final interceptor = MobileFirstInterceptor(
      mobileBody: mobileTitlePage,
      desktopBody: desktopTitlePage,
    );
    final interpreter = await anitubeBehind(interceptor);

    final concrete = await interpreter.runFunction(
      'getConcrete',
      arguments: {
        'uid': '4549-my-milenkiy-tiran.html',
        'data': {'cover': '', 'title': 'Title'},
      },
    );

    expect(concrete, isNotNull);
    expect(interceptor.loadedUrls, hasLength(3));
    expect(interceptor.loadedUrls[1], contains('action=mobiledisable'));
    expect(interceptor.loadedUrls[2], contains('4549-my-milenkiy-tiran.html'));
  });

  test('search switches a mobile layout to the full version', () async {
    final interceptor = MobileFirstInterceptor(
      mobileBody: mobileSearchPage,
      desktopBody: desktopSearchPage,
    );
    final interpreter = await anitubeBehind(interceptor);

    final gallery = await interpreter.runFunction(
      'getGallery',
      arguments: {'page': 1, 'query': 'тиран', 'filters': [], 'feed': ''},
    ) as List;

    expect(gallery, hasLength(1));
    expect(interceptor.loadedUrls.where((url) => url.contains('mobiledisable')),
        hasLength(1));
  });

  test('desktop pages load once without switching', () async {
    final interceptor = MobileFirstInterceptor(
      mobileBody: desktopTitlePage,
      desktopBody: desktopTitlePage,
    );
    final interpreter = await anitubeBehind(interceptor);

    await interpreter.runFunction(
      'getConcrete',
      arguments: {
        'uid': '4549-my-milenkiy-tiran.html',
        'data': {'cover': '', 'title': 'Title'},
      },
    );

    expect(interceptor.loadedUrls, hasLength(1));
  });

}
