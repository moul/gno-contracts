# `gno.land/r/moul/home`

The realm behind **https://gno.land/u/moul**. A profile page whose content is
data, not code: update a paragraph with one small transaction instead of
redeploying a realm.

## Why this one has no `/vN`

It is the only contract in this repo at an unversioned path, and that is forced,
not a slip.

gnoweb builds a user profile by calling `Render("")` on the realm at the **exact**
path `/r/<username>/home` and embedding the result as the page body
([`gno.land/pkg/gnoweb/handler_http.go`][handler], `GetUserView`). That lookup does
no version resolution, so `gno.land/r/moul/home/v0` would never be found. The bare
path *is* the interface with gnoweb.

Versioning moves inside instead: content lives in slots (below), and the code can
be replaced in place because the package is `private`.

[handler]: https://github.com/gnolang/gno/blob/master/gno.land/pkg/gnoweb/handler_http.go

## Slots

The page is assembled from **slots**: named markdown fragments in an avl tree.

| function | what it does |
| --- | --- |
| `Set(cur, slug, body)` | create or replace one slot, the ordinary update |
| `Append(cur, slug, body)` | append, for a body too large for one transaction |
| `Delete(cur, slug)` | remove a slot |
| `Get(slug)` | read one body |
| `Manifest()` | `slug⇥rev⇥len⇥sha256` per slot, the diff surface |
| `Revision()` | total writes accepted, so a client can tell "nothing moved" |

Writes are restricted to `g1manfred47kzduec920z88wfr64ylksmdcedlf5`.

A slug is 1–64 bytes of `[a-z0-9._-]`. No `':'`, so a slug can never break out of
its own `:slug:` placeholder.

## The layout is a slot too

`Render("")` takes the slot named `layout` as its template and fills every
`:slug:` placeholder in it with `p/moul/dynreplacer`. So the shape of the page
(headings, order, what appears at all) changes without touching the code:

```
# Manfred Touron

:bio:

## Packages

:packages:
```

Six placeholders are computed from chain state rather than stored, and are
refused as slot names so nothing can shadow them: `:owner:` `:realm:`
`:chainid:` `:height:` `:rev:` `:slots:`.

Three properties worth knowing:

- **Lazy.** dynreplacer only invokes the callbacks whose placeholder actually
  occurs in the layout, so an unused slot is never read out of the tree.
- **Single-pass.** A placeholder inside a slot *body* is left alone. No slot can
  expand into another, so no cycle exists.
- **Order-independent.** Every placeholder is `:slug:` and a slug cannot contain
  `':'`, so no placeholder is a prefix of another and the replacer has no
  ambiguity to resolve.

An unmatched placeholder survives into the output verbatim. That is deliberate: a
missing section should be visible, not silently blank.

### Other render paths

- `:slots`: the slot index (name, size, revision, height of last write)
- `:slots/<slug>`: one slot's raw markdown, fenced

## Why `private`

`gnomod.toml` declares `private = true`. On gno.land that means two things:

1. **No other realm may import this one.** Fine for a profile page.
2. **The creator may re-add the package at this path.** `AddPackage` waives its
   already-exists refusal for a private package and binds the replacement to the
   address in `[addpkg].creator`.

⚠️ **A redeploy re-runs `init()` and resets all realm state.** The slots are gone.
That is why `content/` is the source of truth and why `gnohome tx -all` exists:
after a redeploy, push every slot back.

The intended path is that this never happens. Slots cover content and the layout
slot covers presentation, so the code should not need to change.

## Local workflow

`cmd/gnohome` is the local half: it builds the slots from `content/*.md`, renders
the page offline exactly as the realm would, diffs against the chain, and prints
the `gnokey` commands for what is outdated, nothing else.

```sh
go run ./r/moul/home/cmd/gnohome preview   # see the page before anyone else does
go run ./r/moul/home/cmd/gnohome status    # what differs from the chain
go run ./r/moul/home/cmd/gnohome tx        # the commands to fix that
```

See [`cmd/gnohome/README.md`](./cmd/gnohome/README.md).

## First deploy

The realm is not on chain yet. `Set` needs the package there first, and a
`private` package still needs `MsgAddPackage`, which no account session can sign.

```sh
gnokey maketx addpkg \
  -pkgdir r/moul/home \
  -pkgpath gno.land/r/moul/home \
  -gas-fee 1000000ugnot -gas-wanted 40000000 \
  -broadcast -chainid gnoland-1 -remote https://rpc.gno.land:443 \
  moul
```

Then `gnohome tx -all` for the content.
