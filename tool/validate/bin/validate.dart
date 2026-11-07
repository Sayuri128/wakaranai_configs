import 'dart:convert';
import 'dart:io';

import 'package:capyscript/modules/abstract/base_module.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/parser/parser.dart';

const Map<String, int> _categoryTypes = {'manga': 0, 'anime': 1};

const Map<String, List<String>> _requiredFunctions = {
  'manga': ['getGallery', 'getConcrete', 'getPages'],
  'anime': ['getGallery', 'getConcrete'],
};

final RegExp _uuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
final RegExp _topLevelFunction = RegExp(r'^function\s+(\w+)', multiLine: true);
final RegExp _import = RegExp(r'''^import\s+["']([^"']+)["']\s*;''', multiLine: true);
final RegExp _incrementBeforeContinue = RegExp(
    r'\b(\w+)\s*(?:=\s*\1\s*\+\s*1|\+\+|\+=\s*1)\s*;\s*continue\s*;');

const int _legacyApiVersion = 1;
const int _latestApiVersion = 2;

const Map<String, int> _moduleApiVersions = {
  'preferences': 2,
  'storage': 2,
  'errors': 2,
};

const Map<String, int> _functionApiVersions = {
  'getPreference': 2,
  'storageGet': 2,
  'storageSet': 2,
  'storageRemove': 2,
  'throwSourceError': 2,
  'currentMirror': 2,
};

const Map<String, int> _configFieldApiVersions = {
  'preferences': 2,
  'requestPolicy': 2,
  'feeds': 2,
};

const Map<String, int> _downloadConfigFieldApiVersions = {
  'segmentConcurrency': 2,
  'episodeDelayMs': 2,
};

final RegExp _semanticVersion = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _apiFunctionCall =
    RegExp('\\b(${_functionApiVersions.keys.join('|')})\\s*\\(');

class _ApiFeature {
  const _ApiFeature(this.description, this.apiVersion);

  final String description;
  final int apiVersion;
}

void main(List<String> args) {
  final root = Directory(args.isEmpty ? '.' : args.first).absolute;
  final errors = <String>[];
  final uids = <String, String>{};
  var checked = 0;

  for (final category in _categoryTypes.keys) {
    final dir = Directory('${root.path}/$category');
    if (!dir.existsSync()) {
      continue;
    }
    final extensions = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final extension in extensions) {
      checked++;
      final name = '$category/${_basename(extension.path)}';
      _validateExtension(extension, name, category, uids,
          (message) => errors.add('$name: $message'));
    }
  }

  for (final error in errors) {
    stderr.writeln(error);
  }
  stdout.writeln(errors.isEmpty
      ? 'ok: $checked extensions'
      : '${errors.length} problem(s) in $checked extensions');
  exit(errors.isEmpty ? 0 : 1);
}

void _validateExtension(Directory dir, String name, String category,
    Map<String, String> uids, void Function(String) fail) {
  final configFile = File('${dir.path}/config.json');
  if (!configFile.existsSync()) {
    fail('missing config.json');
    return;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(configFile.readAsStringSync());
  } on FormatException catch (e) {
    fail('config.json is not valid JSON: ${e.message}');
    return;
  }
  if (decoded is! Map<String, dynamic>) {
    fail('config.json must be an object');
    return;
  }

  final features = <_ApiFeature>[];
  _validateConfig(decoded, name, category, features, fail);

  final uid = decoded['uid'];
  if (uid is String) {
    final owner = uids[uid];
    if (owner != null) {
      fail('uid $uid is already used by $owner');
    } else {
      uids[uid] = name;
    }
  }

  if (!File('${dir.path}/logo.png').existsSync()) {
    fail('missing logo.png');
  }

  final script = File('${dir.path}/main.capyscript');
  if (!script.existsSync()) {
    fail('missing main.capyscript');
    return;
  }
  final functions = <String>{};
  _validateScript(script, functions, <String>{}, features, fail);
  for (final required in _requiredFunctions[category]!) {
    if (!functions.contains(required)) {
      fail('main.capyscript does not define $required');
    }
  }
  _validateApiFeatures(_declaredApiVersion(decoded), features, fail);
}

int _declaredApiVersion(Map<String, dynamic> config) {
  final apiVersion = config['apiVersion'];
  if (apiVersion is int) {
    return apiVersion;
  }
  return _legacyApiVersion;
}

void _validateApiFeatures(
    int apiVersion, List<_ApiFeature> features, void Function(String) fail) {
  final reported = <String>{};
  for (final feature in features) {
    if (feature.apiVersion <= apiVersion) {
      continue;
    }
    if (!reported.add(feature.description)) {
      continue;
    }
    fail('${feature.description} needs "apiVersion": ${feature.apiVersion} '
        'or higher (declared $apiVersion)');
  }
}

