import 'dart:io';

import 'package:capyscript/api_clients/manga_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';

const String citrusUid = 'series/citrus';
const String standaloneUid = 'chapters/a_day_in_the_life_of_nozoeli';
const String titleKindPattern = r'^(series|anthologies|doujins|issues|chapters)/';

void main() {
  late ConfigInfo config;
  late MangaApiClient client;

  setUpAll(() {
    config = loadConfig('manga/dynasty_scans');
    client = MangaApiClient(
      code: readScript('manga/dynasty_scans'),
      host: hostFor(config),
    );
  });

  MangaApiClient clientWith(Map<String, Object?> preferences) {
    return MangaApiClient(
      code: readScript('manga/dynasty_scans'),
      host: hostFor(config, preferences: preferences),
    );
  }

  GalleryFilterMultipleOfMultiple filterFor(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterMultipleOfMultiple;
  }

  test('declares api 2 with feeds and preferences', () {
    expect(config.feeds.map((feed) => feed.id),
        ['latest', 'series', 'anthologies', 'doujins', 'issues']);
    expect(config.preferences.map((preference) => preference.key),
        containsAll(['hideNsfw', 'volumeGroups', 'doujinPages']));
  });

  group('getGallery', () {
    test('latest feed lists one entry per title', () async {
      final items = await client.getGallery(page: 1, feed: 'latest');
      expect(items, isNotEmpty);
      final uids = items.map((item) => item.uid).toList();
      expect(uids.toSet().length, uids.length);
      for (final item in items) {
        expect(item.uid, matches(titleKindPattern));
        expect(item.title, isNotEmpty);
      }
      expect(
        items.where((item) => item.uid.startsWith('series/')).every(
            (item) => item.latestChapter != null),
        isTrue,
      );
    });

    test('series directory has absolute covers and pages', () async {
      final first = await client.getGallery(page: 1, feed: 'series');
      final second = await client.getGallery(page: 2, feed: 'series');
      expect(first, isNotEmpty);
      for (final item in first) {
        expect(item.uid, startsWith('series/'));
        expect(item.cover, startsWith('https://dynasty-scans.com/'));
      }
      expect(second.first.uid, isNot(first.first.uid));
    });

    test('doujin directory lists doujin sources', () async {
      final items = await client.getGallery(page: 1, feed: 'doujins');
      expect(items, isNotEmpty);
      expect(items.every((item) => item.uid.startsWith('doujins/')), isTrue);
    });

    test('searches series', () async {
      final results =
          await client.getGallery(page: 1, query: 'citrus', feed: 'latest');
      expect(results.map((item) => item.uid), contains(citrusUid));
    });

    test('filters by type and tag without a query', () async {
      final items = await client.getGallery(
        page: 1,
        feed: 'latest',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              ['Series'],
            ],
            filter: filterFor('classes'),
          ),
          FilterDataMultipleOfMultiple(
            selected: [
              ['5120'],
            ],
            filter: filterFor('with'),
          ),
        ],
      );
      expect(items, isNotEmpty);
      expect(items.every((item) => item.uid.startsWith('series/')), isTrue);
      expect(items.every((item) => item.tags.contains('Romance')), isTrue);
    });

    test('ends search results past the last page', () async {
      final items =
          await client.getGallery(page: 999, query: 'citrus', feed: 'latest');
      expect(items, isEmpty);
    });

    test('hides NSFW works from latest when asked', () async {
      final items = await clientWith({'hideNsfw': true})
          .getGallery(page: 1, feed: 'latest');
      expect(items, isNotEmpty);
      expect(items.any((item) => item.tags.contains('NSFW')), isFalse);
    });
  });

  group('series', () {
    late MangaConcreteView concrete;

    setUpAll(() async {
      concrete = await client.getConcrete(uid: citrusUid, data: {});
    });

    test('has details', () {
      expect(concrete.title, 'Citrus');
      expect(concrete.authors, contains('Saburouta'));
      expect(concrete.status, MangaStatus.RELEASED);
      expect(concrete.cover, startsWith('https://dynasty-scans.com/system/'));
      expect(concrete.tags, contains('Yuri'));
      expect(concrete.url, 'https://dynasty-scans.com/series/citrus');
    });

    test('lists chapters in one group with volumes', () {
      expect(concrete.groups, hasLength(1));
      final chapters = concrete.groups.first.elements;
      expect(chapters.length, greaterThan(40));
      expect(chapters.first.title, 'Vol. 1 Chapter 1: love affair!?');
      expect(chapters.first.number, 1);
      expect(chapters.first.volume, 1);
      expect(chapters.first.timestamp, isNotEmpty);
    });

    test('pages load with the image headers', () async {
      final chapter = concrete.groups.first.elements.first;
      final pages = await client.getPages(uid: chapter.uid, data: {});
      expect(pages.value, isNotEmpty);
      expect(pages.value.first, startsWith('https://dynasty-scans.com/'));
      final headers = await client.getImageHeaders(uid: chapter.uid, data: {});
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse(pages.value.first));
        headers.forEach(request.headers.set);
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(response.headers.contentType?.primaryType, 'image');
        await response.drain<void>();
      } finally {
        httpClient.close();
      }
    });
  });

  test('groups chapters by volume when asked', () async {
    final grouped = await clientWith({'volumeGroups': true})
        .getConcrete(uid: citrusUid, data: {});
    expect(grouped.groups.first.title, 'Volume 1');
    expect(grouped.groups.first.elements.first.title,
        'Chapter 1: love affair!?');
    expect(grouped.groups.length, greaterThan(5));
  });

  test('doujin sources list the newest doujins oldest first', () async {
    final doujin = await clientWith({'doujinPages': '1'})
        .getConcrete(uid: 'doujins/love_live', data: {});
    expect(doujin.title, 'Love Live!');
    final chapters = doujin.groups.first.elements;
    expect(chapters, hasLength(25));
    expect(chapters.first.timestamp!.compareTo(chapters.last.timestamp!),
        lessThanOrEqualTo(0));
  });

  test('standalone chapters become one-chapter titles', () async {
    final standalone =
        await client.getConcrete(uid: standaloneUid, data: {});
    expect(standalone.title, 'A Day in the Life of NozoEli');
    expect(standalone.cover, startsWith('https://dynasty-scans.com/system/'));
    expect(standalone.description, contains('Love Live!'));
    expect(standalone.groups.single.elements.single.uid,
        'a_day_in_the_life_of_nozoeli');
  });

  test('reports a missing title as not found', () async {
    await expectSourceError(
      () => client.getConcrete(uid: 'series/zzz_no_such_series_here', data: {}),
      SourceErrorKind.notFound,
    );
  });
}
