import 'dart:convert';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/config_info/preferences/extension_preference.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/manga_gallery_view.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String extensionDirectory = 'manga/manga_dex';
const String missingMangaId = '00000000-0000-4000-8000-000000000000';

MangaApiClient clientWith(
  ConfigInfo config, [
  Map<String, Object?> preferences = const {},
]) {
  return MangaApiClient(
    code: readScript(extensionDirectory),
    host: hostFor(config, preferences: preferences),
  );
}

Future<String> mangaWithChaptersIn(List<String> languages) async {
  final query = languages.map((code) => 'translatedLanguage[]=$code').join('&');
  final response = await http
      .get(Uri.parse(
          'https://api.mangadex.org/chapter?limit=100&$query&order[readableAt]=desc'))
      .timeout(const Duration(seconds: 30));
  expect(response.statusCode, 200);
  final chapters = (jsonDecode(response.body) as Map)['data'] as List;
  final languagesByManga = <String, Set<String>>{};
  for (final chapter in chapters) {
    final language = chapter['attributes']['translatedLanguage'] as String;
    for (final relation in chapter['relationships'] as List) {
      if (relation['type'] == 'manga') {
        languagesByManga
            .putIfAbsent(relation['id'] as String, () => <String>{})
            .add(language);
      }
    }
  }
  return languagesByManga.entries
      .firstWhere((entry) => entry.value.length == languages.length,
          orElse: () => languagesByManga.entries.first)
      .key;
}

void main() {
  late ConfigInfo config;
  late MangaApiClient defaultClient;

  setUpAll(() {
    config = loadConfig(extensionDirectory);
    defaultClient = clientWith(config);
  });

  group('config', () {
    test('declares api 2 with feeds and preferences', () {
      expect(config.apiVersion, 2);
      expect(config.feeds.map((feed) => feed.id), ['popular', 'latest']);
      final languages = config.preferences
          .firstWhere((preference) => preference.key == 'chapterLanguages');
      expect(languages.type, ExtensionPreferenceType.multiselect);
      expect(languages.effectiveDefault, ['en']);
      expect(languages.options.map((option) => option.value), contains('uk'));
    });
  });

  group('feeds', () {
    late List<MangaGalleryView> popular;
    late List<MangaGalleryView> popularPage2;
    late List<MangaGalleryView> latest;

    setUpAll(() async {
      popular = await defaultClient.getGallery(page: 1, feed: 'popular');
      popularPage2 = await defaultClient.getGallery(page: 2, feed: 'popular');
      latest = await defaultClient.getGallery(page: 1, feed: 'latest');
    });

    test('popular lists titles with covers', () {
      expect(popular, hasLength(20));
      for (final item in popular) {
        expect(item.title, isNotEmpty);
        expect(item.cover, startsWith('https://uploads.mangadex.org/covers/'));
      }
    });

    test('popular pages do not overlap', () {
      final firstPage = popular.map((item) => item.uid).toSet();
      expect(popularPage2.map((item) => item.uid).toSet().intersection(firstPage),
          isEmpty);
    });

    test('latest lists recently updated titles once each', () {
      expect(latest, isNotEmpty);
      final uids = latest.map((item) => item.uid).toList();
      expect(uids.toSet(), hasLength(uids.length));
      expect(latest.where((item) => item.latestChapter != null), isNotEmpty);
    });

    test('latest differs from popular', () {
      expect(latest.first.uid, isNot(popular.first.uid));
    });

    test('a search query overrides the feed', () async {
      final results = await defaultClient.getGallery(
          page: 1, query: 'one piece', feed: 'latest');
      expect(results, isNotEmpty);
      expect(
        results.any((item) => item.title.toLowerCase().contains('one piece')),
        isTrue,
      );
    });
  });

  group('chapter languages', () {
    test('a single language keeps the Default group', () async {
      final mangaId = await mangaWithChaptersIn(['en']);
      final concrete = await defaultClient.getConcrete(uid: mangaId, data: {});
      expect(concrete.groups.map((group) => group.title), ['Default']);
    });

    test('several languages split chapters into one group per language',
        () async {
      final mangaId = await mangaWithChaptersIn(['en', 'uk']);
      final client = clientWith(config, {
        'chapterLanguages': ['uk', 'en'],
      });
      final concrete = await client.getConcrete(uid: mangaId, data: {});
      final titles = concrete.groups.map((group) => group.title).toList();
      expect(titles, isNotEmpty);
      expect(titles.toSet().difference({'Ukrainian', 'English'}), isEmpty);
      if (titles.length == 2) {
        expect(titles, ['Ukrainian', 'English']);
      }
      final englishOnly =
          await defaultClient.getConcrete(uid: mangaId, data: {});
      final chapterUids = concrete.groups
          .expand((group) => group.elements)
          .map((chapter) => chapter.uid)
          .toSet();
      for (final chapter in englishOnly.groups.first.elements) {
        expect(chapterUids, contains(chapter.uid));
      }
    });

    test('only-translated titles narrow the catalogue to the chosen language',
        () async {
      final client = clientWith(config, {
        'chapterLanguages': ['uk'],
        'onlyTranslatedTitles': true,
      });
      final ukrainian = await client.getGallery(page: 1, feed: 'popular');
      final everything = await defaultClient.getGallery(page: 1, feed: 'popular');
      expect(ukrainian, isNotEmpty);
      expect(ukrainian.map((item) => item.uid).toList(),
          isNot(everything.map((item) => item.uid).toList()));
    });
  });

  group('typed errors', () {
    test('a missing title is reported as not found', () async {
      await expectSourceError(
        () => defaultClient.getConcrete(uid: missingMangaId, data: {}),
        SourceErrorKind.notFound,
      );
    });

    test('a missing chapter is reported as not found', () async {
      await expectSourceError(
        () => defaultClient.getPages(uid: missingMangaId, data: {}),
        SourceErrorKind.notFound,
      );
    });
  });
}
