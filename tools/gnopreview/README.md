# gnopreview (POC for #43)

Extracts a **static gnoweb preview** of this repo's realms so a PR can show what its
realms render as — without a live chain.

## How it works

1. Boots **gnodev** on the selected realm directories (deps resolve from the repo +
   gno examples).
2. Crawls each realm's gnoweb page over HTTP, plus every `/public/` asset it
   references (recursing through CSS `url()`s).
3. Rewrites absolute `/public/`, `/r/`, `/p/` URLs to **relative** paths, so the
   result is a self-contained static tree that works from any subfolder.

Output:

```
_preview/
  index.html                     # list of previewed realms
  public/                        # gnoweb css/js/fonts/favicon
  r/moul/hello/v1/index.html     # one page per realm
  ...
```

## Local usage

```sh
# build a matching gnodev once (the released one may be stale vs. your gno master)
( cd $GNOROOT/contribs/gnodev && GOTOOLCHAIN=auto go build -o /tmp/gnodev . )

# render some realms
GNOROOT=~/p/gh/gnoland/gno GNODEV=/tmp/gnodev \
  python3 tools/gnopreview/gnopreview.py --out _preview ./r/moul/hello ./r/moul/...

# browse
( cd _preview && python3 -m http.server 8777 )   # open http://localhost:8777/
```

Selectors are repo-relative (`./...` default). Only non-draft, non-`ignore` realms
are previewed (pure packages have no `Render`).

## CI

`.github/workflows/pr-preview.yml` builds gnodev from gno master, renders the realms
**changed in the PR**, and publishes them to `gh-pages/pr-<N>/`
(`https://<owner>.github.io/gno-contracts/pr-<N>/`), leaving a sticky comment. The
subfolder is deleted when the PR closes.

**Requires GitHub Pages enabled** with source = `gh-pages` branch. Building gnodev in
CI is heavy (a few minutes) — acceptable for a preview job; could later be cached or
replaced by a prebuilt image.

## Known POC limitations

- Cross-realm navigation and the gnoweb chrome links (Search/Apps/Docs) point at
  absolute site paths and won't resolve inside the preview — only the realm pages
  themselves are captured.
- Interactive actions (the "Actions" tab / tx forms) are static — no signer.
- Renders the realm's *initial* state (post-`init`), not any parameterized path yet.
