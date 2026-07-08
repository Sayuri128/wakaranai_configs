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
