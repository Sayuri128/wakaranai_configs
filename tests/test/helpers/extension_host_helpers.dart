import 'dart:convert';
import 'dart:io';

import 'package:capyscript/api_clients/host/extension_host.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/config_info/request_policy/request_policy.dart';
import 'package:test/test.dart';

import 'scraper_helpers.dart';

class MapPreferences extends ExtensionPreferencesProvider {
  final Map<String, Object?> values;

  const MapPreferences(this.values);

  @override
  Future<Object?> getPreference(String key) async => values[key];
}

ConfigInfo loadConfig(String extensionDirectory) {
  final file = File(scriptPath('$extensionDirectory/config.json'));
  return ConfigInfo.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  );
}

String readScript(String extensionDirectory) {
  return File(
    scriptPath('$extensionDirectory/main.capyscript'),
  ).readAsStringSync();
}

ExtensionHost hostFor(
  ConfigInfo config, {
  Map<String, Object?> preferences = const {},
  RequestPolicy? requestPolicy,
  String uidSuffix = '',
}) {
  return ExtensionHost(
    extensionUid: '${config.uid}$uidSuffix',
    preferenceDefinitions: config.preferences,
    preferences: MapPreferences(preferences),
    requestPolicy: requestPolicy ?? config.requestPolicy,
  );
}

Future<SourceError> expectSourceError(
  Future<Object?> Function() call,
  SourceErrorKind kind,
) async {
  try {
    await call();
  } on SourceError catch (error) {
    expect(error.kind, kind, reason: error.toString());
    return error;
  }
  fail('expected a ${kind.name} source error');
}
