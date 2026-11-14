# Wakaranai Configs

The official extensions for [Wakaranai](https://github.com/Sayuri128/wakaranai), an Android app for manga, anime, novels and audiobooks. Each extension is a `config.json` plus a script written in [Capyscript](https://github.com/Sayuri128/capyscript). The app downloads them from this repository and runs them on the device, so adding or fixing a source doesn't need an app update.

Most extensions use extension API 2 (preferences, feeds, pagination, typed errors) and need **Wakaranai 1.0.0 or newer**. Older app builds can't run them; update the app from [its releases](https://github.com/Sayuri128/wakaranai/releases/latest).

## Extensions

### Manga

| Extension | Language | Notes |
|---|---|---|
| MangaDex | Multi | Popular and latest feeds; chapter languages and page size in the extension settings; status, demographic and content-rating filters |
| MangaLib | Russian | Requires login; shares the session with HentaiLib and RanobeLib |
| ReManga | Russian | Translation branches; type, status, genre and age filters; paid chapters hidden |
| Honey Manga | Ukrainian | Type, status and genre filters; paid early-access chapters hidden |
| Zenko | Ukrainian | Type, status and genre filters; chapters grouped by team |
| Manga/in/UA | Ukrainian | |
| MangaPill | English | Latest chapters, trending and browse feeds; type, status and genre filters |
| MangaNato | English | Mangakakalot/MangaNato catalogue; latest, popular, new and completed feeds; genre filter; no search (the site blocks it) |
| MangaRead | English | Madara engine |
| Mangasushi | English | Madara engine |
| LHTranslation | English | Madara engine |
| Dynasty Scans (NSFW) | English | Yuri series, anthologies, doujins and issues; type, status and tag filters; optional NSFW hiding |
| LilyManga (NSFW) | English | Madara engine |
| HentaiLib (NSFW) | Russian | Requires login |
| SlashLib (NSFW) | Russian | Requires login, shares the MangaLib session; BL manga, manhwa and comics; popular, updates and new feeds; genre, tag, type, format, status and range filters |
| NHentai (NSFW) | Multi | |

### Video

| Extension | Language | Notes |
|---|---|---|
| AniLibria | Russian | AniLibria (AniLiberty) dubs; updates, popular, ongoing and new feeds; genre, type, season, year and status filters; 1080/720/480 HLS with opening and ending skips |
| AnimeVost | Russian | Latest and ongoing feeds; genre, type or year filter; HD and SD MP4 |
| YummyAnime | Russian | Public api.yani.tv API; dubs grouped per player; Kodik, CVH and Aksor play natively, Alloha in the web player; an optional application token can be set in the extension settings |
| Anime365 (paid) | Russian | Browsing is free, watching needs an Anime365 subscription (sign in through the in-app browser); subtitles and voiceovers grouped by team; latest, ongoing and top rated feeds |
| AniHub | Ukrainian | Recently updated, new episodes, popular, top rated and newly added feeds |
| Anitube.in.ua | Ukrainian | Player and dub preferences; opening and ending skips |
| UAFlix | Ukrainian | Movies, series, cartoons and anime; section filter |
| Цікава Ідея | Ukrainian | Dub team catalogue: movies, series, animation |

### Novels

| Extension | Language | Notes |
|---|---|---|
| RanobeLib | Russian | Light and web novels; chapters grouped by translation branch; shares the MangaLib login |
| Ficbook | Russian | Fanfiction and originals; direction, rating, status, fandom and genre filters; NC-17/NC-21 hidden unless enabled |

### Audiobooks

| Extension | Language | Notes |
|---|---|---|
| LibriVox | English | Public domain audiobooks; new releases and catalog feeds; each section is a track streamed from archive.org at 64 or 128 kbps |

### Self-hosted servers

Set the server address and credentials in the extension settings.

| Extension | Type | Notes |
|---|---|---|
| Komga | Manga | API key or email and password |
| Kavita | Manga | API key |
| Suwayomi | Manga | Its library, plus browsing and searching one of its installed sources; optional login |
| OPDS | Manga | Any OPDS 1.x catalog with page streaming (OPDS-PSE) |
| Jellyfin | Video | Movies and shows with seasons, original-file or converted streams, subtitles and audio tracks; username and password or an API key |

## Structure

```
manga/<extension>/   config.json, main.capyscript, logo.png
anime/<extension>/   same layout, for video
novel/<extension>/   same layout, for light novels and web novels
audio/<extension>/   same layout, for audiobooks
shared/              Capyscript code imported by several extensions
index.json           generated list of all configs, read by the app
tool/                index generator, validator and local dev server
tests/               integration tests for each extension
```

- `config.json`: `uid`, `name`, `logoUrl`, `type` (`0` manga, `1` video, `2` novel, `3` audiobook), `nsfw`, `language`, `version`, `apiVersion`, `minAppVersion`, `searchAvailable`, and optionally `pricing`, `sourceType`, `protectorConfig` (sites behind challenges or logins), `preferences`, `requestPolicy`, `feeds`, `pagination` and gallery `filters`.
- `main.capyscript`: implements `getGallery`, `getConcrete`, then `getPages` (manga), `getVideoSources` (video), `getChapterText` (novels) or `getAudioSources` (audiobooks), and optionally `passProtector`. Shared code comes in through relative imports such as `import "../../shared/lib_social_api";`.
- Extensions that use any API 2 feature declare `"apiVersion": 2` and `"minAppVersion": "1.0.0"`. Novel and audiobook extensions always need both, since older apps can't read those types.
- `shared/madara.capyscript`: a generic engine for WordPress sites on the Madara theme. A Madara site is a `config.json` plus a `main.capyscript` that defines `madaraSettings()` (at least `baseUrl`) and delegates `getGallery` / `getConcrete` / `getPages` / `getImageHeaders` to `madaraGetGallery` / `madaraGetConcrete` / `madaraGetPages` / `madaraGetImageHeaders`. Optional settings: `galleryMode` (`search` or `ajax`), `chaptersMode` (`auto`, `page`, `ajax`, `admin-ajax`), `defaultOrder`, `gallerySelector`, `descriptionSelector`, `pageSelector`, `pageExclude` (URL substrings to drop), `chapterGroupTitle`, `userAgent`.

The full authoring guide is in the app repository: [docs/guides/extensions.md](https://github.com/Sayuri128/wakaranai/blob/master/docs/guides/extensions.md).

## Development

```bash
dart tool/build_index.dart                          # regenerate index.json after changing a config
dart tool/build_index.dart --check                  # fail if index.json is out of date
(cd tool/validate && dart pub get)                  # once
dart run tool/validate/bin/validate.dart .          # validate every config and script
dart tool/serve.dart                                # serve extensions on :8080 for the app's LOCAL_REPOSITORY_URL
cd tests && dart test                               # integration tests (hit the real sites)
cd tests && dart run bin/health.dart                # smoke-test every extension end to end (--only <dir>, --browser)
```

Extensions configured through their settings (Komga, Kavita, OPDS, Suwayomi, Jellyfin) need preferences in the health check: pass each one as `--pref <key>=<value>`, for example `dart run bin/health.dart --only komga --pref serverUrl=http://localhost:25600 --pref apiKey=<key>`. The values apply to every extension in the run, so combine them with `--only`.

The validator parses every config with the app's own model classes and every script with a pinned interpreter (`tool/validate/pubspec.yaml`), so it rejects syntax, modules or filter types that app builds can't run. That interpreter predates novels and audiobooks, so those get structural checks instead: the type, `apiVersion`, `minAppVersion`, the models import and the required function. It also checks uids, logos, required functions and the `i = i + 1; continue;` bug. Run it and `build_index.dart --check` before pushing.

## Your own repository

Wakaranai can load extensions from any GitHub repository and branch with this layout. Fork this repository, add your sources, and add the fork as a source in the app's Explore tab.

## License

[Apache License 2.0](LICENSE)
