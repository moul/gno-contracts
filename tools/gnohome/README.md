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
| `tx` | print `gnokey maketx call` for each outdated slot |
| `packages` | print the `packages` slot, generated from `contracts.json` |

Shared flags: `-content` `-realm` `-remote` `-chainid` `-key` `-owner`.
`preview` adds `-out` `-height` `-rev`; `tx` adds `-inline` `-all` `-prune`
`-gas-wanted` `-gas-fee` `-max-deposit`; `packages` adds `-catalog` `-network`.
`gnohome <cmd> -h` lists them.

### `-batch`: one transaction, one signature

`tx` emits one command per outdated slot, which is one passphrase prompt per
slot and, worse, **not atomic**: a failure halfway leaves the page assembled
from a mix of old and new slots, with the layout pointing at a placeholder
that was never written.

A tm2 transaction carries a *list* of messages (`std.Tx.Msgs`), and `gnokey
sign` signs the document rather than the message. So the whole update can be
one signature:

```sh
go -C tools tool gnohome tx -all -batch /tmp/home.tx.json
# then the two commands it prints: gnokey sign, gnokey broadcast
```

It reads the account number and sequence off the chain and puts them in the
`sign` command for you. **The signature is bound to chain-id, account number
and sequence**, so broadcast before that account signs anything else, or the
document is void.

This path also removes the `"$(/bin/cat …)"` problem entirely: in a document
the body is a literal JSON string, so there is no shell to quote for, nothing
eats the trailing newline, and `ARG_MAX` stops being a ceiling on slot size.

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
go -C tools tool gnohome packages > r/moul/home/content/packages.md
go -C tools tool gnohome status    # then push it like any other slot
```

Output is deterministic for a given catalog, so regenerating without a catalog
change leaves `status` quiet instead of proposing a no-op transaction.

`-content` defaults to `<repo>/r/moul/home/content`, found by walking up to
`gnowork.toml`, so the commands above work from anywhere in the repo.

## How a slot maps to a file

`content/<slug>.md` → the slot `<slug>`. `layout.md` is the page template.
Sub-directories and non-`.md` files are ignored; an invalid or reserved slug is
an error, not a surprise on chain.

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
is empty. Push everything back without consulting the chain:

```sh
go -C tools tool gnohome tx -all -batch /tmp/home.tx.json
```

## Bodies too large for one transaction

`tx` warns past 60 KiB. The realm's `Append` is the escape hatch: `Set` the first
chunk, `Append` the rest. `gnohome` does not chunk automatically, because splitting is a
judgement call about where a body can be cut.
