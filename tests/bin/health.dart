import 'dart:async';
import 'dart:io';

import 'package:capyscript/api_clients/anime_api_client.dart';
import 'package:capyscript/api_clients/api_client.dart';
import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_video.dart';
import 'package:capyscript/modules/waka_models/models/anime/anime_concrete_view/anime_video/anime_view_type.dart';
import 'package:capyscript/modules/waka_models/models/common/element_of_elements_group_of_concrete.dart';
import 'package:capyscript/modules/waka_models/models/common/gallery_view.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import '../test/helpers/auth_session.dart';
import '../test/helpers/extension_host_helpers.dart';
import '../test/helpers/real_browser_interceptor_controller.dart';
import '../test/helpers/scraper_helpers.dart';

const List<String> categories = ['manga', 'anime'];
const Map<String, String> sessionAliases = {'lib_social': 'mangalib'};
const String desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const int maxConcreteAttempts = 3;
const int maxImageAttempts = 3;

enum Outcome { ok, fail, skipped }

class HealthOptions {
  final List<String> only;
  final bool allowBrowser;
  final Duration stepTimeout;
  final Map<String, Object?> preferences;

  const HealthOptions({
    required this.only,
    required this.allowBrowser,
    required this.stepTimeout,
    required this.preferences,
  });
}

class HealthResult {
  final String extension;
  final String step;
  final Outcome outcome;
  final Duration elapsed;
  final String note;

  const HealthResult({
    required this.extension,
    required this.step,
    required this.outcome,
    required this.elapsed,
    required this.note,
  });
}

class StepFailure implements Exception {
  final String message;

  const StepFailure(this.message);

  @override
  String toString() => message;
}

class NullLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

Future<void> main(List<String> arguments) async {
  final options = parseOptions(arguments);
  if (options == null) {
    exitCode = 64;
    return;
  }
  silenceInterpreterLogs();

  final directories = discoverExtensions(options.only);
  if (directories.isEmpty) {
    stderr.writeln('no extensions matched');
    exitCode = 64;
    return;
  }

  final results = <HealthResult>[];
  for (final directory in directories) {
    stdout.writeln('checking $directory ...');
    final result = await runSilenced(() => checkExtension(directory, options));
    results.add(result);
  }

  stdout.writeln('');
  printTable(results);
  if (results.any((result) => result.outcome == Outcome.fail)) {
    exitCode = 1;
  }
  exit(exitCode);
}

HealthOptions? parseOptions(List<String> arguments) {
  final only = <String>[];
  var allowBrowser = false;
  var timeoutSeconds = 90;
  final preferences = <String, Object?>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--only' && index + 1 < arguments.length) {
      index++;
      only.addAll(arguments[index].split(',').where((s) => s.isNotEmpty));
    } else if (argument == '--browser') {
      allowBrowser = true;
    } else if (argument == '--timeout' && index + 1 < arguments.length) {
      index++;
      timeoutSeconds = int.parse(arguments[index]);
    } else if (argument == '--pref' &&
        index + 1 < arguments.length &&
        arguments[index + 1].contains('=')) {
      index++;
      final separator = arguments[index].indexOf('=');
      preferences[arguments[index].substring(0, separator)] =
          arguments[index].substring(separator + 1);
    } else {
      stderr.writeln(
        'usage: dart run bin/health.dart [--only <dir>[,<dir>]] [--browser] [--timeout <seconds>] [--pref <key>=<value>]...',
      );
      return null;
    }
  }
  return HealthOptions(
    only: only,
    allowBrowser: allowBrowser,
    stepTimeout: Duration(seconds: timeoutSeconds),
    preferences: preferences,
  );
}

void silenceInterpreterLogs() {
  Logger.level = Level.off;
  Logger.defaultOutput = () => NullLogOutput();
}

Future<T> runSilenced<T>(Future<T> Function() body) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {},
    ),
  );
}

List<String> discoverExtensions(List<String> only) {
  final found = <String>[];
  for (final category in categories) {
    final categoryDirectory = Directory(scriptPath(category));
    if (categoryDirectory.existsSync() == false) {
      continue;
    }
    final names = categoryDirectory
        .listSync()
        .whereType<Directory>()
        .where((d) => File(p.join(d.path, 'config.json')).existsSync())
        .map((d) => p.basename(d.path))
        .toList()
      ..sort();
    for (final name in names) {
      found.add('$category/$name');
    }
  }
  if (only.isEmpty) {
    return found;
  }
  final wanted = only.map(normalizeSelector).toSet();
  return found
      .where((dir) => wanted.contains(dir) || wanted.contains(p.posix.basename(dir)))
      .toList();
}

