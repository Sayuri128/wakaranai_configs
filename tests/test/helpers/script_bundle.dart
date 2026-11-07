import 'dart:io';

import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:path/path.dart' as p;

import 'extension_host_helpers.dart';
import 'scraper_helpers.dart';

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

NovelApiClient novelClientFor(
  String extensionDirectory, {
  Map<String, Object?> preferences = const {},
}) {
  final config = loadConfig(extensionDirectory);
  return NovelApiClient(
    code: bundleScript(scriptPath('$extensionDirectory/main.capyscript')),
    host: hostFor(config, preferences: preferences),
  );
}
