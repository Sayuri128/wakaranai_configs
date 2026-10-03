# Wakaranai Configs

The official extension repository for the [Wakaranai](https://github.com/Sayuri128/wakaranai) manga/anime reader. Extensions are written in [Capyscript](https://github.com/Sayuri128/capyscript) and loaded by the app at runtime — no app update is needed to add or fix a source.

## Extensions

| Extension | Type | Language | Notes |
|---|---|---|---|
| MangaLib | Manga | Russian | Requires login; shares the session with HentaiLib |
| HentaiLib | Manga (NSFW) | Russian | Requires login |
| MangaDex | Manga | English | Status, demographic and content-rating filters |
| NHentai | Manga (NSFW) | Multi | |
| Manga/in/UA | Manga | Ukrainian | |
| Anitube.in.ua | Anime | Ukrainian | |

## Structure

```
manga/<extension>/   config.json, main.capyscript, logo.png
anime/<extension>/   same layout
shared/              Capyscript code imported by several extensions
index.json           generated list of all configs, read by the app
tool/                index generator and local dev server
tests/               integration tests for each extension
```

- `config.json` — metadata: `uid`, `name`, `logoUrl`, `type` (`0` manga, `1` anime), `nsfw`, `language`, `version`, `searchAvailable`, an optional `protectorConfig` for sites behind challenges or logins, and optional gallery `filters`.
- `main.capyscript` — implements `getGallery`, `getConcrete`, `getPages` / video lists, and optionally `passProtector`. Shared code is pulled in with relative imports such as `import "../../shared/lib_social_api";`.

The full extension authoring guide lives in the app repo: [docs/guides/extensions.md](https://github.com/Sayuri128/wakaranai/blob/master/docs/guides/extensions.md).

## Development

```bash
dart tool/build_index.dart     # regenerate index.json after changing a config
dart tool/serve.dart           # serve extensions locally on :8080 for the app's LOCAL_REPOSITORY_URL
cd tests && dart test          # run integration tests (hits the real sites)
```

`index.json` is also regenerated automatically by CI on pushes to `main`.

## Custom repositories

Wakaranai can load extensions from any GitHub repository (and branch) with this layout — fork this repo, add your sources, and add the fork as a source in the app.
