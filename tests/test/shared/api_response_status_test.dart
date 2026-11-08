import 'package:capyscript/AST/throw/capyscript_error.dart';
import 'package:capyscript/Interpreter/capyscript_runtime_error.dart';
import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/api_clients/host/extension_host.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/http/http_module.dart';
import 'package:capyscript/modules/http/http_response.dart';
import 'package:capyscript/modules/waka_models/models/config_info/preferences/extension_preference.dart';
import 'package:test/test.dart';
import '../helpers/extension_host_helpers.dart';
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

void describeDecoder(
  String scriptRelativePath,
  String functionName, {
  required bool signalsLoginOn401,
  required SourceErrorKind anonymous404Kind,
  ExtensionHost host = ExtensionHost.none,
}) {
  group('$functionName in $scriptRelativePath', () {
    late Interpreter interpreter;

    setUpAll(() {
      interpreter = Interpreter.fromFile(
        path: scriptPath(scriptRelativePath),
        host: host,
      );
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

    Future<SourceError> sourceErrorFor(
      CapyHttpResponse response,
      SourceErrorKind kind,
    ) {
      return expectSourceError(
        () => interpreter.runFunction(
          functionName,
          arguments: {'apiResponse': response, 'requestLabel': 'title details'},
        ),
        kind,
      );
    }

    if (signalsLoginOn401) {
      test('401 asks the app to sign in again', () async {
        final error = await sourceErrorFor(
          fakeResponse(401, '{"message":"Unauthenticated."}'),
          SourceErrorKind.loginRequired,
        );
        expect(error.message, contains('title details'));
      });
    } else {
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
    }

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

    test('404 without a session reports ${anonymous404Kind.name}', () async {
      await sourceErrorFor(
        fakeResponse(404, '{"data":{"toast":{"message":"Not Found"}}}'),
        anonymous404Kind,
      );
    });

    test('429 reports a rate limit', () async {
      await sourceErrorFor(
        fakeResponse(429, '{"message":"Too Many Attempts."}'),
        SourceErrorKind.rateLimited,
      );
    });

    test('5xx reports the source as down', () async {
      for (final statusCode in [500, 502, 503]) {
        final error = await sourceErrorFor(
          fakeResponse(statusCode, '<html>Server Error</html>'),
          SourceErrorKind.sourceDown,
        );
        expect(error.message, contains('$statusCode'));
      }
    });

    test('other statuses stay plain script errors', () async {
      final Object? value = await thrownValue(
        interpreter,
        functionName,
        fakeResponse(418, '{}'),
        'teapot',
      );
      expect(value, 'HTTP 418 (teapot)');
    });
  });
}

void main() {
  describeDecoder(
    'shared/lib_social_api.capyscript',
    'libSocialDecodeResponse',
    signalsLoginOn401: true,
    anonymous404Kind: SourceErrorKind.notFound,
    host: hostFor(
      loadConfig('manga/manga_lib'),
      preferences: {ExtensionPreference.mirrorKey: 'https://api.lib.social'},
      uidSuffix: '-status',
    ),
  );
  describeDecoder(
    'manga/manga_dex/main.capyscript',
    'decodeApiResponse',
    signalsLoginOn401: false,
    anonymous404Kind: SourceErrorKind.notFound,
  );

  test('lib social names the DDoS guard on a non-JSON 403', () async {
    final interpreter = Interpreter.fromFile(
      path: scriptPath('shared/lib_social_api.capyscript'),
    );
    final Object? value = await thrownValue(
      interpreter,
      'libSocialDecodeResponse',
      fakeResponse(403, '<!DOCTYPE html><title>Error 403</title>'),
      'gallery',
    );
    expect(value, contains('mirror'));
    expect(value, contains('gallery'));
  });

  describeLibSocialMissing();
}

const String mangaLibHiddenFromGuests = '3754--sweet-home-kim-carnby-';
const String libSocialMissingTitle = '999999999--wakaranai-missing-title';
const String browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

Map<String, String> libSocialSessionHeaders(int siteId, String siteUrl) {
  return {
    'site-id': '$siteId',
    'Referer': '$siteUrl/',
    'user-agent': browserUserAgent,
    'x-requested-with': 'XMLHttpRequest',
  };
}

void describeLibSocialMissing() {
  group('lib social 404 classification', () {
    Interpreter interpreterWithHeaders(
      String extensionDirectory,
      Map<String, String> sessionHeaders,
    ) {
      final interpreter = Interpreter.fromFile(
        path: scriptPath('shared/lib_social_api.capyscript'),
        host: hostFor(
          loadConfig(extensionDirectory),
          preferences: {
            ExtensionPreference.mirrorKey: 'https://api.cdnlibs.org',
          },
          uidSuffix: '-missing',
        ),
      );
      (interpreter.builtinModule(HttpModule.module_name) as HttpModule)
          .setHeaders(sessionHeaders);
      return interpreter;
    }

    Future<SourceError> missingTitleError(
      Interpreter interpreter,
      String titleUid,
      SourceErrorKind kind,
    ) {
      return expectSourceError(
        () => interpreter.runFunction(
          'libSocialDecodeTitleResponse',
          arguments: {
            'apiResponse': fakeResponse(
              404,
              '{"data":{"toast":{"type":"silent","message":"Not Found"}}}',
            ),
            'requestLabel': 'title details',
            'titleUid': titleUid,
          },
        ),
        kind,
      );
    }

    test('a MangaLib guest gets notFound for a removed title', () async {
      final interpreter = interpreterWithHeaders(
        'manga/manga_lib',
        libSocialSessionHeaders(1, 'https://mangalib.me'),
      );
      await missingTitleError(
        interpreter,
        libSocialMissingTitle,
        SourceErrorKind.notFound,
      );
    });

    test('a MangaLib guest is asked to sign in for a title hidden from guests',
        () async {
      final interpreter = interpreterWithHeaders(
        'manga/manga_lib',
        libSocialSessionHeaders(1, 'https://mangalib.me'),
      );
      await missingTitleError(
        interpreter,
        mangaLibHiddenFromGuests,
        SourceErrorKind.loginRequired,
      );
    });

    test('a HentaiLib guest is asked to sign in on any 404', () async {
      final interpreter = interpreterWithHeaders(
        'manga/hentai_lib',
        libSocialSessionHeaders(4, 'https://hentailib.me'),
      );
      await missingTitleError(
        interpreter,
        libSocialMissingTitle,
        SourceErrorKind.loginRequired,
      );
    });

    test('an expired session token is asked to sign in again', () async {
      final interpreter = interpreterWithHeaders(
        'manga/manga_lib',
        {
          ...libSocialSessionHeaders(1, 'https://mangalib.me'),
          'Authorization': 'Bearer wakaranai-expired-token',
        },
      );
      final error = await missingTitleError(
        interpreter,
        libSocialMissingTitle,
        SourceErrorKind.loginRequired,
      );
      expect(error.message, contains('expired'));
    });
  });
}