String normalizeSelector(String selector) {
  var normalized = selector.replaceAll('\\', '/');
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  while (normalized.startsWith('../')) {
    normalized = normalized.substring(3);
  }
  return normalized;
}

String bundleScript(String entryPath) {
  final imports = <String>[];
  final bodies = <String>[];
  collectScript(p.normalize(entryPath), imports, bodies, <String>{});
  final uniqueImports = <String>[];
  for (final line in imports) {
    if (uniqueImports.contains(line) == false) {
      uniqueImports.add(line);
    }
  }
  return [
    if (uniqueImports.isNotEmpty) uniqueImports.join('\n'),
    ...bodies.where((body) => body.trim().isNotEmpty),
  ].join('\n\n');
}

final RegExp importPattern = RegExp(
  r'''^\s*import\s+["']([^"']+)["'];\s*$''',
  multiLine: true,
);

void collectScript(
  String path,
  List<String> imports,
  List<String> bodies,
  Set<String> visited,
) {
  if (visited.add(path) == false) {
    return;
  }
  final source = File(path).readAsStringSync();
  for (final match in importPattern.allMatches(source)) {
    final target = match.group(1)!;
    if (target.startsWith('./') || target.startsWith('../')) {
      var resolved = p.normalize(p.join(p.dirname(path), target));
      if (p.extension(resolved).isEmpty) {
        resolved = '$resolved.capyscript';
      }
      collectScript(resolved, imports, bodies, visited);
    } else {
      imports.add(match.group(0)!.trim());
    }
  }
  final body = source.replaceAll(importPattern, '').trim();
  if (body.isNotEmpty) {
    bodies.add(body);
  }
}

String? savedSessionFor(String directory, ConfigInfo config) {
  final group = config.protectorConfig?.sessionGroup;
  final candidates = <String>[
    if (group != null) group,
    if (group != null && sessionAliases.containsKey(group)) sessionAliases[group]!,
    p.posix.basename(directory),
  ];
  for (final candidate in candidates) {
    final cookies = File(p.join(Directory.current.path, '.auth', candidate, 'cookies.json'));
    if (cookies.existsSync()) {
      return candidate;
    }
  }
  return null;
}

class ExtensionRun {
  final String directory;
  final HealthOptions options;
  final Stopwatch stopwatch = Stopwatch();
  String step = 'load';
  final List<String> notes = [];
  RealBrowserInterceptorController? browser;

  ExtensionRun(this.directory, this.options);

  Future<T> run<T>(String name, Future<T> Function() body) async {
    step = name;
    return await body().timeout(
      options.stepTimeout,
      onTimeout: () => throw StepFailure('timed out after ${options.stepTimeout.inSeconds}s'),
    );
  }

  HealthResult finish(Outcome outcome, String note) {
    return HealthResult(
      extension: directory,
      step: step,
      outcome: outcome,
      elapsed: stopwatch.elapsed,
      note: note,
    );
  }
}

