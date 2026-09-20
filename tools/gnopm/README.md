# gnopm

A package manager for gno workspaces. It keeps a package's **version in its
`gnomod.toml`** instead of in its directory name, records where every version's
source lives in a **`gnomod.lock`**, and materializes the versions that are no
longer in the working tree so that pinned imports still resolve.

```
p/alice/md/gnomod.toml     module = "gno.land/p/alice/md/v1"
p/alice/md/md.gno          edited in place
```

`p/alice/md/` publishes to `gno.land/p/alice/md/v1`. There is no `v1/`
directory, and there never was a `v0/` one either: `v0` is pinned in
`gnomod.lock` to a commit, and `gnopm sync` rebuilds it under `.gnopm/` for
anything that still imports it.

## Why a directory should not carry the version

A gno package path ends in its version (`gno.land/p/alice/md/v0`), so the
obvious layout mirrors the path and puts each version in its own directory.
Bumping then means copying the directory and editing the copy.

**git cannot pair a copy.** The review diff of a version bump becomes a set of
added files with no content diff at all, which is backwards: a bump is by
definition the compatibility change that most needs reviewing, and it is the one
change you cannot see. `git log --follow`, `git blame` and `git bisect` all stop
at the copy too.

gnopm removes the copy. The toolchain already reads the version from the module
line, so the directory does not have to repeat it.

> Verified against gno master: a directory named `zzz/` declaring
> `gno.land/p/probe/foo/v1` is resolved by a sibling importing that path, and an
> import absent from the workspace genuinely fails to resolve, so resolution
> really happens rather than being masked by a later error. Dot-directories are
> scanned, which is what makes `.gnopm/` work.

## Two halves, borrowed

| half | prior art | here |
|---|---|---|
| a lockfile recording where each version's source is | `package-lock.json`, `Cargo.lock` | `gnomod.lock` |
| a tool-managed directory, materialized on demand | `virtualenv`, `node_modules` | `.gnopm/` |

Only versions that no longer exist in the tree are materialized. The code you
are editing is never copied anywhere, so your editor, your language server and
every error message keep pointing at the real file.

## Commands

```
gnopm status            what the workspace resolves, and what is out of date
gnopm sync              make the state good
gnopm bump <package>    promote a package to its next version, in place
gnopm ls [pattern]      list resolvable modules and where their source is
gnopm verify            prove every pinned version still reproduces (CI)
gnopm deversion         one-time migration off versioned directories
```

Six commands, and two of them are the ones you type: `status` to ask, `sync` to
fix. There is deliberately no separate "write the lock" and "download the
versions": both are just `sync`, which works out what is missing and does it.

`<package>` is a directory, a module path, or any unambiguous part of one, so
`p/alice/md`, `gno.land/p/alice/md/v0` and `md` all resolve to the same package.
Flags may appear before or after positional arguments.

Global options: `-C <dir>` to run as if started elsewhere, `-q` for terse
output, `-json` for machine-readable output.

**Data goes to stdout and nothing else does.** Progress, warnings and
diagnostics go to stderr, so a pipe gets data and a human still sees what
happened:

```
gnopm ls -q | xargs -n1 gno lint
gnopm ls -pinned -json | jq -r '.[].commit'
gnopm status -json | jq -e .ok
```

### status and verify are not the same question

`status` is a cheap glance: does the lock describe the tree, is the assembly
current. It never touches git history and always exits 0.

`verify` is the expensive proof: it re-reads every pinned version out of history
and re-hashes it, so a rewritten or garbage-collected commit is caught here
rather than discovered weeks later by somebody whose build stopped working. It
writes nothing and exits non-zero. That is the one for CI.

## Workflows

### Add a package

Create the directory **without** a version segment and declare the version in
`gnomod.toml`, then:

```
gnopm sync
```

Commit `gnomod.lock` along with the package.

### Bump

```
gnopm bump md
# ...edit the files in place...
```

Three things happen, and the directory is not one of them:

1. the outgoing version is pinned to a commit that still holds it, so
   everything importing it keeps resolving;
2. the `module` line becomes the next version;
3. the package becomes the working-tree copy of the new version.

Then you edit, and git diffs it. `-to <n>` skips versions. `bump` syncs before
and after, so there is nothing to run afterwards.

**It refuses when the package has uncommitted changes.** The commit it records
has to be one where the directory actually held the outgoing version; a dirty
directory makes that record a lie, and the hash stored alongside would be of the
wrong bytes too, so nothing downstream would catch it. `-force` exists for when
you are sure. The check is scoped to the package, so unrelated edits elsewhere
never block a bump.

### Migrate a repository that has versioned directories

