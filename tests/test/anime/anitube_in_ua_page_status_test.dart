import 'package:capyscript/AST/throw/capyscript_error.dart';
import 'package:capyscript/Interpreter/capyscript_runtime_error.dart';
import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/http/http_interceptor_controller.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import '../helpers/extension_host_helpers.dart';
import '../helpers/scraper_helpers.dart';

const String serverNotFoundPage = '''<!doctype html>
<html>
	<head>
		<meta charset="utf-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1.0" />
		<title>404 Not Found</title>
	</head>
	<body>
		<div class="container">
			<div class="logo"></div>
			<div class="title">404</div>
			<div class="desc">Sorry, the page you visited does not exist.<br />It may be that the access link is wrong or the file does not exist.</div>
		</div>
	</body>
</html>''';

const String titlePage = '''<!doctype html>
<html><head><title>Монолог травниці (3 сезон) аніме українською онлайн</title></head>
<body><div id="dle-content"><div class="story">
<div class="story_c"><div class="rcol"><div class="story_c_r">Рік виходу аніме: 2025</div></div>
<div class="story_c_text"><div class="my-text">Опис</div></div></div>
</div></div></body></html>''';

const String bogusTitleUid = '9999999-neisnuyuchyi-tytul.html';

class CannedInterceptor implements HttpInterceptorController {
  CannedInterceptor(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<HttpInterceptorControllerResponse> loadPage({
    required String url,
    String? method,
    Map<String, String>? headers,
    String? body,
  }) async {
    return HttpInterceptorControllerResponse(
      body: this.body,
      data: const {},
      statusCode: statusCode,
      headers: const {},
      cookies: const {},
    );
  }

  @override
  Future<dynamic> executeJsScript(String code) async => [];
}

Interpreter anitubeInterpreter() {
  return Interpreter.fromFile(
    path: scriptPath('anime/anitube_in_ua/main.capyscript'),
  );
}

Future<Interpreter> interpreterBehindInterceptor(
  int statusCode,
  String body,
) async {
  final interpreter = anitubeInterpreter();
  await interpreter.runFunction(
    'passWebBrowserInterceptorController',
    arguments: {'controller': CannedInterceptor(statusCode, body)},
  );
  return interpreter;
}

Future<Object?> checkPage(
  Interpreter interpreter,
  int statusCode,
  String body, {
  bool missingIsError = true,
}) {
  return interpreter.runFunction(
    'checkPageStatus',
    arguments: {
      'pageResponse': HttpInterceptorControllerResponse(
        body: body,
        data: const {},
        statusCode: statusCode,
        headers: const {},
        cookies: const {},
      ),
      'pageLabel': bogusTitleUid,
      'missingIsError': missingIsError,
    },
  );
}

Object? scriptErrorValue(Object error) {
  Object? current = error;
  for (int depth = 0; depth < 6; depth++) {
    if (current is CapyScriptRuntimeError) {
      current = current.cause;
    } else if (current is CapyScriptError) {
      return current.value;
    } else {
      return current;
    }
  }
  return current;
}

Future<Object?> concreteFor(Interpreter interpreter, String uid) {
  return interpreter.runFunction(
    'getConcrete',
    arguments: {
      'uid': uid,
      'data': {'cover': '', 'title': 'Title'},
    },
  );
}

void main() {
  group('checkPageStatus content check', () {
    late Interpreter interpreter;

    setUpAll(() {
      interpreter = anitubeInterpreter();
    });

    test('the server 404 page reported as 200 is notFound', () async {
      final error = await expectSourceError(
        () => checkPage(interpreter, 200, serverNotFoundPage),
        SourceErrorKind.notFound,
      );
      expect(error.message, contains(bogusTitleUid));
    });

    test('the server 404 page is a missing page when it is not an error',
        () async {
      final Object? usable = await checkPage(
        interpreter,
        200,
        serverNotFoundPage,
        missingIsError: false,
      );
      expect(usable, isFalse);
    });

    test('a title page is usable', () async {
      expect(await checkPage(interpreter, 200, titlePage), isTrue);
    });

    test('unreadable and timed out loads report the source as down', () async {
      for (final statusCode in [0, 408]) {
        await expectSourceError(
          () => checkPage(interpreter, statusCode, ''),
          SourceErrorKind.sourceDown,
        );
      }
    });

    test('an empty 200 body reports the source as down', () async {
      await expectSourceError(
        () => checkPage(interpreter, 200, '   '),
        SourceErrorKind.sourceDown,
      );
    });

    test('403 throws the challenge message', () async {
      try {
        await checkPage(interpreter, 403, '<html>challenge</html>');
      } catch (error) {
        expect(
          scriptErrorValue(error),
          'HTTP 403 Forbidden (anitube.in.ua $bogusTitleUid)',
        );
        return;
      }
      fail('403 did not throw');
    });
  });

  group('getConcrete behind an interceptor that always reports 200', () {
    test('the server 404 page throws notFound', () async {
      final interpreter =
          await interpreterBehindInterceptor(200, serverNotFoundPage);
      await expectSourceError(
        () => concreteFor(interpreter, bogusTitleUid),
        SourceErrorKind.notFound,
      );
    });

    test('a timed out load throws sourceDown instead of an empty title',
        () async {
      final interpreter = await interpreterBehindInterceptor(408, '');
      await expectSourceError(
        () => concreteFor(interpreter, bogusTitleUid),
        SourceErrorKind.sourceDown,
      );
    });

    test('a page without title markup throws sourceDown', () async {
      final interpreter = await interpreterBehindInterceptor(
        200,
        '<html><head><title>AniTube</title></head><body></body></html>',
      );
      await expectSourceError(
        () => concreteFor(interpreter, bogusTitleUid),
        SourceErrorKind.sourceDown,
      );
    });

    test('search on the server 404 page returns no results', () async {
      final interpreter =
          await interpreterBehindInterceptor(200, serverNotFoundPage);
      final Object? gallery = await interpreter.runFunction(
        'getGallery',
        arguments: {'page': 1, 'query': 'наруто', 'filters': [], 'feed': ''},
      );
      expect(gallery, isEmpty);
    });
  });

  group('live anitube.in.ua not-found page', () {
    test('the live 404 page for a removed title is detected by content',
        () async {
      final response = await http.get(
        Uri.parse('https://anitube.in.ua/$bogusTitleUid'),
        headers: {'user-agent': 'Mozilla/5.0'},
      );
      expect(response.statusCode, 404);
      final interpreter = anitubeInterpreter();
      await expectSourceError(
        () => checkPage(interpreter, 200, response.body),
        SourceErrorKind.notFound,
      );
    });

    test('getConcrete over plain http throws notFound for a removed title',
        () async {
      await expectSourceError(
        () => concreteFor(anitubeInterpreter(), bogusTitleUid),
        SourceErrorKind.notFound,
      );
    });
  });
}
