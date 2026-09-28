# gnohome

The local half of [`r/moul/home`](../../README.md): write markdown in
`content/`, see the page before anyone else does, push only what changed.

Standard library only: no `gnoclient`, no cgo, no second `go.mod`. It reads the
chain over plain JSON-RPC `abci_query` and **prints** `gnokey` commands instead
of signing them, so it holds no key and can broadcast nothing by accident.

## The loop

```sh
$EDITOR r/moul/home/content/bio.md

go -C tools tool gnohome preview   # exactly what the realm will render
go -C tools tool gnohome status    # what differs from the chain
go -C tools tool gnohome tx        # the commands to fix that
```

`tx` writes to stdout. **Do not pipe it into `sh`**: `gnokey` reads the
passphrase from stdin, and the pipe takes stdin away, so every prompt fails
with `inappropriate ioctl for device`. Save it, read it, run it:

```sh
go -C tools tool gnohome tx > /tmp/slots.sh
sh /tmp/slots.sh
```

Better still, use `-batch` and sign once. See below.

## Commands

| command | what it does |
| --- | --- |
| `slots` | the local slots: name, bytes, hash, path |
| `preview` | render the page locally; `-out FILE` to write it |
| `status` | diff `content/` against the chain manifest, one query, no bodies |
| `tx` | the plan: `Set` each outdated slot, and with `-prune` `Delete` each slot the chain has and `content/` does not |
| `packages` | print the `packages` slot, generated from `contracts.json` |

Shared flags: `-content` `-realm` `-remote` `-chainid` `-key` `-owner`.
`preview` adds `-out` `-height` `-rev`; `tx` adds `-inline` `-all` `-prune`
`-gas-wanted` `-gas-fee` `-max-deposit`; `packages` adds `-catalog` `-network`.
`gnohome <cmd> -h` lists them.

`tx` describes by default and `-run` performs. **`-print` is the same thing as the
default**, and it exists because every other tool in this ecosystem spells "show
me, run nothing" that way; the one that inverts the flag is the one a reader
abandons for raw `gnokey`. It also **beats `-run`**, so appending it to a recalled
command line can never broadcast.

### `-batch`: one transaction, one signature

`tx` emits one command per outdated slot, which is one passphrase prompt per
slot and, worse, **not atomic**: a failure halfway leaves the page assembled
from a mix of old and new slots, with the layout pointing at a placeholder
that was never written.

A tm2 transaction carries a *list* of messages (`std.Tx.Msgs`), and `gnokey
sign` signs the document rather than the message. So the whole update can be
one signature:

```sh
go -C tools tool gnohome tx -prune -batch /tmp/home.tx.json
sh /tmp/home.tx.sh    # signs, then broadcasts, written next to the document
```

The two commands are also printed, chained with `&&`. That is not cosmetic:
`gnokey broadcast` does **not** refuse an unsigned document locally, it sends
it and lets the chain answer `no signers`. Signing has to gate the broadcast.

It reads the account number and sequence off the chain and puts them in the
`sign` command for you. **The signature is bound to chain-id, account number
and sequence**, so broadcast before that account signs anything else, or the
document is void.

This path also removes the `"$(/bin/cat …)"` problem entirely: in a document
the body is a literal JSON string, so there is no shell to quote for, nothing
eats the trailing newline, and `ARG_MAX` stops being a ceiling on slot size.

### `-all` and `-prune` compose, and once did not

`-prune` adds a `Delete` for every slot on chain with no local file. `-all`
pushes every local slot rather than only the outdated ones.

Until 2026-09-28 `-all` built its plan from the local files **without fetching
the manifest**, on the reasoning that a redeploy empties the store so there is
nothing to ask about. True of the slots it pushed, false of the ones it did not:
with no manifest there are no extras, so `-all -prune` emitted zero `Delete`
messages, accepted the flag and warned about nothing. The document looked
plausible, the page even rendered correctly, because a section disappears the
moment the new `layout` is set, and the orphaned slots stayed in the store with
their deposit locked. `TestAllChangesKeepsTheExtras` pins it.

