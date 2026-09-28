# CI internals

The four workflows, what each owns and when it runs, are in
[`AGENTS.md`](../AGENTS.md) § CI. This file is the part you only need when changing CI
itself or chasing a preview that did not appear.

## The composite actions

Three actions carry what the workflows share: `.github/actions/setup-gno` (clone gno
master outside the workspace, build the requested binaries, cached on the upstream SHA,
Go version from `tools/go.mod`), `.github/actions/previews-sync` (rewrite one subfolder of
the previews site and push, retrying when a parallel job moved the branch) and
`.github/actions/pr-comment` (upsert the one sticky comment and delete any duplicate).

## Previews

The two published snapshots, and how to render one locally, are in AGENTS.md § CI. Both
come from `gnocontracts preview`, which boots **one** gnodev on the whole workspace and
crawls it. Three things there are load-bearing:

1. **gnodev is given every package, not just the ones being rendered.** A package is
   versioned in its `gnomod.toml`, not in its directory path, so gnodev cannot find
   `gno.land/p/moul/authz/v0` by walking to `p/moul/authz/v0`. Lazy loading makes the
   whole workspace cost the same as one package: 193 packages, node ready in 9s.
2. **`GNOROOT` is the stdlib-only view**, so a preview resolves dependencies out of
   committed `vendor/` exactly as lint and test do. `preview` builds the view itself, from
   the real checkout, which is what stops GNOROOT ever naming the view while the view is
   being built out of it (that killed a CI run with `failed loading stdlib "errors"`).
3. **A changed pure package previews its dependents.** The reverse-import walk is
   transitive, so touching `p/moul/md` renders every realm that renders markdown. The
   previous preview rendered nothing at all for a diff touching no `r/`.

Bounds, because a realm may link as many pages as it likes: at most 25 packages on a pull
request (changed ones are never dropped, and the comment says how many were), 10
render-argument pages per package, and never a `$state`, `$help&func=`, `$download` or
`:args$source` page. Without the argument budget one realm (`romannumdemo`, a page per
numeral) produced 4,065 of 5,437 pages and 220 MB of 323 MB on its own. Every page is
`noindex, nofollow`: each is a near-duplicate of a real gno.land page.

The site lives in
[moul/gno-contracts-previews](https://github.com/moul/gno-contracts-previews), not in this
repository's `gh-pages`: the main snapshot is 103 MB rewritten on every push, and this
repository is one everybody clones. That branch is rewritten as a single orphan commit
each time, so the previews repository only ever holds the site as it is now. Publishing
needs the `PREVIEWS_DEPLOY_KEY` secret, the private half of a write deploy key there; a
fork has no secrets, so it renders nothing and is linked to nothing.

**A preview outlives its pull request by 21 days.** Nothing is deleted when one closes:
the sticky comment embeds the before/after screenshots *by URL*, so evicting on close
leaves every merged pull request with a comment full of broken images (it did, until
2026-09-21). The hourly `main` run is the only thing that shrinks the site: it drops
previews whose pull request closed more than `grace-days` ago, and if the site is still
over `max-total-mb` (700) it gives up the closed ones early, oldest first. **A preview of
an open pull request is never evicted**, whatever the budget says; if only those are left,
the run warns instead.
