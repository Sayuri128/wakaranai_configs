import 'package:capyscript/api_clients/novel_api_client.dart';
import 'package:capyscript/modules/waka_models/models/config_info/config_info.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_concrete_view.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/data/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_gallery_view/filters/multiple_of_multiple/multiple_of_multiple.dart';
import 'package:test/test.dart';

import '../helpers/extension_host_helpers.dart';
import '../helpers/script_bundle.dart';
import '../helpers/self_hosted_helpers.dart';

const String extensionDirectory = 'novel/ranobe_lib';
const String guestMirror = 'https://api.lib.social';
const String omniscientReader = '26690--omniscient-readers-viewpoint-novel';
const String documentBranch = '17824';
const String htmlBranch = '17823';
const String koreaTypeId = '11';

void main() {
  late ConfigInfo config;
  late NovelApiClient client;
  late MangaConcreteView concrete;

  setUpAll(() async {
    config = loadConfig(extensionDirectory);
    client = novelClientFor(
      extensionDirectory,
      preferences: {'__mirror': guestMirror},
    );
    concrete = await client.getConcrete(uid: omniscientReader, data: {});
  });

  GalleryFilterMultipleOfMultiple filterFor(String param) {
    return config.filters.firstWhere((filter) => filter.param == param)
        as GalleryFilterMultipleOfMultiple;
  }

  group('config', () {
    test('is a novel extension for the first app release with novels', () {
      expect(config.type, ConfigInfoType.NOVEL);
      expect(config.apiVersion, 2);
      expect(config.minAppVersion, '1.0.0');
      expect(config.protectorConfig?.sessionGroup, 'lib_social');
      expect(config.requestPolicy?.defaultHeaders['Site-Id'], '3');
      expect(config.feeds.map((feed) => feed.id), ['popular', 'updates', 'new']);
    });
  });

  group('getGallery', () {
    test('lists every feed', () async {
      for (final feed in config.feeds) {
        final items = await client.getGallery(
          page: 1,
          query: '',
          filters: [],
          feed: feed.id,
          pageSize: 20,
        );
        expect(items, hasLength(20), reason: feed.id);
        for (final item in items) {
          expect(item.title, isNotEmpty);
          expect(item.cover, startsWith('https://'));
          expect(item.data['site'], 3);
        }
      }
    });

    test('sorts the updates feed differently from the popular one', () async {
      final popular = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'popular', pageSize: 20);
      final updates = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'updates', pageSize: 20);
      expect(
        updates.map((item) => item.uid).toList(),
        isNot(popular.map((item) => item.uid).toList()),
      );
    });

    test('pages with the chosen page size', () async {
      final first = await client.getGallery(
          page: 1, query: '', filters: [], feed: 'popular', pageSize: 20);
      final second = await client.getGallery(
          page: 2, query: '', filters: [], feed: 'popular', pageSize: 20);
      expect(second, isNotEmpty);
      expect(
        second.map((item) => item.uid).toSet().intersection(
              first.map((item) => item.uid).toSet(),
            ),
        isEmpty,
      );
    });

    test('searches', () async {
      final items = await client.getGallery(
          page: 1, query: 'Всеведущего', filters: [], feed: '', pageSize: 0);
      expect(items.map((item) => item.uid), contains(omniscientReader));
    });

    test('filters by type', () async {
      final items = await client.getGallery(
        page: 1,
        query: '',
        filters: [
          FilterDataMultipleOfMultiple(
            selected: [
              [koreaTypeId],
            ],
            filter: filterFor('types'),
          ),
        ],
        feed: 'popular',
        pageSize: 20,
      );
      expect(items, isNotEmpty);
      for (final item in items) {
        expect((item.data['type'] as Map)['id'].toString(), koreaTypeId);
      }
    });
  });

  group('getConcrete', () {
    test('has details and metadata', () {
      expect(concrete.title, isNotEmpty);
      expect(concrete.cover, startsWith('https://'));
      expect(concrete.description, isNotEmpty);
      expect(concrete.tags, isNotEmpty);
      expect(concrete.url, 'https://ranobelib.me/ru/book/$omniscientReader');
      expect(concrete.status, isNot(MangaStatus.UNDEFINED));
      expect(concrete.authors, isNotEmpty);
      expect(concrete.year, 2018);
    });

    test('groups chapters by translation branch, largest first', () {
      expect(concrete.groups.length, greaterThan(1));
      final titles = concrete.groups.map((group) => group.title).toList();
      expect(titles.toSet(), hasLength(titles.length));
      for (var index = 1; index < concrete.groups.length; index++) {
        expect(
          concrete.groups[index].elements.length,
          lessThanOrEqualTo(concrete.groups[index - 1].elements.length),
        );
      }
      final uids = concrete.groups
          .expand((group) => group.elements)
          .map((chapter) => chapter.uid)
          .toList();
      expect(uids.toSet(), hasLength(uids.length));
      expect(uids, contains('$omniscientReader/0/1/$documentBranch'));
      expect(uids, contains('$omniscientReader/0/1/$htmlBranch'));
    });

    test('chapters have titles and timestamps', () {
      final chapter = concrete.groups.first.elements.first;
      expect(chapter.title, startsWith('Том 1 Глава 0'));
      expect(chapter.timestamp, isNotNull);
    });
  });

  group('getChapterText', () {
    test('converts a document chapter to html with images', () async {
      final content = await client.getChapterText(
        uid: '$omniscientReader/0/1/$documentBranch',
        data: {},
      );
      expect(content.html, startsWith('<p>'));
      expect(content.html, isNot(contains('"type"')));
      expect(content.html, contains('<strong>'));
      final image = RegExp("<img src='([^']+)'>").firstMatch(content.html);
      expect(image, isNotNull);
      final imageUrl = image!.group(1)!;
      expect(imageUrl, startsWith('https://ranobelib.me/uploads/ranobe/'));
      final headers = await client.getImageHeaders(uid: omniscientReader, data: {});
      expect(await probeContentType(imageUrl, headers), startsWith('image/'));
    });

    test('keeps an html chapter as html', () async {
      final content = await client.getChapterText(
        uid: '$omniscientReader/0/1/$htmlBranch',
        data: {},
      );
      expect(content.html, startsWith('<p'));
      expect(content.html.length, greaterThan(1000));
    });

    test('escapes text and keeps marks, breaks and images', () async {
      final html = await client.interpreter.runFunction(
        'ranobeLibChapterHtml',
        arguments: {
          'chapterData': {
            'content': {
              'type': 'doc',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'a < b & c'},
                    {'type': 'hardBreak'},
                    {
                      'type': 'text',
                      'text': 'marked',
                      'marks': [
                        {'type': 'bold'},
                        {'type': 'italic'},
                        {'type': 'underline'},
                        {'type': 'strike'},
                      ],
                    },
                  ],
                },
                {
                  'type': 'image',
                  'attrs': {
                    'images': [
                      {'image': 'picture'},
                    ],
                  },
                },
                {'type': 'horizontalRule'},
                {'type': 'paragraph'},
              ],
            },
            'attachments': [
              {'name': 'picture', 'url': '/uploads/ranobe/1/picture.jpg'},
            ],
          },
        },
      );
      expect(
        html,
        "<p>a &lt; b &amp; c<br><s><u><em><strong>marked</strong></em></u></s></p>"
        "<p><img src='https://ranobelib.me/uploads/ranobe/1/picture.jpg'></p>"
        '<hr><p></p>',
      );
    });

    test('resolves relative images in an html chapter', () async {
      final html = await client.interpreter.runFunction(
        'ranobeLibChapterHtml',
        arguments: {
          'chapterData': {
            'content': '<p>text</p><img src="/uploads/ranobe/1/a.png">',
            'attachments': [],
          },
        },
      );
      expect(html, '<p>text</p><img src="https://ranobelib.me/uploads/ranobe/1/a.png">');
    });
  });

  group('getImageHeaders', () {
    test('sends the site referer that covers need', () async {
      final headers = await client.getImageHeaders(uid: omniscientReader, data: {});
      expect(headers['Referer'], 'https://ranobelib.me/');
      expect(await probeContentType(concrete.cover, headers), startsWith('image/'));
    });
  });
}