`tx` now fetches the manifest either way. `-all` selects which local slots are
pushed; it no longer decides whether the chain is consulted.

### `-run`: and sign and broadcast it, which is what `make home-push` does

```sh
make home-push              # build the document, sign it, broadcast it
make home-push PRINT=1      # build it and print the two commands, run nothing
```

`-run` implies `-batch`, and picks its own path under the temp dir keyed by
chain id when none is named, so a staging document and a mainnet one cannot
overwrite each other. It writes the same document and the same `.sh` first, so
a run that fails halfway is reproducible by hand from what is already on disk.

What it removes is the **paste**, not the review. The signature covers the
account sequence, so the document is valid only until that key signs anything
else, and the gap between reading the two commands and running them is exactly
the gap in which that happens. Pasting is also how the wrong document gets
broadcast, since `gnokey broadcast` does not check locally that a document was
signed at all.

gnohome still holds no key: it shells out to `gnokey`, which prompts for the
passphrase exactly as it would if you had typed the command. The child inherits
stdin for that reason, which is also why `make home-push` must not be piped
into anything.

### Deploying is not here

Publishing the realm is [`gnopm publish`](https://github.com/moul/gnopm), which
does it for any package in any workspace: chain discovered from the package
path, live/parked/absent reported as three states, dependency ordering, gas and
fee sized from the payload, and `gnokey` commands emitted rather than signed.
A per-contract tool would have reinvented all of it once per contract.

This tool owns only what is specific to this realm: its slots.

### `packages` is the one generated slot

Every other slot is prose somebody wrote. `packages` is a claim about what is
deployed, so writing it by hand guarantees it goes stale the next time a
contract lands. It reads `contracts.json`, keeps the highest version of each
family **that is actually uploaded to the target network** (so a `v1` that only
reached pearl does not get advertised on mainnet), and prints the counts plus
the libraries and realms by name. `x/daily` is counted rather than listed:
there are more of those than of everything else together.

```sh
make home-packages                 # regenerate it
go -C tools tool gnohome status    # then push it like any other slot
```

**It is regenerated on `main` by the regen workflow (`make gen`), and a pull
request may not carry it** (`generatedPaths`, `tools/gnocontracts/guard_generated.go`).

Both of those are recent, and they exist because neither was true for weeks.
The paragraph above was already correct about the risk; nothing enforced it.
`make gen` did not write this file and no guard rejected a hand edit, so it was
updated by whoever remembered. It drifted to **239 packages and 169 daily
experiments while the catalog said 245 and 173**, and the realm served the
stale numbers to everyone who opened `/u/moul`, for as long as it took a human
to read his own page and notice.

The general rule it made explicit: **no count is typed by hand anywhere in
`content/`.** `now.md` opened with "169 of them are on chain" and was wrong
within a fortnight for exactly the same reason; it now points at this slot
instead. A number a tool can derive belongs in the generated slot. Prose that
cannot go stale belongs in the others.

Output is deterministic for a given catalog, so regenerating without a catalog
change leaves `status` quiet instead of proposing a no-op transaction.

`-content` defaults to `<repo>/r/moul/home/content`, found by walking up to
`gnowork.toml`, so the commands above work from anywhere in the repo.

## Every chain read is retried, including on 403

`rpc.gno.land` sits behind a load balancer that intermittently answers a bare
`403` to a source it has decided to throttle: no `Retry-After`, no rate-limit
header, no body, and the next request often succeeds. Seen from two different
hosts on 2026-09-24 and 2026-09-28, minutes apart, while the same endpoint
answered 200 to another host.

`tx -run` reads the account before it can build anything, so one 403 on the
first call ended the whole push with nothing done. That is how `make home-push`
failed the first time it was used for real:

```
gnohome: reading g1manfred…: querying https://rpc.gno.land:443: HTTP 403 Forbidden
make: *** [Makefile:101: home-push] Error 1
```

So `abciQuery` retries 5 times with a doubling backoff (1s, 2s, 4s, 8s), says so
on stderr each time, and gives up after about 15s rather than hanging.

**403 is normally the one status it is wrong to retry**, and it is retried here
deliberately: this endpoint is an *unauthenticated public read*, so there is no
credential that could be wrong and 403 cannot mean what it usually means. The
only reading left is that the edge refused to pass the request on. If gnohome
ever reads an endpoint that takes a credential, this has to be revisited.

Retried: `403`, `429`, `5xx`, and transport failures. **Not** retried: an ABCI
error, `400`, `404`. Those are answers from a healthy node and will not change,
and retrying them would turn a clear message into a slow one.

## How a slot maps to a file

`content/<slug>.md` → the slot `<slug>`. `layout.md` is the page template.
Sub-directories and non-`.md` files are ignored; an invalid or reserved slug is
an error, not a surprise on chain.

## Computed placeholders, and how exact `preview` is

The realm fills eleven placeholders from chain state rather than from a slot,
and `preview` reproduces all of them so the rendered page is the real one:
`:owner:` `:realm:` `:chainid:` `:height:` `:rev:` `:slots:`, plus the five
explorer links `:scan:` `:scan.realm:` `:scan.me:` `:scan.block:`
`:scan.links:` (`scan.go`, mirroring `r/moul/home/scan.gno`).

Two deliberate approximations, and nothing else differs:

- `:height:` and `:rev:` are whatever the chain query returned, or zero offline.
- The explorer **base URL** is `p/moul/mygnoscan`'s `DefaultBase`. On chain it
  comes from `r/moul/config`, so if the explorer is ever repointed the preview
  keeps showing the default. The path shapes are identical either way.

`scan.go` is a mirror, not an import, because `p/moul/mygnoscan` is gno and its
`Scanner` reads chain state. When the two disagree, **the realm is right and
the mirror is the bug**. `scan_test.go` pins the URL shapes and asserts that
the shipped `content/layout.md` renders with no `:slug:` left in it, which is
the failure this whole file exists to prevent: an unmatched placeholder is not
an error, it is a literal `:scan.links:` shown to every visitor.

## The one subtle part: `"$(/bin/cat …)"`

`tx` emits the body as `-args "$(/bin/cat '<abs path>')"` rather than inlining a
few kilobytes of markdown into your terminal. Two details make that safe:

- **Trailing newlines are stripped locally, and nothing else is.** Command
  substitution eats trailing newlines, so a body that kept one would hash
  differently on chain than `status` compared, and the slot would report as
  outdated forever. Trailing *spaces* are kept, because `cat` keeps them.
  Carriage returns are refused at load time for the same reason.
- **`/bin/cat`, not `cat`.** A shadowed or broken `cat` on `PATH` makes the
  substitution expand to nothing, and the command would then silently set the
  slot to the empty string. The absolute path is deliberate.

Use `-inline` to embed the literal instead (shell-quoted, apostrophes included).

## After a redeploy

Re-adding the package resets realm state: `init()` runs again and the slot tree
is empty. Push everything back:

```sh
make home-push          # or: gnohome tx -prune -batch /tmp/home.tx.json
```

No special flag for it. An empty manifest makes every local slot `missing`, so
the ordinary plan already pushes all of them. `-all` exists for the other case,
re-sending a slot the chain already agrees with, which costs gas and changes
nothing.

The redeploy that carried `scan.gno` landed at height 396749 and emptied the
tree, which is what this path exists for: eight slots, one transaction, one
signature.

## Bodies too large for one transaction

`tx` warns past 60 KiB. The realm's `Append` is the escape hatch: `Set` the first
chunk, `Append` the rest. `gnohome` does not chunk automatically, because splitting is a
judgement call about where a body can be cut.
