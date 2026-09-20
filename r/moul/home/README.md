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

`cmd/gnohome` is the local half: it builds the slots from `content/*.md`, renders
the page offline exactly as the realm would, diffs against the chain, and prints
the `gnokey` commands for what is outdated, nothing else.

```sh
go run ./r/moul/home/cmd/gnohome preview   # see the page before anyone else does
go run ./r/moul/home/cmd/gnohome status    # what differs from the chain
go run ./r/moul/home/cmd/gnohome tx        # the commands to fix that
```

The `packages` slot is generated, not written: it is a claim about what is
deployed, and `contracts.json` already tracks that per network.

```sh
go run ./r/moul/home/cmd/gnohome packages > r/moul/home/content/packages.md
```


See [`cmd/gnohome/README.md`](./cmd/gnohome/README.md).

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

### 1. Dry-run

`-simulate only` signs locally and asks the node for the real `GasUsed` without
broadcasting. Code-bearing messages cannot be simulated unsigned, so this is the
only honest estimate available.

```sh
gnokey maketx addpkg \
  -pkgdir r/moul/home \
  -pkgpath gno.land/r/moul/home \
  -gas-fee 600000ugnot -gas-wanted 60000000 \
  -max-deposit 10000000ugnot \
  -broadcast -simulate only \
  -chainid gnoland-1 -remote https://rpc.gno.land:443 \
  moul
```

### 2. Broadcast

Same line with `-simulate test`, after sizing `-gas-wanted` down from the
`GasUsed` the dry-run reported.

```sh
gnokey maketx addpkg \
  -pkgdir r/moul/home \
  -pkgpath gno.land/r/moul/home \
  -gas-fee 600000ugnot -gas-wanted 60000000 \
  -max-deposit 10000000ugnot \
  -broadcast -chainid gnoland-1 -remote https://rpc.gno.land:443 \
  moul
```

### 3. Confirm it went live, not just parked

```sh
curl -s 'https://rpc.gno.land/abci_query?path=%22vm%2Fqinertpaths%22&data=0x' \
  | jq -r '.result.response.ResponseBase.Data' | base64 -d | grep moul/home
```

Still listed means still parked. Gone (and `vm/qrender` answering) means enabled.

### 4. Push the content

```sh
go run ./r/moul/home/cmd/gnohome tx -all | sh
```

### Where those numbers come from

`gnokey maketx addpkg` uploads with `MPUserAll`, so every `.gno`, `.toml` and
`.md` in the package directory travels, test files and this README included:
**29,797 bytes** across six files. `cmd/` and `content/` are sub-directories and
are skipped.

- **`-gas-wanted 60000000`.** Ten successful mainnet `add_package` transactions
  above h160000 cost **1,014 to 1,781 gas per uploaded byte** (median 1,393). At
  the top of that range this package needs ~53.1M, so the 40M this file used to
  suggest was under the worst case. 60M is a ceiling, and a ceiling is not
  charged.
- **`-gas-fee 600000ugnot`.** The fee requirement is the `gas_fee / gas_wanted`
  **ratio**, and the ratio is what the mempool enforces, so headroom is not free.
  The lowest accepted ratio on mainnet is 0.001 ugnot/gas and comparable
  `add_package` transactions paid 0.001 to 0.00125. 600000/60000000 = 0.01, ten
  times the floor. **`gas_fee` is deducted in full and never refunded**, which is
  why the previous 1000000ugnot at 40M gas (0.025, twenty-five times the floor)
  was worth fixing.
- **`-max-deposit 10000000ugnot`.** Omitting it is not opting out: it falls back
  to `vm:p:default_deposit`, **100 GNOT of ceiling per message**. Storage locks
  100ugnot per byte, so the source alone is 2.98 GNOT and realm state is extra.
  10 GNOT is a deliberate ceiling with room. Unlike `gas_fee` this one is
  refundable, and only the measured byte delta is ever locked.

Re-measure before a later redeploy: gas is a function of the code, and both the
gas price and the submission policy are chain parameters.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/home dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/home/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
