// Simple dev server for hosting this configs repo to the Wakaranai app locally.
//
// Run from the repo root:
//   dart tool/serve.dart            # port 8080
//   dart tool/serve.dart 9000       # custom port
//
// Then in the app point LOCAL_REPOSITORY_URL at it and switch
// RemoteConfigsCubit to RepoConfigsService:
//   - Android emulator: http://10.0.2.2:8080
//   - Real device:      http://<your-lan-ip>:8080
//
// Endpoints (matching LocalConfigsRepository):
//   GET /configs?category=manga|anime  -> { status, availableCategories, configs }
//   GET /script?path=<repo/relative/path.capyscript> -> { path, script }

import 'dart:convert';
import 'dart:io';

const List<String> _categories = <String>['manga', 'anime'];

late final Directory _root;

Future<void> main(List<String> args) async {
  _root = Directory.current;
  final int port =
      args.isNotEmpty ? int.tryParse(args.first) ?? 8080 : 8080;

  final HttpServer server =
      await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Serving ${_root.path} on http://0.0.0.0:$port');
  stdout.writeln('  emulator: http://10.0.2.2:$port   device: http://<lan-ip>:$port');

  await for (final HttpRequest request in server) {
    try {
      await _handle(request);
    } catch (e) {
      _json(request, HttpStatus.internalServerError,
          <String, dynamic>{'error': e.toString()});
    }
  }
}

Future<void> _handle(HttpRequest request) async {
  final String path = request.uri.path;
  stdout.writeln('${request.method} ${request.uri}');

  if (request.method != 'GET') {
    _json(request, HttpStatus.methodNotAllowed,
        <String, dynamic>{'error': 'method not allowed'});
    return;
  }

  switch (path) {
    case '/configs':
      _serveConfigs(request);
    case '/script':
      _serveScript(request);
    default:
      _json(request, HttpStatus.notFound,
          <String, dynamic>{'error': 'not found'});
  }
}

void _serveConfigs(HttpRequest request) {
  final String? category = request.uri.queryParameters['category'];

  final List<String> available = <String>[
    for (final String c in _categories)
      if (Directory('${_root.path}/$c').existsSync()) c,
  ];

  final List<String> wanted =
      category != null && category.isNotEmpty ? <String>[category] : available;

  final List<Map<String, dynamic>> configs = <Map<String, dynamic>>[];

  for (final String c in wanted) {
    final Directory dir = Directory('${_root.path}/$c');
    if (!dir.existsSync()) continue;

    final List<Directory> extensions = dir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((Directory a, Directory b) => a.path.compareTo(b.path));

    for (final Directory ext in extensions) {
      final String name = ext.path.split(Platform.pathSeparator).last;
      final File configFile = File('${ext.path}/config.json');
      if (!configFile.existsSync()) continue;

      configs.add(<String, dynamic>{
        'category': c,
        'path': '$c/$name/main.capyscript',
        'config': jsonDecode(configFile.readAsStringSync()),
      });
    }
  }

  _json(request, HttpStatus.ok, <String, dynamic>{
    'status': 200,
    'availableCategories': available,
    'configs': configs,
  });
}

void _serveScript(HttpRequest request) {
  final String? rawPath = request.uri.queryParameters['path'];
  if (rawPath == null || rawPath.isEmpty) {
    _json(request, HttpStatus.badRequest,
        <String, dynamic>{'error': 'missing path'});
    return;
  }

  final Uri rootUri = Directory(_root.path).uri;
  final Uri fileUri = rootUri.resolve(rawPath);

  // Reject anything that escapes the repo root.
  if (!fileUri.toFilePath().startsWith(rootUri.toFilePath())) {
    _json(request, HttpStatus.forbidden,
        <String, dynamic>{'error': 'path outside repo'});
    return;
  }

  final File file = File(fileUri.toFilePath());
  if (!file.existsSync()) {
    _json(request, HttpStatus.notFound,
        <String, dynamic>{'error': 'script not found: $rawPath'});
    return;
  }

  _json(request, HttpStatus.ok, <String, dynamic>{
    'path': rawPath,
    'script': file.readAsStringSync(),
  });
}

void _json(HttpRequest request, int status, Map<String, dynamic> body) {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  request.response.close();
}
