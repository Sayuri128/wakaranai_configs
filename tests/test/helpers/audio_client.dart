import 'package:capyscript/api_clients/audio_api_client.dart';

import 'extension_host_helpers.dart';
import 'scraper_helpers.dart';
import 'script_bundle.dart';

AudioApiClient audioClientFor(
  String extensionDirectory, {
  Map<String, Object?> preferences = const {},
}) {
  final config = loadConfig(extensionDirectory);
  return AudioApiClient(
    code: bundleScript(scriptPath('$extensionDirectory/main.capyscript')),
    host: hostFor(config, preferences: preferences),
  );
}
