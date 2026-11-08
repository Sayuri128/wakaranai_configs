import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/api_clients/source_error.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/ficbook';
const String multiPartWork = '5528601';
const String singlePartWork = '4195954';
const String singlePart = '4195954/10876161';
const String notedPart = '019e3af9-307c-7f96-b5fd-52cdcd15a073/41995067';
const String narutoFandomId = '98';
const Set<String> safeRatings = {'G', 'PG-13', 'R'};

void main() {
  late ConfigInfo config;
  late NovelApiClient client;
  late MangaConcreteView multiPart;
  late MangaConcreteView singlePartConcrete;

  setUpAll(() async {
    silenceInterpreterLogs();
    config = loadConfig(extensionDirectory);
    client = novelClientFor(extensionDirectory);
    multiPart = await client.getConcrete(uid: multiPartWork, data: {});
    singlePartConcrete = await client.getConcrete(uid: singlePartWork, data: {});
  });

  GalleryFilterMultipleOfMultiple filterFor(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterMultipleOfMultiple;
  }

  FilterDataMultipleOfMultiple selection(String param, List<String> values) {
    return FilterDataMultipleOfMultiple(
      selected: [values],
      filter: filterFor(param),
    );
  }

  Set<String> ratingsOf(List items) {
    return items.map((item) => item.data['rating'].toString()).toSet();
  }

  group('config', () {
    test('is a novel extension that hides adult works by default', () {
      expect(config.type, ConfigInfoType.NOVEL);
      expect(config.apiVersion, 2);
      expect(config.minAppVersion, '1.0.0');
      expect(config.nsfw, isFalse);
      expect(config.feeds.map((feed) => feed.id), ['popular', 'updates', 'awarded']);
      final showAdult =
          config.preferences.firstWhere((preference) => preference.key == 'showAdult');
      expect(showAdult.defaultValue, false);
      expect(config.requestPolicy?.userAgent, isNull);
      expect(config.requestPolicy?.rateLimit, isNotNull);
    });
  });

  group('getGallery', () {
    test('lists every feed without adult works', () async {
      for (final feed in config.feeds) {
        final items = await client.getGallery(
          page: 1,
          query: '',
          filters: [],
          feed: feed.id,
          pageSize: 0,
        );
        expect(items.length, greaterThanOrEqualTo(15), reason: feed.id);
        for (final item in items) {
          expect(item.title, isNotEmpty);
          expect(item.uid, isNot(contains('/')));
          expect(item.uid, isNot(contains('?')));
          expect(safeRatings, contains(item.data['rating']), reason: item.uid);
          if (item.cover.isNotEmpty) {
            expect(item.cover, startsWith('https://'));
          }
        }
      }
    });

    test('sorts the updates feed differently from the popular one', () async {
      final popular = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'popular', pageSize: 0);
      final updates = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'updates', pageSize: 0);
      expect(
        updates.map((item) => item.uid).toList(),
        isNot(popular.map((item) => item.uid).toList()),
      );
    });

    test('pages through results and stops after the last site page', () async {
      final first = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'popular', pageSize: 0);
      final second = await client.getGallery(
          page: 2, query: '', filters: [], feed: 'popular', pageSize: 0);
      expect(second, isNotEmpty);
      expect(
        second.map((item) => item.uid).toSet().intersection(
              first.map((item) => item.uid).toSet(),
            ),
        isEmpty,
      );
      final beyond = await client.getGallery(
          page: 101, query: '', filters: [], feed: 'popular', pageSize: 0);
      expect(beyond, isEmpty);
    });

    test('shows adult works once the preference allows them', () async {
      final adultClient =
          novelClientFor(extensionDirectory, preferences: {'showAdult': true});
      final items = await adultClient.getGallery(
          page: 1, query: '', filters: [], feed: 'popular', pageSize: 0);
      expect(ratingsOf(items).intersection({'NC-17', 'NC-21'}), isNotEmpty);
    });

    test('searches by title', () async {
      final items = await client.getGallery(
          page: 1,
          query: 'Свадебные колокола',
          filters: [],
          feed: 'popular',
          pageSize: 0);
      expect(items.map((item) => item.uid), contains(singlePartWork));
    });

    test('filters by rating and keeps adult ratings behind the preference', () async {
      final general = await client.getGallery(
        page: 1,
        query: '',
        filters: [selection('ratings', ['5'])],
        feed: 'popular',
        pageSize: 0,
      );
      expect(general, isNotEmpty);
      expect(ratingsOf(general), {'G'});

      final adultOnly = await client.getGallery(
        page: 1,
        query: '',
        filters: [selection('ratings', ['8', '9'])],
        feed: 'popular',
        pageSize: 0,
      );
      expect(adultOnly, isNotEmpty);
      expect(safeRatings.containsAll(ratingsOf(adultOnly)), isTrue);
    });

    test('filters by fandom and direction', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [
          selection('fandom_ids', [narutoFandomId]),
          selection('directions', ['1']),
        ],
        feed: 'popular',
        pageSize: 0,
      );
      expect(items, isNotEmpty);
      final concrete = await client.getConcrete(uid: items.first.uid, data: {});
      expect(concrete.tags, contains('Naruto'));
      expect(concrete.tags, contains('Джен'));
    });
  });

  group('getConcrete', () {
    test('has details and metadata', () {
      expect(multiPart.title, isNotEmpty);
      expect(multiPart.description, isNotEmpty);
      expect(multiPart.description, contains('Размер:'));
      expect(multiPart.tags, contains('G'));
      expect(multiPart.status, isNot(MangaStatus.UNDEFINED));
      expect(multiPart.authors, isNotEmpty);
      expect(multiPart.url, 'https://ficbook.net/readfic/$multiPartWork');
      expect(multiPart.year, isNotNull);
    });

    test('lists every part in order', () {
      final parts = multiPart.groups.single.elements;
      expect(parts.length, greaterThan(10));
      for (final part in parts) {
        expect(part.uid, startsWith('$multiPartWork/'));
        expect(part.title, isNotEmpty);
        expect(part.timestamp, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00\+03:00$')));
      }
      expect(parts.map((part) => part.uid).toSet(), hasLength(parts.length));
    });

    test('gives a single-part work one chapter with its part id', () {
      final part = singlePartConcrete.groups.single.elements.single;
      expect(part.uid, singlePart);
      expect(part.title, 'Часть 1');
      expect(part.timestamp, startsWith('2016-03-20T16:26'));
      expect(singlePartConcrete.status, MangaStatus.RELEASED);
    });

    test('reports a missing work as not found', () async {
      await expectSourceError(
        () => client.getConcrete(uid: '999999999999', data: {}),
        SourceErrorKind.notFound,
      );
    });
  });

  group('getChapterText', () {
    test('turns a part into paragraphs', () async {
      final part = multiPart.groups.single.elements.first;
      final content = await client.getChapterText(uid: part.uid, data: {});
      expect(content.html, startsWith('<p>'));
      expect(content.html, isNot(contains('id="content"')));
      expect(content.html.length, greaterThan(1000));
      expect(content.title, part.title);
    });

    test('reads a single-part work by its part id or its work id', () async {
      final byPart = await client.getChapterText(uid: singlePart, data: {});
      final byWork = await client.getChapterText(uid: singlePartWork, data: {});
      expect(byPart.html, contains('ЛедиБаг'));
      expect(byWork.html, byPart.html);
    });

    test('wraps author notes and can leave them out', () async {
      final withNotes = await client.getChapterText(uid: notedPart, data: {});
      expect(withNotes.html, startsWith('<blockquote><p><strong>Примечания:</strong></p>'));
      expect(withNotes.html, contains('<hr><blockquote>'));
      final quietClient =
          novelClientFor(extensionDirectory, preferences: {'authorNotes': false});
      final withoutNotes = await quietClient.getChapterText(uid: notedPart, data: {});
      expect(withoutNotes.html, isNot(contains('<blockquote>')));
      expect(withoutNotes.html, startsWith('<p>'));
    });

    test('splits lines into paragraphs and keeps block markup', () async {
      final html = await client.interpreter.runFunction(
        'ficbookParagraphs',
        arguments: {
          'markup': 'first &amp; <i>line</i>\r\n\n  second line\n'
              '<p style="text-align: center;">***</p>\n&nbsp;\n&nbsp;&nbsp; third',
        },
      );
      expect(
        html,
        '<p>first &amp; <i>line</i></p><p>second line</p>'
        '<p style="text-align: center;">***</p><p>third</p>',
      );
    });

    test('parses russian dates', () async {
      final timestamp = await client.interpreter.runFunction(
        'ficbookTimestamp',
        arguments: {'rawDate': '5 мая 2023 г., 9:31'},
      );
      expect(timestamp, '2023-05-05T09:31:00+03:00');
    });
  });

  group('covers', () {
    test('load without extra headers on the gallery and the title page', () async {
      final adultClient =
          novelClientFor(extensionDirectory, preferences: {'showAdult': true});
      final items = await adultClient.getGallery(
          page: 1, query: '', filters: [], feed: 'popular', pageSize: 0);
      final withCover = items.firstWhere((item) => item.cover.isNotEmpty);
      expect(withCover.cover, startsWith('https://assets.teinon.net/fanfic-covers/'));
      expect(await probeContentType(withCover.cover, {}), startsWith('image/'));
      final concrete = await adultClient.getConcrete(uid: withCover.uid, data: {});
      expect(concrete.cover, startsWith('https://assets.teinon.net/fanfic-covers/'));
      expect(await probeContentType(concrete.cover, {}), startsWith('image/'));
    });
  });
}
