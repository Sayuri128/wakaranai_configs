import 'dart:io';
import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:path/path.dart' as p;
import 'real_browser_interceptor_controller.dart';

String scriptPath(String relativePath) {
  return p.normalize(p.join(Directory.current.path, '..', relativePath));
}

Future<void> setupBrowserWithCookies(
  Interpreter interpreter,
  RealBrowserInterceptorController browser,
  String baseUrl,
) async {
  final response = await browser.loadPage(url: baseUrl);
  final cookieHeader =
      response.cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  final userAgent = await browser.userAgent();

  await interpreter.runFunction('passProtector', arguments: {
    'body': response.body,
    'headers': {
      'cookie': cookieHeader,
      'user-agent': userAgent,
    },
    'cookies': response.cookies,
  });
}
