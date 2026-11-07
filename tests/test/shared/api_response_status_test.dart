import 'package:capyscript/AST/throw/capyscript_error.dart';
import 'package:capyscript/Interpreter/capyscript_runtime_error.dart';
import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/http/http_response.dart';
import 'package:test/test.dart';
import '../helpers/scraper_helpers.dart';

final RegExp labelledAuthStatusPattern = RegExp(
  r'\b(?:status(?:\s*code)?|statusCode|http(?:\s*error)?)\s*[:=(]?\s*(?:401|403)\b',
  caseSensitive: false,
);
final RegExp namedAuthStatusPattern = RegExp(
  r'\b(?:401\s+unauthorized|403\s+forbidden)\b',
  caseSensitive: false,
);

bool looksLikeExpiredSession(String text) {
  return labelledAuthStatusPattern.hasMatch(text) ||
      namedAuthStatusPattern.hasMatch(text);
}

CapyHttpResponse fakeResponse(int statusCode, String body) {
  return CapyHttpResponse(
    statusCode: statusCode,
    body: body,
    contentLength: body.length,
    headers: const {'content-type': 'application/json'},
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

Future<Object?> thrownValue(
  Interpreter interpreter,
  String functionName,
  CapyHttpResponse response,
  String requestLabel,
) async {
  try {
    await interpreter.runFunction(
      functionName,
      arguments: {'apiResponse': response, 'requestLabel': requestLabel},
    );
  } catch (error) {
    final Object? value = scriptErrorValue(error);
    expect(
      error.toString(),
      contains(value.toString()),
      reason: 'the host-side error text must carry the thrown message',
    );
    return value;
  }
  fail('$functionName did not throw for HTTP ${response.statusCode}');
}

void describeDecoder(String scriptRelativePath, String functionName) {
  group('$functionName in $scriptRelativePath', () {
    late Interpreter interpreter;

    setUpAll(() {
      interpreter = Interpreter.fromFile(path: scriptPath(scriptRelativePath));
    });

    test('decodes a 200 body', () async {
      final Object? decoded = await interpreter.runFunction(
        functionName,
        arguments: {
          'apiResponse': fakeResponse(200, '{"data":[{"id":1}]}'),
          'requestLabel': 'gallery',
        },
      );
      expect(decoded, isA<Map>());
      expect((decoded as Map)['data'], [
        {'id': 1},
      ]);
    });

    test('401 throws a sign-in-again message', () async {
      final Object? value = await thrownValue(
        interpreter,
        functionName,
        fakeResponse(401, '{"message":"Unauthenticated."}'),
        'gallery',
      );
      expect(value, 'HTTP 401 Unauthorized (gallery)');
      expect(looksLikeExpiredSession(value.toString()), isTrue);
    });

    test('403 throws a sign-in-again message', () async {
      final Object? value = await thrownValue(
        interpreter,
        functionName,
        fakeResponse(403, '{"message":"Forbidden"}'),
        'chapter pages',
      );
      expect(value, 'HTTP 403 Forbidden (chapter pages)');
      expect(looksLikeExpiredSession(value.toString()), isTrue);
    });

    test('429 throws a rate-limit message', () async {
      final Object? value = await thrownValue(
        interpreter,
        functionName,
        fakeResponse(429, '{"message":"Too Many Attempts."}'),
        'title details',
      );
      expect(value, 'HTTP 429 Too Many Requests (title details)');
      expect(looksLikeExpiredSession(value.toString()), isFalse);
    });

    test('500 throws the status code with context', () async {
      final Object? value = await thrownValue(
        interpreter,
        functionName,
        fakeResponse(500, '<html>Server Error</html>'),
        'chapter list',
      );
      expect(value, 'HTTP 500 (chapter list)');
      expect(looksLikeExpiredSession(value.toString()), isFalse);
    });
  });
}

void main() {
  describeDecoder('shared/lib_social_api.capyscript', 'libSocialDecodeResponse');
  describeDecoder('manga/manga_dex/main.capyscript', 'decodeApiResponse');
}
