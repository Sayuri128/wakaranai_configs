import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'real_browser_interceptor_controller.dart';

class AuthState {
  final List<CookieParam> cookies;
  final Map<String, String> localStorage;

  const AuthState({required this.cookies, required this.localStorage});
}

class AuthSession {
  final String name;
  final String? loginUrl;
  final String? baseUrl;
  final bool requiresLogin;

  const AuthSession({
    required this.name,
    this.loginUrl,
    this.baseUrl,
    this.requiresLogin = false,
  });

  String get _authDir => p.join(Directory.current.path, '.auth', name);

  Future<AuthState> load() async {
    final cookiesFile = File(p.join(_authDir, 'cookies.json'));
    final localStorageFile = File(p.join(_authDir, 'localstorage.json'));

    List<CookieParam> cookies = [];
    Map<String, String> localStorage = {};

    if (cookiesFile.existsSync()) {
      final rawCookies = jsonDecode(cookiesFile.readAsStringSync()) as List;
      cookies = rawCookies
          .map((c) => CookieParam(
                name: c['name'] as String,
                value: c['value'] as String,
                domain: c['domain'] as String?,
                path: c['path'] as String?,
                secure: c['secure'] as bool?,
                httpOnly: c['httpOnly'] as bool?,
              ))
          .toList();
    } else if (requiresLogin && loginUrl != null) {
      final state = await _loginInteractively();
      cookies = state.cookies;
      localStorage = state.localStorage;
      await _save(cookies, localStorage);
      return AuthState(cookies: cookies, localStorage: localStorage);
    }

    if (localStorageFile.existsSync()) {
      final raw = jsonDecode(localStorageFile.readAsStringSync());
      localStorage = Map<String, String>.from(raw as Map);
    }

    return AuthState(cookies: cookies, localStorage: localStorage);
  }

  Future<AuthState> _loginInteractively() async {
    final browser = RealBrowserInterceptorController(headless: false);
    await browser.launch(initialUrl: loginUrl);

    print('');
    print('=== MANUAL LOGIN REQUIRED ===');
    print('Browser opened at: $loginUrl');
    print('Please log in, then press ENTER to continue.');
    stdin.readLineSync();

    final cookies = await browser.extractCookies();
    final ls = await browser.extractLocalStorage();
    await browser.dispose();

    return AuthState(cookies: cookies, localStorage: ls);
  }

  Future<void> _save(
    List<CookieParam> cookies,
    Map<String, String> localStorage,
  ) async {
    final dir = Directory(_authDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final cookiesJson = cookies
        .map((c) => {
              'name': c.name,
              'value': c.value,
              'domain': c.domain,
              'path': c.path,
              'secure': c.secure,
              'httpOnly': c.httpOnly,
            })
        .toList();

    File(p.join(_authDir, 'cookies.json'))
        .writeAsStringSync(jsonEncode(cookiesJson));
    File(p.join(_authDir, 'localstorage.json'))
        .writeAsStringSync(jsonEncode(localStorage));
  }
}