Future<HealthResult> checkExtension(String directory, HealthOptions options) async {
  final run = ExtensionRun(directory, options)..stopwatch.start();
  try {
    final config = loadConfig(directory);
    final protector = config.protectorConfig;
    final session = savedSessionFor(directory, config);
    final needsBrowser = protector != null &&
        (protector.needToLogin || protector.inAppBrowserInterceptor);
    if (needsBrowser && session == null) {
      if (protector.needToLogin || options.allowBrowser == false) {
        run.step = 'protector';
        return run.finish(Outcome.skipped, 'skipped (needs session)');
      }
    }

    final code = bundleScript(scriptPath('$directory/main.capyscript'));
    final host = hostFor(config, preferences: options.preferences);
    final ApiClient client = config.type == ConfigInfoType.ANIME
        ? AnimeApiClient(code: code, host: host)
        : MangaApiClient(code: code, host: host);
    if (client.interpreter.hasFunction('getGallery') == false) {
      throw const StepFailure('getGallery is not defined');
    }

    if (protector != null) {
      await run.run('protector', () => passProtector(run, client, config, session, needsBrowser));
    }

    final feed = config.feeds.isEmpty ? '' : config.feeds.first.id;
    final gallery = await run.run(
      'gallery',
      () => client.getGallery(page: 1, query: '', filters: [], feed: feed),
    );
    if (gallery.isEmpty) {
      throw const StepFailure('empty gallery');
    }
    run.notes.add('${gallery.length} items');

    final element = await run.run('concrete', () => firstElement(client, gallery, run));

    if (client is MangaApiClient) {
      await checkMangaPages(run, client, element);
    } else if (client is AnimeApiClient) {
      await checkAnimeSources(run, client, element as AnimeVideo);
    }
    return run.finish(Outcome.ok, run.notes.join(', '));
  } catch (error) {
    return run.finish(Outcome.fail, shortError(error));
  } finally {
    await run.browser?.dispose();
  }
}

Future<void> passProtector(
  ExtensionRun run,
  ApiClient client,
  ConfigInfo config,
  String? session,
  bool needsBrowser,
) async {
  final protector = config.protectorConfig!;
  final auth = session == null
      ? const AuthState(cookies: [], localStorage: {})
      : await AuthSession(name: session).load();
  if (session != null) {
    run.notes.add('session ${p.posix.basename(session)}');
  }

  if (needsBrowser || run.options.allowBrowser) {
    final browser = RealBrowserInterceptorController(headless: true);
    run.browser = browser;
    await browser.launch(
      cookies: auth.cookies,
      localStorage: auth.localStorage,
      initialUrl: auth.localStorage.isNotEmpty ? protector.pingUrl : null,
    );
    if (protector.inAppBrowserInterceptor &&
        client.interpreter.hasFunction('passWebBrowserInterceptorController')) {
      await client.passWebBrowserInterceptorController(controller: browser);
    }
    final response = await browser.loadPage(url: protector.pingUrl);
    final cookieHeader =
        response.cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final userAgent = await browser.userAgent();
    if (client.interpreter.hasFunction('passProtector')) {
      await client.passProtector(
        body: response.body,
        headers: {'cookie': cookieHeader, 'user-agent': userAgent},
        cookies: Map<String, String>.from(response.cookies),
      );
    }
    return;
  }

  if (client.interpreter.hasFunction('passProtector') == false) {
    return;
  }
  final cookies = {for (final c in auth.cookies) c.name: c.value};
  await client.passProtector(
    body: '',
    headers: {
      'cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      'user-agent': desktopUserAgent,
    },
    cookies: cookies,
  );
}

