# `gno.land/p/moul/wiki/v0`

A Wikipedia-shaped wiki engine: namespaced titles, an append-only revision
chain, wikilinks with backlinks, categories, redirects, protection levels,
line diffs, and markdown rendering.

Pure: no realm globals, no chain imports. Every mutating call takes the author
address, the wall clock and the block height from its caller, so the engine is
unit-testable off-chain and the realm keeps all the authority.

Live demo: [`gno.land/r/moul/wiki/v0`](../../../../r/moul/wiki/v0).

## The storage model

A realm write locks a storage deposit proportional to the bytes it adds
(100ugnot per byte, `gnolang/gno#6171`). A wiki that kept every revision in
full would therefore charge its editors rent on the whole history forever: at
5 KB per revision that is 0.5 GNOT locked per edit, permanently.

This engine keeps a **content-addressed spine plus a bounded body window**:

| kept forever, per revision | kept only inside the window |
|---|---|
| id, parent, kind, author, time, height, summary, byte size, **SHA-256 of the body**, minor flag | the body text |

Roughly 200 bytes per revision regardless of article size, plus the bodies of
the newest `Retention` revisions of each page (3 by default).

An evicted body is not lost. Its bytes were an argument of the transaction
that wrote it, so they are still in the chain's transaction history, and the
retained hash proves which bytes were the real ones. The realm stops paying
rent for deep history; the archive lives where archives belong. What you lose
is the ability to diff or revert to an evicted revision from inside the realm,
and both failures are explicit (`ErrBodyEvicted`) rather than silent.

`Purge` evicts every body of a page at once and returns the bytes released. It
is the lever for content that must stop being served out of realm state; it
cannot and does not remove the transactions that wrote it.

## Rendering untrusted markdown

Article bodies are attacker-controlled markdown rendered by gnoweb, so the
render path has a fixed order:

1. `sanitize.BlockRich` the body (`gno.land/p/nt/markdown/sanitize/v0`).
2. **Then** rewrite the wikilinks.

Not the other way around. The sanitizer escapes every `[`, so `[[Gno land]]`
becomes `\[\[Gno land\]\]` in its output; a rewriter that ran first would hand
the markdown links it just generated to the escaper and every link on the wiki
would render as literal text. That is why `ScanLinks` takes its delimiters as
parameters: indexing scans the raw body, rendering scans the escaped one.

The blank lines `BlockRich` adds around its output are load-bearing, not
cosmetic. A CommonMark HTML block of type 6 or 7 is not escaped in any mode,
and without the surrounding blank line it would absorb the realm chrome
appended after the body.

Two layers, two jobs: `sanitize` stops markdown **structure** injection, and
gnoweb's own link extension stops **URL scheme** abuse (`javascript:` and
friends). Neither replaces the other.

The title charset is narrower than MediaWiki's for the same reason. `/`, `|`,
`#`, `*`, `[`, `<`, `?`, `%` and `&` are rejected rather than escaped, which
keeps `Title.String`, `Title.Slug` and the rendered link byte-identical.
`TestTitleSurvivesTheRenderPipeline` pins that coupling end to end.

## Determinism and gas

`Render` runs under `maxGasQuery` (3e9 in `gno.land/pkg/sdk/vm/keeper.go`),
which a reader cannot raise, so an unbounded render makes a page permanently
unreadable. Three bounds keep it away from that ceiling:

- `MaxBody` (32 KiB) caps a revision, and therefore caps every render.
- `DiffMaxLines` (80) caps the changed region a diff computes exactly. The
  common prefix and suffix are trimmed first, so an ordinary edit to a long
  article still diffs exactly; past the bound a diff degrades to a block
  replacement instead of failing.
- Histories, indexes and listings are paginated by the caller.

Measured with `gno test -v` on gno master.184 (2026-09-17): the diff of a 33 KB
body against itself plus one line costs 691M gas, and the article render of a
33 KB body with links costs 693M, each about 23% of the ceiling.

Everything else follows gno's determinism rules: no map iteration anywhere in a
render path, `avl` for every ordered index, and namespace keys padded by hand
because `ufmt` has no width flags (`ufmt.Sprintf("%02d", 7)` silently returns
`"7"`, which would sort `Talk` between two main-namespace pages).

## Wiki syntax

| syntax | meaning |
|---|---|
| `[[Target]]` | link, rendered from the canonical title |
| `[[Target\|label]]` | link with a display label |
| `[[Category:Name]]` | join a category; removed from the text flow |
| `[[:Category:Name]]` | link to the category instead of joining it |
| `#REDIRECT [[Target]]` on line 1 | redirect, followed one hop only |

Links to pages that do not exist yet are still indexed, so creating a page
immediately knows who was already pointing at it.

## Known limits

- `Page.Revision(id)` is a linear scan of the page's history.
- Redirects are followed one hop; chains are not resolved.
- Templates and transclusion are not implemented.
- There is no full-text search, and there cannot be a cheap one on chain.