```
gnopm deversion -n      # the plan
gnopm deversion         # do it
```

The ordering is the part that is easy to get wrong, which is why it is a command
and not a page of instructions:

1. **Pin everything first**, before anything is removed. Skipping this is
   unrecoverable: a version deleted without a pin is a version nobody can
   resolve again.
2. **Move**, lifting each `pkg/vN` directory's files up to `pkg` with `git mv`,
   so git records renames and the change reviews as a rename list. Where several
   versions of a package exist, the highest keeps the directory and the rest
   leave the tree, still resolvable from step 1.
3. **Re-lock and materialize.**

**Module lines are not touched.** A realm's address derives from its package
path, so rewriting one during the move would silently change an address. The
migration is a pure directory move.

It refuses on uncommitted work, refuses if a directory's version disagrees with
its module line, and checks the whole plan for collisions before moving
anything, because half a migration is much worse than none. It is idempotent and
only touches directories that still carry a version, so a branch opened before
the migration can rebase and re-run it to fix up just its own packages.

## `gnomod.lock`

```toml
lock = 1

[[module]]
module = "gno.land/p/alice/md/v0"
source = { commit = "d387abaa3a81...", dir = "p/alice/md/v0" }
hash = "h1:3f9c..."

[[module]]
module = "gno.land/p/alice/md/v1"
source = { dir = "p/alice/md" }
```

**Flat: one entry per resolvable module path**, not a package with nested
versions. gno has no concept of an unversioned module path (the path *is*
`.../md/v0`), so inventing one purely for the lock would make the format harder
to adopt than the thing it describes.

**`source` is a tagged union.** All four variants are specified, because that is
what makes this a format rather than one program's scratch file. Two are
implemented.

| variant | means | implemented |
|---|---|---|
| `{ dir }` | in the working tree, the version you edit | yes |
| `{ commit, dir }` | this repository's git history | yes |
| `{ repo, commit, dir }` | another git repository | not yet |
| `{ chain, tx }` | deployed source, read back via `vm/qfile` | not yet |

**`hash` is `h1:`**, the same construction as a `go.sum` line: sha256 over a
sorted manifest of `<sha256 of content>  <name>` lines. The prefix means the
algorithm can be replaced later without a format bump, and anyone who has read a
`go.sum` already knows what it is. The hashed set is every **git-tracked** file
in the directory at that commit, which makes it reproducible whether the code is
read from the working tree or from `git archive`, and sidesteps the "is
`_test.gno` part of the package" question by never asking it.

**A `{ dir }` entry deliberately carries no hash.** It points at a directory
someone is editing right now. Hashing it would rewrite `gnomod.lock` on every
source edit, so every change would carry a lock diff and two unrelated changes
would conflict in it. The working tree is pinned by git; the lock only has to
say where it is.

### Why `gnomod.lock` and not `gnopm.lock`

Every ecosystem names the lock after the **manifest**, not the tool, and puts it
at the **workspace root only**: `Cargo.toml` to `Cargo.lock` (root of the
workspace, never per-crate), `package.json` to `package-lock.json`, `Gemfile` to
`Gemfile.lock`. Naming it after the binary would make the format read as one
implementation's private file, which is fatal to it becoming a convention.

### The lock is source, not a generated artifact

It is committed by the author of a change, like `Cargo.lock` and unlike a
generated catalog. A change that bumps a version has to carry the pin that keeps
the outgoing version resolvable, or CI cannot build what still imports it.

It changes only when a package is **added, removed or bumped**, never on an
ordinary source edit. Entries are sorted by module path and separated by blank
lines, so two changes adding two packages usually merge without a conflict.

## Which commit a pin goes to

Not `HEAD`, and this is the subtle part.

Most repositories **squash-merge or rebase-merge**. A branch's commits then
never become ancestors of the default branch, and once the branch is deleted
they are unreachable from any branch or tag: a fresh clone does not have them,
because `git fetch` brings branches and tags and not `refs/pull/*`. A version
pinned to a branch's `HEAD` therefore stops resolving the moment the change
lands, and `verify` fails on the default branch from then on with nothing left
to recover the version from.

So `bump` and `freeze` pin to a commit that is **already on the default branch**
and holds byte-identical content: its tip in the ordinary case, since nothing on
this branch has touched the package yet, falling back to the last commit that
touched the directory. If neither matches, the version genuinely exists nowhere
but this branch; `HEAD` is then the only honest answer and gnopm says so, with
what to do about it.

**CI must check out full history.** A shallow clone has none of the pinned
commits, so every materialization fails. With `actions/checkout` that means
`fetch-depth: 0`.

## What `verify` proves

1. `gnomod.lock` is in canonical form, so a hand edit or a stale generator is
   caught before it becomes a merge conflict.
