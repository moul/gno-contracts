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

This is also why `gnopm bump` refuses this package: it looks for a trailing
`/vN` on the module line to increment and there is none. The module line stays
bare, `gnopm status` and `gnopm verify` accept it, and only `bump` is off the
table. A compatibility change here is a redeploy of the same path, not a new
version.

### What it replaces: `gno.land/r/moul/home/v0`

This directory used to hold a different realm: a hand-maintained dashboard with
a todo list, a status string and a meme URL, its state mutable only by the admin
and its *shape* only by redeploying. It never reached any network
(`contracts.json` had it `uploaded: false` everywhere), so nothing on chain is
being replaced, only the source.

That version is not deleted, it is **pinned to history** in `gnomod.lock` the way
`AGENTS.md` prescribes for a superseded version:

```toml
[[module]]
module = "gno.land/r/moul/home/v0"
source = { commit = "4f2df83869b80470eb81c48a82fdbe82256b8113", dir = "r/moul/home" }
```

So it keeps resolving for anything that imports it, `gnopm sync` materializes it
under `.gnopm/`, and it is still linted and tested from there. Read the code at
[`r/moul/home` @ 4f2df83][v0], the last commit where this directory held it.

[handler]: https://github.com/gnolang/gno/blob/master/gno.land/pkg/gnoweb/handler_http.go
[v0]: https://github.com/moul/gno-contracts/tree/4f2df83869b80470eb81c48a82fdbe82256b8113/r/moul/home

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
<gno-columns>
![Manfred Touron](https://avatars.githubusercontent.com/u/94029?s=400)
<gno-columns-sep />
# Manfred Touron

:bio:

:social:
</gno-columns>

## Packages

:packages:
```

`<gno-columns>` / `<gno-columns-sep />` are gnoweb's own extension, not HTML:
raw HTML is not rendered, these are parsed. Adding a section is a **content**
change, never a code one: the renderer registers one placeholder per slot by
iterating the tree, so writing `content/social.md` and referencing `:social:`
is the whole of it.

### Images: two gates, and neither is the one you expect

An image in a slot passes **gnoweb's validator** and then the **CSP the site is
served behind**. They block different things, and only the second is a domain
list:

- gnoweb's `AllowSvgDataImage` (`gno.land/pkg/gnoweb/render_config.go`, wired in
  `markdown/ext_imgvalidator.go`)
  rejects every `data:` URI that is not `image/svg+xml`, and blanks the `src`
  rather than dropping the tag. Ordinary `https://` URLs are not checked at all.
- The live `content-security-policy` header on gno.land pins `img-src` to
  `'self' data:` plus a fixed host list: `*.githubusercontent.com`,
  `*.github.io`, `github.com`, `imgur.com`, `*.imgur.com`, `assets.gnoteam.com`,
  `sa.gno.services`, `gnolang.github.io`, `ipfs.io`, `cloudflare-ipfs.com`
  (read 2026-09-19). Anything else is silently not painted by the browser, with
  the HTML looking perfectly fine.

So a GitHub avatar needs no hosting of its own:
`https://avatars.githubusercontent.com/u/94029?s=400` matches
`*.githubusercontent.com` and renders as-is. Verified by running this exact
page through gnoweb's real goldmark pipeline, not by reading the policy.

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

`tools/gnohome` is the local half: it builds the slots from `content/*.md`, renders
the page offline exactly as the realm would, diffs against the chain, and prints
the `gnokey` commands for what is outdated, nothing else.

```sh
go -C tools tool gnohome preview   # see the page before anyone else does
go -C tools tool gnohome status    # what differs from the chain
go -C tools tool gnohome tx        # the commands to fix that
```

The `packages` slot is generated, not written: it is a claim about what is
deployed, and `contracts.json` already tracks that per network.

```sh
go -C tools tool gnohome packages > r/moul/home/content/packages.md
```


See [`tools/gnohome/README.md`](../../../tools/gnohome/README.md).

## First deploy

The realm is not on chain yet. `Set` needs the package there first, and a
`private` package still needs `MsgAddPackage`, which no account session can sign.

**mainnet deploys in two phases.** `gnoland-1` runs
`vm:p:code_submission_policy = "inert"` (read back from the chain 2026-09-19), so
`MsgAddPackage` **parks** the bytes under `inert_pkg:<path>` and returns
`success: true` without making the package live. `Render` still answers
`package not found`, `/u/moul` is still blank, and `gnohome tx` cannot land a
single slot until an approver in `vm:p:pkg_approvers` sends `MsgEnablePackage`.

In practice that gate is an oracle, not a queue: `g1yaaa6rcp4ew5yjzdj4yms596wx2dtrj3a86704`
enabled the four most recent parked packages after 1 to 4 blocks, 3.3 to 13.2
seconds. It can still refuse, and a refusal is easy to miss, so check rather than
assume.

### The whole plan, from gnopm

Deploying is not special to this realm, so it is not this realm's tool that
does it. `gnopm publish` reads the chain, reports whether the package is live,
parked or absent, checks that every non-test dependency is already up, sizes
gas, fee and deposit from the real payload, and writes the `gnokey` commands.
It never signs.

```sh
gnopm publish -key moul moul/home     # read the report, read the script
gnopm publish -key moul moul/home | sh
```

Then the content, once the realm answers:

```sh
go -C tools tool gnohome tx -all | sh
```

Run those rather than copying commands from here: anything written down goes
stale, and the tools recompute from the files as they are.

### How it sizes them

Deliberately no byte count here. This README **is part of the payload**, so any
figure quoted in it invalidates itself the moment the file is edited. The tool
reads the real numbers off the files; what follows is only the method, so a
reader can judge it.

**What travels.** `gnokey maketx addpkg` uploads with `MPUserAll`
(`gno.land/pkg/keyscli/addpkg.go`), so every `.gno`, `.toml` and `.md` in the
package directory goes on chain, **test files and this README included**.
Sub-directories are skipped, which is why `content/` never ships. The README is
usually the single largest file, and you pay gas and storage on it.

**`-gas-wanted`, at 1,800 gas per uploaded byte.** Ten successful mainnet
`add_package` transactions above h160000 cost **1,014 to 1,781 gas/byte**
(median 1,393, measured 2026-09-19). The spread is the package's own `init()`
work, which a byte count cannot see, so size from the top of the range. It is a
ceiling and a ceiling is not charged.

**`-gas-fee`, at ten times the accepted floor.** What the mempool enforces is
the `gas_fee / gas_wanted` **ratio**, not the absolute
(`EnsureSufficientMempoolFees`), so raising the ceiling raises the required fee
and headroom is not free. The lowest ratio accepted on mainnet is
**0.001 ugnot/gas**; comparable `add_package` transactions paid 0.001 to
0.00125. The tool offers 0.01. **`gas_fee` is deducted in full as offered and
never refunded**, so over-offering is a real cost and not insurance: the flat
`1000000ugnot` this tooling used to emit for a slot write was about ninety times
the floor.

**`-max-deposit`, an explicit ceiling.** Omitting it is not opting out: it falls
back to `vm:p:default_deposit`, **100 GNOT of ceiling per message**. Storage
locks 100ugnot per byte. Unlike the gas fee this one is **refundable** and only
the measured byte delta is ever locked, so headroom here costs nothing.

Re-measure before a later redeploy: gas is a function of the code, and both the
gas price and the submission policy are chain parameters.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/home dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/home/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
