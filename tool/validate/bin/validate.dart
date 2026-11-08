import 'dart:convert';
import 'dart:io';

import 'package:capyscript/AST/function_declaration/ast_funcation_declaration_node.dart';
import 'package:capyscript/modules/abstract/base_module.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/parser/parser.dart';

const Map<String, int> _categoryTypes = {
  'manga': 0,
  'anime': 1,
  'novel': 2,
  'audio': 3,
};

const Map<String, List<String>> _requiredFunctions = {
  'manga': ['getGallery', 'getConcrete', 'getPages'],
  'anime': ['getGallery', 'getConcrete'],
  'novel': ['getGallery', 'getConcrete', 'getChapterText'],
  'audio': ['getGallery', 'getConcrete', 'getAudioSources'],
};

class _NewerCategory {
  const _NewerCategory({
    required this.label,
    required this.modelsModule,
    required this.minAppVersion,
  });

  final String label;
  final String modelsModule;
  final String minAppVersion;
}

const int _newerCategoryApiVersion = 2;
const Map<String, _NewerCategory> _newerCategories = {
  'novel': _NewerCategory(
    label: 'novel',
    modelsModule: 'novel_models',
    minAppVersion: '0.4.0',
  ),
  'audio': _NewerCategory(
    label: 'audio',
    modelsModule: 'audio_models',
    minAppVersion: '0.4.0',
  ),
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
  'pagination': 2,
};

const Map<String, int> _galleryParameterApiVersions = {
  'pageSize': 2,
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
  final imports = <String>{};
  final newer = _newerCategories[category];
  _validateScript(script, functions, imports, <String>{}, features,
      {if (newer != null) newer.modelsModule}, fail);
  if (newer != null && !imports.contains(newer.modelsModule)) {
    fail('main.capyscript must import "${newer.modelsModule}"');
  }
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
  _validatePreferences(config['preferences'], fail);
  _validateRequestPolicy(config['requestPolicy'], fail);
  _validateFeeds(config['feeds'], fail);
  _validatePagination(config['pagination'], fail);
  _validateDownloadConfig(config['downloadConfig'], fail);
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
    final timeout = protector['pageLoadTimeoutSeconds'];
    if (timeout != null && (timeout is! int || timeout < 5 || timeout > 120)) {
      fail('"protectorConfig.pageLoadTimeoutSeconds" must be an integer from '
          '5 to 120');
    }
  }
  _validateContentKinds(config['contentKinds'], fail);
  _validatePricing(config['pricing'], fail);
  _validateSourceType(config['sourceType'], fail);
  final multiInstance = config['multiInstance'];
  if (multiInstance != null && multiInstance is! bool) {
    fail('"multiInstance" must be true or false');
  }
  final newer = _newerCategories[category];
  if (newer != null) {
    _validateNewerCategoryConfig(config, newer, fail);
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

  if (newer != null) {
    _validateNewerCategorySharedFields(config, newer, fail);
    return;
  }
  try {
    ConfigInfo.fromJson(config);
  } catch (e) {
    fail('the app cannot parse config.json: $e');
  }
}

void _validateNewerCategoryConfig(Map<String, dynamic> config,
    _NewerCategory newer, void Function(String) fail) {
  if (config['apiVersion'] != _newerCategoryApiVersion) {
    fail('${newer.label} extensions must declare "apiVersion": '
        '$_newerCategoryApiVersion');
  }
  final minAppVersion = config['minAppVersion'];
  if (minAppVersion is! String) {
    fail('${newer.label} extensions must declare "minAppVersion" (at least '
        '${newer.minAppVersion}, the first app release with ${newer.label} '
        'support)');
    return;
  }
  if (_semanticVersion.hasMatch(minAppVersion) &&
      _compareVersions(minAppVersion, newer.minAppVersion) < 0) {
    fail('"minAppVersion" $minAppVersion is older than '
        '${newer.minAppVersion}, the first app release with ${newer.label} '
        'support');
  }
}