2. The lock and the working tree agree about where every module lives: nothing
   in the tree is missing from the lock, and no `{ dir }` entry points at a
   directory that does not declare it.
3. Every version pinned to history still reproduces its recorded hash.

It deliberately does **not** check "the lock is byte-identical to what `sync`
would write". That is simpler, but it fails during the one window where the lock
is meant to disagree with the tree: the migration pins packages that are still
in their directories, precisely so the directories can then move. A guard with a
documented exception is a guard with a hole, so the rule is consistency rather
than identity.

## Seeing it work

**[github.com/moul/gnopm-demo](https://github.com/moul/gnopm-demo)** is a
generated worked example: a whole workspace built from nothing, migrated off
versioned directories, and then worked on normally. Read it as a history rather
than a tree.

[`scripts/demo.sh`](./scripts/demo.sh) is what produces it, and it builds the
repository from nothing and asserts at every step. It needs no network and no
GitHub:

```
./scripts/demo.sh /tmp/gnopm-demo
```

It is the integration test (`go test ./...` runs it) and the demo repository at
the same time, deliberately. A demo that is not executed rots; a demo that is
executed as a test cannot. It has already caught three real defects that unit
tests missed: `-C` not working before the subcommand, two copies of the
lock-consistency check that could disagree, and error messages naming commands
that had been removed.

Add `--push <owner>/<repo>` to publish the result. The repository it produces is
a history to read rather than a tree to browse:

```
git log --reverse --stat
```

Act 1 builds a workspace the old way, one directory per version, and ends with
a copy-bump whose diff the script asserts is a **pure addition**, nothing
removed, compatibility change invisible. Act 2 is one `gnopm deversion`, which
the script asserts git records as `R100` renames. Act 3 is ordinary work
afterwards: a package added with no version in its path, a bump that is
literally one line in `gnomod.toml` followed by the real content diff, a version
skipped with `-to`, and a superseded version still resolving for the realm that
still imports it.

```
p/demo/math/bignum/{v0 => }/bignum.gno  | 0      <- the migration
p/demo/table/gnomod.toml                | 2 +-   <- the bump
```

The generated repository is rewritten from scratch on every run, which is what
lets it always show the tool's current behaviour rather than whatever it was
when someone last remembered to update a fixture.

## Integrating it

- Gitignore `/.gnopm/`. `install` refuses otherwise: a committed assembly would
  put a second copy of old versions back in the tree, which is the problem
  gnopm removes.
- Make every gno-invoking target depend on `.gnopm/.stamp`. The stamp is the
  lock's hash, so a repeat `sync` is a no-op and the dependency is free.
- Run `verify` in CI, with full history.
- Build and test the materialized versions too, if you were building them
  before. They are deployed, other packages import them, and "does this still
  compile on current gno" is a real signal. Losing it as a side effect of a
  directory move is a bad trade.
- Do not format or edit anything under `.gnopm/`. It is a read-only projection
  of history, and changing it breaks its recorded hash.

In this repository that is a `.gnopm/.stamp` prerequisite on `test`, `lint` and
`fmt`, plus a `make verify` for CI. Everything else you type as `gnopm`
directly: wrapping a good CLI in `make thing VAR=value` only makes it worse.

## Dependencies

None. The lock parser and the `h1:` hash are standard library. A lockfile format
whose reference implementation needs a dependency tree is a bad advertisement
for itself.

The format lives in its own importable package,
[`pkg/gnomodlock`](./pkg/gnomodlock), apart from the CLI, because more than one
program has to read it: a format only its own writer can parse is not a format.
It is named for the file rather than for the manifest, since `gnomod` is
already a package in the gno monorepo.

## Status

Step 1 of five: lock and install. It lives inside a contracts repository while
the format survives contact with reality, and is meant to graduate.

Ideas, prior art and open questions live in
[issue #172](https://github.com/moul/gno-contracts/issues/172): what is worth
stealing from `go mod` and from `docker`, why Minimal Version Selection
deliberately does not apply here, the principles to hold, and the non-goals.
Argue there before writing code.

1. **Lock + install.** This.
2. **Bump** as a first-class operation, including regenerating fixtures keyed on
   a realm address (an address derives from the package path, so a `v1` realm
   has a different address than its `v0`).
3. **Chain.** Publish ordering, on-chain status, per-network version state.
   Much of this already exists in the sibling catalog tool, and the intent is
   for gnopm to absorb it rather than for the two to coexist indefinitely.
4. **Links and reporting.** A permalink to any version's source at its commit,
   dependency graph, catalog.
5. **Graduation.** Standalone repository, spec, upstream proposal.