Future<ElementOfElementsGroupOfConcrete> firstElement(
  ApiClient client,
  List<GalleryView> gallery,
  ExtensionRun run,
) async {
  Object? lastError;
  final attempts = gallery.length < maxConcreteAttempts ? gallery.length : maxConcreteAttempts;
  for (var index = 0; index < attempts; index++) {
    final item = gallery[index];
    try {
      final concrete = await client.getConcrete(uid: item.uid, data: item.data);
      final groups = concrete.groups.where((g) => g.elements.isNotEmpty).toList();
      if (groups.isEmpty) {
        lastError = StepFailure('no chapters in "${item.uid}"');
        continue;
      }
      final count = concrete.groups.fold<int>(0, (sum, g) => sum + g.elements.length);
      run.notes.add('$count ${client is AnimeApiClient ? 'ep' : 'ch'}');
      if (index > 0) {
        run.notes.add('item #${index + 1}');
      }
      return groups.first.elements.first;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? const StepFailure('no title with chapters');
}

Future<void> checkMangaPages(
  ExtensionRun run,
  MangaApiClient client,
  ElementOfElementsGroupOfConcrete chapter,
) async {
  final pages = await run.run(
    'pages',
    () => client.getPages(uid: chapter.uid, data: chapter.data),
  );
  if (pages.value.isEmpty) {
    throw const StepFailure('no pages');
  }
  run.notes.add('${pages.value.length} pages');

  final headers = await run.run(
    'image headers',
    () => client.getImageHeaders(uid: chapter.uid, data: chapter.data),
  );
  final contentType = await run.run('image', () => probeFirstImage(run, pages.value, headers));
  run.notes.add(contentType);
}

Future<String> probeFirstImage(
  ExtensionRun run,
  List<String> pageUrls,
  Map<String, String> headers,
) async {
  Object? firstError;
  final attempts = pageUrls.length < maxImageAttempts ? pageUrls.length : maxImageAttempts;
  for (var index = 0; index < attempts; index++) {
    try {
      final contentType = await probe(pageUrls[index], headers);
      if (contentType.startsWith('text/html')) {
        throw StepFailure('page ${index + 1} is $contentType');
      }
      if (index > 0) {
        run.notes.add('page 1 failed: $firstError');
      }
      return contentType;
    } catch (error) {
      firstError ??= error;
    }
  }
  throw firstError ?? const StepFailure('no image');
}

Future<void> checkAnimeSources(
  ExtensionRun run,
  AnimeApiClient client,
  AnimeVideo video,
) async {
  if (await client.supportsVideoSources()) {
    final sources = await run.run('sources', () => client.getVideoSources(video));
    if (sources.isEmpty) {
      if (video.type == AnimeVideoType.IFRAME) {
        run.notes.add('no sources, iframe');
        await run.run('media', () => probe(video.src, const {}));
        return;
      }
      throw const StepFailure('no video sources');
    }
    run.notes.add('${sources.length} sources');
    final first = sources.first;
    final contentType = await run.run('media', () => probe(first.url, first.headers));
    run.notes.add(contentType);
    return;
  }
  run.notes.add(video.type == AnimeVideoType.IFRAME ? 'iframe' : 'direct');
  final contentType = await run.run('media', () => probe(video.src, const {}));
  run.notes.add(contentType);
}

Future<String> probe(String url, Map<String, String> headers) async {
  final uri = Uri.parse(url.startsWith('//') ? 'https:$url' : url);
  final client = http.Client();
  try {
    final request = http.Request('GET', uri)
      ..followRedirects = true
      ..headers.addAll(headers);
    final response = await client.send(request);
    final status = response.statusCode;
    final contentType = (response.headers['content-type'] ?? '?').split(';').first.trim();
    await response.stream.listen((_) {}).cancel();
    if (status >= 400) {
      throw StepFailure('HTTP $status for ${uri.host}');
    }
    return contentType;
  } finally {
    client.close();
  }
}

final RegExp secretPattern = RegExp(
  r'''(cookie|set-cookie|authorization|x-api-key|apikey|x-xsrf-token|cf_clearance)(["']?\s*[:=]\s*)("[^"]*"|'[^']*'|[^,}\n]*)''',
  caseSensitive: false,
);

String redact(String text) {
  return text.replaceAllMapped(secretPattern, (m) => '${m.group(1)}${m.group(2)}<redacted>');
}

String shortError(Object error) {
  var text = redact(error.toString()).replaceAll('\r', ' ').replaceAll('\n', ' ');
  text = text.replaceFirst(RegExp(r'^(Exception|CapyScriptRuntimeError):\s*'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length > 110) {
    text = '${text.substring(0, 107)}...';
  }
  return text;
}

String formatDuration(Duration duration) {
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

void printTable(List<HealthResult> results) {
  final rows = <List<String>>[
    ['extension', 'step', 'result', 'time', 'note'],
    for (final r in results)
      [r.extension, r.step, r.outcome.name, formatDuration(r.elapsed), r.note],
  ];
  final widths = List<int>.filled(4, 0);
  for (final row in rows) {
    for (var column = 0; column < 4; column++) {
      if (row[column].length > widths[column]) {
        widths[column] = row[column].length;
      }
    }
  }
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    final cells = [
      for (var column = 0; column < 4; column++) row[column].padRight(widths[column]),
      row[4],
    ];
    stdout.writeln(cells.join('  ').trimRight());
    if (index == 0) {
      stdout.writeln(cells.map((c) => '-' * (c.isEmpty ? 4 : c.length)).join('  '));
    }
  }
  final failed = results.where((r) => r.outcome == Outcome.fail).length;
  final skipped = results.where((r) => r.outcome == Outcome.skipped).length;
  final passed = results.length - failed - skipped;
  stdout.writeln('');
  stdout.writeln('$passed ok, $failed failed, $skipped skipped');
}
