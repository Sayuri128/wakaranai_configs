import 'dart:convert';
import 'dart:io';

const List<String> _categories = <String>['manga', 'anime'];
const String _outputPath = 'index.json';

void main(List<String> args) {
  final Directory root = Directory.current;
  final List<Map<String, dynamic>> configs = <Map<String, dynamic>>[];

  for (final String category in _categories) {
    final Directory categoryDir = Directory('${root.path}/$category');
    if (!categoryDir.existsSync()) {
      continue;
    }

    final List<Directory> extensionDirs = categoryDir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((Directory a, Directory b) => a.path.compareTo(b.path));

    for (final Directory extensionDir in extensionDirs) {
      final String name = extensionDir.path.split(Platform.pathSeparator).last;
      final File configFile = File('${extensionDir.path}/config.json');
      if (!configFile.existsSync()) {
        stderr.writeln('skip $category/$name: no config.json');
        continue;
      }

      final Object? config = jsonDecode(configFile.readAsStringSync());
      configs.add(<String, dynamic>{
        'category': category,
        'path': '$category/$name',
        'revision': _revision(extensionDir),
        'config': config,
      });
    }
  }

  final Map<String, dynamic> index = <String, dynamic>{
    'schemaVersion': 1,
    'configs': configs,
  };

  final String output =
      '${const JsonEncoder.withIndent('  ').convert(index)}\n';
  File('${root.path}/$_outputPath').writeAsStringSync(output);
  stdout.writeln('wrote $_outputPath (${configs.length} configs)');
}

final RegExp _relativeImport =
    RegExp(r'''^import\s+["'](\.{1,2}/[^"']+)["']\s*;''', multiLine: true);

String _revision(Directory extensionDir) {
  final List<File> files = <File>[File('${extensionDir.path}/config.json')];
  final Set<String> seen = <String>{};
  void collect(File script) {
    final String path = script.absolute.uri.normalizePath().toFilePath();
    if (!seen.add(path) || !script.existsSync()) {
      return;
    }
    files.add(script);
    for (final RegExpMatch match
        in _relativeImport.allMatches(script.readAsStringSync())) {
      collect(File('${script.parent.path}/${match.group(1)}.capyscript'));
    }
  }

  collect(File('${extensionDir.path}/main.capyscript'));

  int hash = 0xcbf29ce484222325;
  for (final File file in files) {
    final List<int> bytes =
        utf8.encode(file.readAsStringSync().replaceAll('\r\n', '\n'));
    for (final int byte in <int>[...bytes, 0]) {
      hash ^= byte;
      hash *= 0x100000001b3;
    }
  }
  return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
