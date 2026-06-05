import 'dart:convert';
import 'package:capyscript/modules/http/http_interceptor_controller.dart';
import 'package:puppeteer/puppeteer.dart';

class RealBrowserInterceptorController implements HttpInterceptorController {
  final bool headless;
  Browser? _browser;
  Page? _page;

  RealBrowserInterceptorController({this.headless = true});

  Page get page => _page!;

  Future<void> launch({
    List<CookieParam> cookies = const [],
    Map<String, String> localStorage = const {},
    String? initialUrl,
  }) async {
    _browser = await puppeteer.launch(
      headless: headless,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-blink-features=AutomationControlled',
      ],
    );
    _page = await _browser!.newPage();
    await _page!.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    if (cookies.isNotEmpty) await _page!.setCookies(cookies);
    if (localStorage.isNotEmpty && initialUrl != null) {
      await _page!.goto(initialUrl, wait: Until.networkIdle);
      final encoded = jsonEncode(localStorage);
      await _page!.evaluate('''() => {
        const ls = $encoded;
        Object.entries(ls).forEach(([k, v]) => localStorage.setItem(k, v));
      }''');
    }
  }

  @override
  Future<HttpInterceptorControllerResponse> loadPage({
    required String url,
    String? method,
    Map<String, String>? headers,
    String? body,
  }) async {
    if (headers != null && headers.isNotEmpty) {
      await _page!.setExtraHTTPHeaders(headers);
    }
    try {
      final response = await _page!.goto(
        url,
        wait: Until.networkIdle,
        timeout: Duration(seconds: 60),
      );
      try {
        await _page!.waitForFunction(
          "document.readyState !== 'loading'",
          timeout: Duration(seconds: 15),
        );
      } catch (_) {}
      final html = await _page!.content;
      final pageCookies = await _page!.cookies();
      final cookieMap = {for (final c in pageCookies) c.name: c.value};
      return HttpInterceptorControllerResponse(
        body: html ?? '',
        statusCode: response.status,
        headers: Map<String, String>.from(response.headers),
        cookies: cookieMap,
        data: {},
      );
    } catch (_) {
      try {
        await _page!.waitForFunction(
          "document.readyState !== 'loading'",
          timeout: Duration(seconds: 10),
        );
      } catch (_) {}
      final html = await _page!.content;
      final pageCookies = await _page!.cookies();
      final cookieMap = {for (final c in pageCookies) c.name: c.value};
      return HttpInterceptorControllerResponse(
        body: html ?? '',
        statusCode: 200,
        headers: {},
        cookies: cookieMap,
        data: {},
      );
    }
  }

  @override
  Future<dynamic> executeJsScript(String code) async {
    try {
      await _page!.waitForFunction(
        "document.readyState === 'complete' || document.readyState === 'interactive'",
        timeout: Duration(seconds: 15),
      );
    } catch (_) {}
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _page!.evaluate('(async function() { $code })()');
        if (result != null) return result;
      } catch (_) {}
      if (attempt == 0) await Future.delayed(Duration(seconds: 1));
    }
    return null;
  }

  Future<List<CookieParam>> extractCookies() async {
    final cookies = await _page!.cookies();
    return cookies
        .map((c) => CookieParam(
              name: c.name,
              value: c.value,
              domain: c.domain,
              path: c.path,
              secure: c.secure,
              httpOnly: c.httpOnly,
            ))
        .toList();
  }

  Future<Map<String, String>> extractLocalStorage() async {
    final result = await _page!.evaluate(
      '() => JSON.stringify(Object.fromEntries(Object.entries(localStorage)))',
    );
    if (result is String) return Map<String, String>.from(jsonDecode(result) as Map);
    return {};
  }

  Future<String> userAgent() async {
    return (await _page!.evaluate('() => navigator.userAgent') as String?) ?? '';
  }

  Future<void> dispose() async {
    await _browser?.close();
    _browser = null;
    _page = null;
  }
}
