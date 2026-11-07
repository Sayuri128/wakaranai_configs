import 'package:capyscript/Interpreter/interpreter.dart';
import 'package:capyscript/modules/http/http_module.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/config_info/preferences/extension_preference.dart';
import 'package:capyscript/modules/waka_models/models/config_info/request_policy/request_policy.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/scraper_helpers.dart';

const String primaryApiHost = 'https://api.cdnlibs.org';
const List<String> alternativeMirrors = [
  'https://api.lib.social',
  'https://api2.mangalib.me',
];
const Map<String, String> siteIds = {
  'manga/manga_lib': '1',
  'manga/hentai_lib': '4',
};

Future<List<MangaGalleryView>> galleryThrough(
  String extensionDirectory,
  ConfigInfo config, {
  Map<String, Object?> preferences = const {},
  RequestPolicy? requestPolicy,
  String uidSuffix = '',
}) async {
  final interpreter = Interpreter.fromFile(
    path: scriptPath('$extensionDirectory/main.capyscript'),
    host: hostFor(
      config,
      preferences: preferences,
      requestPolicy: requestPolicy,
      uidSuffix: uidSuffix,
    ),
  );
  final httpModule = interpreter.builtinModule(HttpModule.module_name);
  if (httpModule is HttpModule) {
    httpModule.setHeaders({'site-id': siteIds[extensionDirectory]!});
  }
  return ((await interpreter.runFunction(
    'getGallery',
    arguments: {'page': 1, 'query': '', 'filters': []},
  )) as List)
      .cast<MangaGalleryView>();
}

void describeMirrors(String extensionDirectory) {
  group(extensionDirectory, () {
    late ConfigInfo config;

    setUpAll(() {
      config = loadConfig(extensionDirectory);
    });

    test('declares the API host and its mirrors', () {
      expect(config.apiVersion, 2);
      expect(config.requestPolicy?.mirrors, [
        primaryApiHost,
        ...alternativeMirrors,
      ]);
      expect(config.protectorConfig?.sessionGroup, 'lib_social');
    });

    test('every alternative mirror serves the same gallery', () async {
      final firstPages = <String, List<String>>{};
      for (final mirror in alternativeMirrors) {
        final gallery = await galleryThrough(
          extensionDirectory,
          config,
          preferences: {ExtensionPreference.mirrorKey: mirror},
          uidSuffix: mirror,
        );
        expect(gallery, isNotEmpty, reason: mirror);
        firstPages[mirror] = gallery.map((item) => item.uid).toList();
      }
      expect(
        firstPages[alternativeMirrors.last],
        firstPages[alternativeMirrors.first],
      );
    });

    test('an unreachable mirror fails over to the next one', () async {
      final gallery = await galleryThrough(
        extensionDirectory,
        config,
        requestPolicy: const RequestPolicy(mirrors: [
          'https://127.0.0.1:9',
          'https://api.lib.social',
          primaryApiHost,
        ]),
        preferences: {ExtensionPreference.mirrorKey: 'https://127.0.0.1:9'},
        uidSuffix: '-failover',
      );
      expect(gallery, isNotEmpty);
    });
  });
}

void main() {
  describeMirrors('manga/manga_lib');
  describeMirrors('manga/hentai_lib');
}
