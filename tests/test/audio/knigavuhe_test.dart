import 'package:capyscript/api_clients/audio_api_client.dart';
import 'package:capyscript/modules/waka_models/models/manga/manga_concrete_view/manga_status.dart';
import 'package:test/test.dart';

import '../helpers/audio_client.dart';

const String tajnaBulavki = 'tajjna-bulavki-1';

void main() {
  late AudioApiClient client;

  setUpAll(() {
    client = audioClientFor('audio/knigavuhe');
  });

  test('feeds list books and page forward', () async {
    for (final feed in ['new', 'popular', 'rating']) {
      final items = await client.getGallery(page: 1, feed: feed);
      expect(items, isNotEmpty, reason: feed);
      expect(items.every((item) => item.cover.startsWith('https://')), isTrue);
    }
    final first = await client.getGallery(page: 1, feed: 'new');
    final second = await client.getGallery(page: 2, feed: 'new');
    expect(second.first.uid, isNot(first.first.uid));
  });

  test('search finds books', () async {
    final results = await client.getGallery(page: 1, query: 'Тайна булавки');
    expect(results.map((item) => item.uid), contains(tajnaBulavki));
  });

  test('a book lists its tracks with direct mp3 sources', () async {
    final concrete = await client.getConcrete(uid: tajnaBulavki, data: {});
    expect(concrete.title, 'Тайна булавки');
    expect(concrete.authors, contains('Эдгар Уоллес'));
    expect(concrete.tags, contains('Читает: Юрий Яковлев-Суханов'));
    expect(concrete.status, MangaStatus.RELEASED);
    final tracks = concrete.groups.single.elements;
    expect(tracks, hasLength(9));
    expect(tracks.first.title, endsWith('01'));
    final sources = await client.getAudioSources(uid: tracks.first.uid, data: tracks.first.data);
    expect(sources.single.url, endsWith('.mp3'));
    expect(sources.single.duration, greaterThan(1000));
  });
}
