# Wakaranai Configs

The official extension repository for the [Wakaranai](https://github.com/Sayuri128/wakaranai) manga, anime and light novel reader. Extensions are written in [Capyscript](https://github.com/Sayuri128/capyscript) and loaded by the app at runtime — no app update is needed to add or fix a source.

## Extensions

| Extension | Type | Language | Notes |
|---|---|---|---|
| MangaLib | Manga | Russian | Requires login; shares the session with HentaiLib |
| HentaiLib | Manga (NSFW) | Russian | Requires login |
| RanobeLib | Novel | Russian | Light and web novels; chapters grouped by translation branch; shares the MangaLib login |
| MangaDex | Manga | English | Status, demographic and content-rating filters |
| NHentai | Manga (NSFW) | Multi | |
| Manga/in/UA | Manga | Ukrainian | |
| MangaRead | Manga | English | Madara engine |
| Mangasushi | Manga | English | Madara engine |
| LHTranslation | Manga | English | Madara engine |
| LilyManga | Manga (NSFW) | English | Madara engine |
| Anitube.in.ua | Anime | Ukrainian | |
| UAFlix | Video | Ukrainian | Movies, series, cartoons and anime; section filter |
| Цікава Ідея | Video | Ukrainian | Dub team catalogue: movies, series, animation |
| AnimeVost | Anime | Russian | AnimeVost dubs; latest and ongoing feeds; genre, type or year filter; HD and SD MP4 |
| YummyAnime | Anime | Russian | Public api.yani.tv API; dubs grouped per player; Kodik, CVH and Aksor play natively, Alloha in the web player; optional application token |
| ReManga | Manga | Russian | Translation branches; type, status, genre and age filters |
| Honey Manga | Manga | Ukrainian | Type, status and genre filters; paid early-access chapters hidden |
| Zenko | Manga | Ukrainian | Type, status and genre filters; chapters grouped by team |
| Komga | Manga | Multi | Your own Komga server; set the address and an API key or email and password in the extension settings |
| Kavita | Manga | Multi | Your own Kavita server; set the address and API key in the extension settings |
| OPDS | Manga | Multi | Any OPDS 1.x catalog with page streaming (OPDS-PSE); set the catalog address in the extension settings |
| Suwayomi | Manga | Multi | Your own Suwayomi (Tachidesk) server: its library, plus browsing and searching one of its installed sources; set the address, an optional login and the source in the extension settings |
| Jellyfin | Video | Multi | Your own Jellyfin server: movies and shows with seasons, original-file or converted streams, subtitles and audio tracks; set the address and a username and password or an API key in the extension settings |

## Structure

```
manga/<extension>/   config.json, main.capyscript, logo.png
anime/<extension>/   same layout
novel/<extension>/   same layout, for light novels and web novels
shared/              Capyscript code imported by several extensions
index.json           generated list of all configs, read by the app
tool/                index generator and local dev server
tests/               integration tests for each extension
```

- `config.json` — metadata: `uid`, `name`, `logoUrl`, `type` (`0` manga, `1` anime, `2` novel), `nsfw`, `language`, `version`, `searchAvailable`, an optional `protectorConfig` for sites behind challenges or logins, and optional gallery `filters`.
- `main.capyscript` — implements `getGallery`, `getConcrete`, `getPages` / video lists / `getChapterText`, and optionally `passProtector`. Shared code is pulled in with relative imports such as `import "../../shared/lib_social_api";`.
- Novel extensions (`novel/`) import `novel_models`, which has the manga builders plus `buildNovelChapter`, and return the chapter body as HTML from `getChapterText(uid, data)` instead of page images. They only run on app releases with novel support, so they must declare `"apiVersion": 2` and a `minAppVersion` of at least `0.4.0`.
- `shared/madara.capyscript` — a generic engine for WordPress sites on the Madara theme. A Madara site is a `config.json` plus a `main.capyscript` that defines `madaraSettings()` (at least `baseUrl`) and delegates `getGallery` / `getConcrete` / `getPages` / `getImageHeaders` to `madaraGetGallery` / `madaraGetConcrete` / `madaraGetPages` / `madaraGetImageHeaders`. Optional settings: `galleryMode` (`search` or `ajax`), `chaptersMode` (`auto`, `page`, `ajax`, `admin-ajax`), `defaultOrder`, `gallerySelector`, `descriptionSelector`, `pageSelector`, `pageExclude` (URL substrings to drop), `chapterGroupTitle`, `userAgent`.

The full extension authoring guide lives in the app repo: [docs/guides/extensions.md](https://github.com/Sayuri128/wakaranai/blob/master/docs/guides/extensions.md).

## Development

```bash
dart tool/build_index.dart                          # regenerate index.json after changing a config
dart tool/build_index.dart --check                  # fail if index.json is out of date
(cd tool/validate && dart pub get)                  # once
dart run tool/validate/bin/validate.dart .          # validate every config and script
dart tool/serve.dart                                # serve extensions locally on :8080 for the app's LOCAL_REPOSITORY_URL
cd tests && dart test                               # run integration tests (hits the real sites)
cd tests && dart run bin/health.dart                # smoke-test every extension end to end (--only <dir>, --browser)
```

Extensions configured through their settings (Komga, Kavita, OPDS, Suwayomi, Jellyfin) need preferences in the health check: pass each one as `--pref <key>=<value>`, for example `dart run bin/health.dart --only komga --pref serverUrl=http://localhost:25600 --pref apiKey=<key>`. The values apply to every extension in the run, so combine them with `--only`.

The validator parses every config with the app's own model classes and every script with the interpreter that current app releases ship (pinned in `tool/validate/pubspec.yaml`), so it rejects syntax, modules or filter types that existing app builds can't run. That interpreter predates novels, so novel configs and scripts get structural checks instead: type `2`, api version, `minAppVersion`, the `novel_models` import and `getChapterText`. It also checks uids, logos, required functions and the `i = i + 1; continue;` bug. Run it and `build_index.dart --check` before pushing.

## Custom repositories

Wakaranai can load extensions from any GitHub repository (and branch) with this layout — fork this repo, add your sources, and add the fork as a source in the app.