void _validateConfig(Map<String, dynamic> config, String name, String category,
    List<_ApiFeature> features, void Function(String) fail) {
  void expectType<T>(String key, {bool nullable = false}) {
    final value = config[key];
    if (value == null && nullable) {
      return;
    }
    if (value is! T) {
      fail('"$key" must be ${T.toString()}${nullable ? ' or null' : ''}');
    }
  }

  expectType<String>('name');
  expectType<String>('uid');
  expectType<String>('logoUrl');
  expectType<int>('type');
  expectType<bool>('nsfw');
  expectType<String>('language');
  expectType<int>('version');
  expectType<bool>('searchAvailable');
  expectType<List>('filters');
  expectType<Map>('protectorConfig', nullable: true);
  expectType<int>('apiVersion', nullable: true);
  expectType<String>('minAppVersion', nullable: true);

  final uid = config['uid'];
  if (uid is String && !_uuid.hasMatch(uid)) {
    fail('"uid" must be a lowercase UUID');
  }
  if (config['type'] is int && config['type'] != _categoryTypes[category]) {
    fail('"type" is ${config['type']} but the extension lives in $category/');
  }
  final version = config['version'];
  if (version is int && version < 1) {
    fail('"version" must be at least 1');
  }
  final apiVersion = config['apiVersion'];
  if (apiVersion is int &&
      (apiVersion < _legacyApiVersion || apiVersion > _latestApiVersion)) {
    fail('"apiVersion" must be between $_legacyApiVersion and '
        '$_latestApiVersion, the highest api version this tooling knows');
  }
  final minAppVersion = config['minAppVersion'];
  if (minAppVersion is String && !_semanticVersion.hasMatch(minAppVersion)) {
    fail('"minAppVersion" must look like 1.2.3');
  }
  _collectConfigApiFeatures(config, features);
  final logoUrl = config['logoUrl'];
  if (logoUrl is String && !logoUrl.endsWith('/$name/logo.png?raw=true')) {
    fail('"logoUrl" should point at $name/logo.png');
  }
  final protector = config['protectorConfig'];
  if (protector is Map) {
    for (final key in ['pingUrl']) {
      if (protector[key] is! String) fail('"protectorConfig.$key" must be String');
    }
    for (final key in ['needToLogin', 'inAppBrowserInterceptor']) {
      if (protector[key] is! bool) fail('"protectorConfig.$key" must be bool');
    }
    final group = protector['sessionGroup'];
    if (group != null && group is! String) {
      fail('"protectorConfig.sessionGroup" must be String or null');
    }
  }

  final filters = config['filters'];
  if (filters is List) {
    final known = GalleryFilterModes.values.toSet();
    for (final filter in filters) {
      final type = filter is Map ? filter['type'] : null;
      if (!known.contains(type)) {
        fail('filter type $type is not supported by the interpreter in current '
            'app releases (${known.join(', ')})');
        return;
      }
    }
  }

  try {
    ConfigInfo.fromJson(config);
  } catch (e) {
    fail('the app cannot parse config.json: $e');
  }
}

void _collectConfigApiFeatures(
    Map<String, dynamic> config, List<_ApiFeature> features) {
  for (final entry in _configFieldApiVersions.entries) {
    if (config[entry.key] != null) {
      features.add(_ApiFeature('config field "${entry.key}"', entry.value));
    }
  }
  final downloadConfig = config['downloadConfig'];
  if (downloadConfig is! Map) {
    return;
  }
  for (final entry in _downloadConfigFieldApiVersions.entries) {
    if (downloadConfig[entry.key] != null) {
      features.add(_ApiFeature(
          'config field "downloadConfig.${entry.key}"', entry.value));
    }
  }
}

void _validateScript(File file, Set<String> functions, Set<String> visited,
    List<_ApiFeature> features, void Function(String) fail) {
  final path = file.absolute.path;
  if (!visited.add(path)) {
    return;
  }
  final label = _basename(path);
  final source = file.readAsStringSync();
  final code = _blankStringsAndComments(source);

  final List<String> parsed;
  try {
    parsed = Parser(source: source)
        .parse()
        .functions
        .map((f) => f.functionName)
        .toList();
  } catch (e) {
    fail('$label does not parse: ${_firstLine(e.toString())}');
    return;
  }
  functions.addAll(parsed);

  for (final match in _topLevelFunction.allMatches(code)) {
    final declared = match.group(1)!;
    if (!parsed.contains(declared)) {
      fail('$label: function $declared is never parsed; check the syntax above '
          'line ${_lineOf(code, match.start)}');
      break;
    }
  }

  for (final match in _incrementBeforeContinue.allMatches(code)) {
    fail('$label:${_lineOf(code, match.start)}: "${match.group(1)}" is '
        'incremented before continue, which skips the next iteration');
  }

  for (final match in _apiFunctionCall.allMatches(code)) {
    final function = match.group(1)!;
    features.add(
        _ApiFeature('$label calls $function', _functionApiVersions[function]!));
  }

  for (final match in _import.allMatches(code)) {
    final module = source.substring(match.start, match.end);
    final name = _import.firstMatch(module)!.group(1)!;
    if (moduleFactories.containsKey(name)) {
      continue;
    }
    final moduleApiVersion = _moduleApiVersions[name];
    if (moduleApiVersion != null) {
      features.add(_ApiFeature('$label imports "$name"', moduleApiVersion));
      continue;
    }
    if (!name.startsWith('./') && !name.startsWith('../')) {
      fail('$label imports "$name", which is neither a builtin module in the '
          'supported interpreter nor a relative path');
      continue;
    }
    final imported = File('${file.parent.path}/$name.capyscript');
    if (!imported.existsSync()) {
      fail('$label imports "$name", but ${imported.path} does not exist');
      continue;
    }
    _validateScript(imported, functions, visited, features, fail);
  }
}

String _blankStringsAndComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? source.length : end + 2;
      out.write(source.substring(i, stop).replaceAll(RegExp(r'[^\n]'), ' '));
      i = stop;
      continue;
    }
    if (c == '"' || c == "'" || c == '`') {
      var j = i + 1;
      while (j < source.length && source[j] != c) {
        if (c != '`' && source[j] == r'\' && j + 1 < source.length) {
          j++;
        }
        j++;
      }
      final stop = j < source.length ? j + 1 : source.length;
      out.write(c);
      out.write(source.substring(i + 1, stop - 1).replaceAll(RegExp(r'[^\n]'), ' '));
      if (stop > i + 1) out.write(c);
      i = stop;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

int _lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

String _firstLine(String text) => text.split('\n').first.trim();