void _validateNewerCategorySharedFields(Map<String, dynamic> config,
    _NewerCategory newer, void Function(String) fail) {
  final mangaShaped = Map<String, dynamic>.of(config)
    ..['type'] = _categoryTypes['manga'];
  try {
    ConfigInfo.fromJson(mangaShaped);
  } catch (e) {
    fail('the fields ${newer.label} configs share with manga configs do not '
        'parse: $e');
  }
}

int _compareVersions(String left, String right) {
  final leftParts = left.split('.').map(int.parse).toList();
  final rightParts = right.split('.').map(int.parse).toList();
  for (var index = 0; index < leftParts.length; index++) {
    final difference = leftParts[index] - rightParts[index];
    if (difference != 0) {
      return difference;
    }
  }
  return 0;
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

const Set<String> _preferenceTypes = {
  'toggle',
  'select',
  'multiselect',
  'text',
  'number',
};
const Set<String> _optionPreferenceTypes = {'select', 'multiselect'};
const Set<String> _preferenceFields = {
  'key',
  'type',
  'title',
  'summary',
  'default',
  'options',
  'secret',
};
const Set<String> _requestPolicyFields = {
  'rateLimit',
  'defaultHeaders',
  'userAgent',
  'mirrors',
};
const Set<String> _rateLimitFields = {'requests', 'perSeconds'};
const Set<String> _feedFields = {'id', 'title'};
const Set<String> _paginationFields = {'pageSizes', 'defaultPageSize'};
const int _maxPageSize = 500;
const String _reservedPreferencePrefix = '__';
const int _maxSegmentConcurrency = 8;

bool _isNonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty;

void _rejectUnknownFields(Map<dynamic, dynamic> object, Set<String> known,
    String path, void Function(String) fail) {
  for (final field in object.keys) {
    if (!known.contains(field)) {
      fail('"$path.$field" is not a known field (${known.join(', ')})');
    }
  }
}

void _validatePreferences(Object? preferences, void Function(String) fail) {
  if (preferences == null) {
    return;
  }
  if (preferences is! List) {
    fail('"preferences" must be a list');
    return;
  }
  final keys = <String>{};
  for (var index = 0; index < preferences.length; index++) {
    final preference = preferences[index];
    final path = 'preferences[$index]';
    if (preference is! Map) {
      fail('"$path" must be an object');
      continue;
    }
    _rejectUnknownFields(preference, _preferenceFields, path, fail);
    final key = preference['key'];
    if (!_isNonEmptyString(key)) {
      fail('"$path.key" must be a non-empty string');
    } else if ((key as String).startsWith(_reservedPreferencePrefix)) {
      fail('"$path.key" "$key" uses the reserved "$_reservedPreferencePrefix" '
          'prefix');
    } else if (!keys.add(key)) {
      fail('"$path.key" "$key" is declared more than once');
    }
    final type = preference['type'];
    if (!_preferenceTypes.contains(type)) {
      fail('"$path.type" must be one of ${_preferenceTypes.join(', ')}');
    }
    if (!_isNonEmptyString(preference['title'])) {
      fail('"$path.title" must be a non-empty string');
    }
    final summary = preference['summary'];
    if (summary != null && summary is! String) {
      fail('"$path.summary" must be a string or null');
    }
    final secret = preference['secret'];
    if (secret != null && (secret is! bool || type != 'text')) {
      fail('"$path.secret" must be a bool and is only allowed on text '
          'preferences');
    }
    final optionValues = _validatePreferenceOptions(
        preference['options'], type, path, fail);
    final defaultValue = preference['default'];
    if (defaultValue != null) {
      _validatePreferenceDefault(defaultValue, type, optionValues, path, fail);
    }
  }
}

Set<String> _validatePreferenceOptions(
    Object? options, Object? type, String path, void Function(String) fail) {
  final values = <String>{};
  final needsOptions = _optionPreferenceTypes.contains(type);
  if (options == null) {
    if (needsOptions) {
      fail('"$path.options" is required for a $type preference');
    }
    return values;
  }
  if (options is! List) {
    fail('"$path.options" must be a list');
    return values;
  }
  if (!needsOptions) {
    if (options.isNotEmpty) {
      fail('"$path.options" only applies to select and multiselect '
          'preferences');
    }
    return values;
  }
  if (options.isEmpty) {
    fail('"$path.options" must not be empty for a $type preference');
  }
  for (var index = 0; index < options.length; index++) {
    final option = options[index];
    final optionPath = '$path.options[$index]';
    if (option is! Map) {
      fail('"$optionPath" must be an object with value and label');
      continue;
    }
    _rejectUnknownFields(option, const {'value', 'label'}, optionPath, fail);
    final value = option['value'];
    if (value is! String) {
      fail('"$optionPath.value" must be a string');
    } else if (!values.add(value)) {
      fail('"$optionPath.value" "$value" is listed more than once');
    }
    if (!_isNonEmptyString(option['label'])) {
      fail('"$optionPath.label" must be a non-empty string');
    }
  }
  return values;
}

void _validatePreferenceDefault(Object defaultValue, Object? type,
    Set<String> optionValues, String path, void Function(String) fail) {
  final defaultPath = '$path.default';
  switch (type) {
    case 'toggle':
      if (defaultValue is! bool) {
        fail('"$defaultPath" must be a bool for a toggle preference');
      }
    case 'text':
      if (defaultValue is! String) {
        fail('"$defaultPath" must be a string for a text preference');
      }
    case 'number':
      if (defaultValue is! num) {
        fail('"$defaultPath" must be a number for a number preference');
      }
    case 'select':
      if (defaultValue is! String) {
        fail('"$defaultPath" must be a string for a select preference');
      } else if (!optionValues.contains(defaultValue)) {
        fail('"$defaultPath" "$defaultValue" is not one of the option values');
      }
    case 'multiselect':
      if (defaultValue is! List) {
        fail('"$defaultPath" must be a list of option values for a '
            'multiselect preference');
        return;
      }
      final seen = <String>{};
      for (final value in defaultValue) {
        if (value is! String || !optionValues.contains(value)) {
          fail('"$defaultPath" entry $value is not one of the option values');
        } else if (!seen.add(value)) {
          fail('"$defaultPath" lists $value more than once');
        }
      }
  }
}

void _validateRequestPolicy(Object? policy, void Function(String) fail) {
  if (policy == null) {
    return;
  }
  if (policy is! Map) {
    fail('"requestPolicy" must be an object or null');
    return;
  }
  _rejectUnknownFields(policy, _requestPolicyFields, 'requestPolicy', fail);
  _validateRateLimit(policy['rateLimit'], fail);
  final defaultHeaders = policy['defaultHeaders'];
  if (defaultHeaders != null) {
    if (defaultHeaders is! Map) {
      fail('"requestPolicy.defaultHeaders" must map header names to strings');
    } else {
      for (final entry in defaultHeaders.entries) {
        if (!_isNonEmptyString(entry.key) || entry.value is! String) {
          fail('"requestPolicy.defaultHeaders.${entry.key}" must map a header '
              'name to a string');
        }
      }
    }
  }
  final userAgent = policy['userAgent'];
  if (userAgent != null && !_isNonEmptyString(userAgent)) {
    fail('"requestPolicy.userAgent" must be a non-empty string or null');
  }
  _validateMirrors(policy['mirrors'], fail);
}

void _validateRateLimit(Object? rateLimit, void Function(String) fail) {
  if (rateLimit == null) {
    return;
  }
  if (rateLimit is! Map) {
    fail('"requestPolicy.rateLimit" must be an object or null');
    return;
  }
  _rejectUnknownFields(
      rateLimit, _rateLimitFields, 'requestPolicy.rateLimit', fail);
  final requests = rateLimit['requests'];
  if (requests is! int || requests <= 0) {
    fail('"requestPolicy.rateLimit.requests" must be a positive integer');
  }
  final perSeconds = rateLimit['perSeconds'];
  if (perSeconds is! num || perSeconds <= 0) {
    fail('"requestPolicy.rateLimit.perSeconds" must be a positive number');
  }
}

void _validateMirrors(Object? mirrors, void Function(String) fail) {
  if (mirrors == null) {
    return;
  }
  if (mirrors is! List) {
    fail('"requestPolicy.mirrors" must be a list of base URLs');
    return;
  }
  final seen = <String>{};
  String? sharedPath;
  for (var index = 0; index < mirrors.length; index++) {
    final mirror = mirrors[index];
    final path = 'requestPolicy.mirrors[$index]';
    final problem = _mirrorProblem(mirror);
    if (problem != null) {
      fail('"$path" $problem');
      continue;
    }
    final mirrorUrl = mirror as String;
    final uri = Uri.parse(mirrorUrl);
    if (!seen.add(mirrorUrl.toLowerCase())) {
      fail('"$path" $mirrorUrl is listed more than once');
    }
    if (sharedPath == null) {
      sharedPath = uri.path;
    } else if (uri.path != sharedPath) {
      fail('"$path" $mirrorUrl has path "${uri.path}" but the first mirror has '
          '"$sharedPath"; mirrors are swapped as prefixes, so their paths must '
          'match');
    }
  }
}

String? _mirrorProblem(Object? mirror) {
  if (mirror is! String || mirror.isEmpty || mirror.trim() != mirror) {
    return 'must be a URL string without surrounding spaces';
  }
  final Uri uri;
  try {
    uri = Uri.parse(mirror);
  } on FormatException {
    return '$mirror is not a valid URL';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '$mirror must be an absolute http(s) URL';
  }
  if (uri.host.isEmpty) {
    return '$mirror has no host';
  }
  if (uri.userInfo.isNotEmpty) {
    return '$mirror must not carry credentials';
  }
  if (uri.hasQuery || uri.hasFragment) {
    return '$mirror must not have a query or fragment';
  }
  if (mirror.endsWith('/')) {
    return '$mirror must not end with "/"; mirrors are prefixes of request URLs';
  }
  return null;
}

void _validateFeeds(Object? feeds, void Function(String) fail) {
  if (feeds == null) {
    return;
  }
  if (feeds is! List) {
    fail('"feeds" must be a list');
    return;
  }
  final ids = <String>{};
  for (var index = 0; index < feeds.length; index++) {
    final feed = feeds[index];
    final path = 'feeds[$index]';
    if (feed is! Map) {
      fail('"$path" must be an object with id and title');
      continue;
    }
    _rejectUnknownFields(feed, _feedFields, path, fail);
    final id = feed['id'];
    if (!_isNonEmptyString(id)) {
      fail('"$path.id" must be a non-empty string');
    } else if (!ids.add(id as String)) {
      fail('"$path.id" "$id" is declared more than once');
    }
    if (!_isNonEmptyString(feed['title'])) {
      fail('"$path.title" must be a non-empty string');
    }
  }
}

final RegExp _contentKind = RegExp(r'^[a-z][a-z0-9-]*$');

void _validateSourceType(Object? sourceType, void Function(String) fail) {
  if (sourceType == null) {
    return;
  }
  if (sourceType != 'website' &&
      sourceType != 'self-hosted' &&
      sourceType != 'official') {
    fail('"sourceType" must be "website", "self-hosted" or "official"');
  }
}

void _validatePricing(Object? pricing, void Function(String) fail) {
  if (pricing == null) {
    return;
  }
  if (pricing != 'free' && pricing != 'partial' && pricing != 'paid') {
    fail('"pricing" must be "free", "partial" or "paid"');
  }
}

void _validateContentKinds(Object? kinds, void Function(String) fail) {
  if (kinds == null) {
    return;
  }
  if (kinds is! List || kinds.isEmpty) {
    fail('"contentKinds" must be a non-empty list of lowercase strings');
    return;
  }
  final seen = <String>{};
  for (final kind in kinds) {
    if (kind is! String || !_contentKind.hasMatch(kind)) {
      fail('"contentKinds" entry $kind must be a lowercase word such as '
          '"anime" or "movie"');
    } else if (!seen.add(kind)) {
      fail('"contentKinds" lists "$kind" twice');
    }
  }
}

void _validatePagination(Object? pagination, void Function(String) fail) {
  if (pagination == null) {
    return;
  }
  if (pagination is! Map) {
    fail('"pagination" must be an object with pageSizes and defaultPageSize');
    return;
  }
  _rejectUnknownFields(pagination, _paginationFields, 'pagination', fail);
  final pageSizes = pagination['pageSizes'];
  final sizes = <int>{};
  if (pageSizes is! List || pageSizes.isEmpty) {
    fail('"pagination.pageSizes" must be a non-empty list of integers from 1 '
        'to $_maxPageSize');
  } else {
    for (var index = 0; index < pageSizes.length; index++) {
      final size = pageSizes[index];
      final path = 'pagination.pageSizes[$index]';
      if (size is! int || size < 1 || size > _maxPageSize) {
        fail('"$path" must be an integer from 1 to $_maxPageSize');
      } else if (!sizes.add(size)) {
        fail('"$path" $size is listed more than once');
      }
    }
  }
  final defaultPageSize = pagination['defaultPageSize'];
  if (defaultPageSize is! int) {
    fail('"pagination.defaultPageSize" must be an integer');
  } else if (sizes.isNotEmpty && !sizes.contains(defaultPageSize)) {
    fail('"pagination.defaultPageSize" $defaultPageSize is not one of '
        '"pagination.pageSizes"');
  }
}

void _validateDownloadConfig(
    Object? downloadConfig, void Function(String) fail) {
  if (downloadConfig == null) {
    return;
  }
  if (downloadConfig is! Map) {
    fail('"downloadConfig" must be an object or null');
    return;
  }
  for (final field in ['pageDelayMs', 'chapterDelayMs', 'episodeDelayMs']) {
    final delay = downloadConfig[field];
    if (delay != null && (delay is! int || delay < 0)) {
      fail('"downloadConfig.$field" must be an integer of at least 0');
    }
  }
  final concurrency = downloadConfig['segmentConcurrency'];
  if (concurrency != null &&
      (concurrency is! int ||
          concurrency < 1 ||
          concurrency > _maxSegmentConcurrency)) {
    fail('"downloadConfig.segmentConcurrency" must be an integer from 1 to '
        '$_maxSegmentConcurrency');
  }
}

void _validateScript(
    File file,
    Set<String> functions,
    Set<String> imports,
    Set<String> visited,
    List<_ApiFeature> features,
    Set<String> categoryModules,
    void Function(String) fail) {
  final path = file.absolute.path;
  if (!visited.add(path)) {
    return;
  }
  final label = _basename(path);
  final source = file.readAsStringSync();
  final code = _blankStringsAndComments(source);

  final List<ASTFunctionDeclarationNode> declarations;
  try {
    declarations = Parser(source: source).parse().functions;
  } catch (e) {
    fail('$label does not parse: ${_firstLine(e.toString())}');
    return;
  }
  final parsed = declarations.map((f) => f.functionName).toList();
  functions.addAll(parsed);
  _collectGalleryParameterApiFeatures(declarations, label, features);

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
    imports.add(name);
    if (moduleFactories.containsKey(name) || categoryModules.contains(name)) {
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
    _validateScript(imported, functions, imports, visited, features,
        categoryModules, fail);
  }
}

void _collectGalleryParameterApiFeatures(
    List<ASTFunctionDeclarationNode> declarations,
    String label,
    List<_ApiFeature> features) {
  for (final declaration in declarations) {
    if (declaration.functionName != 'getGallery') {
      continue;
    }
    for (final parameter in declaration.parameters) {
      final apiVersion = _galleryParameterApiVersions[parameter.paramName];
      if (apiVersion != null) {
        features.add(_ApiFeature(
            '$label getGallery parameter "${parameter.paramName}"',
            apiVersion));
      }
    }
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
