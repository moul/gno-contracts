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

`tx` writes to stdout, so review then pipe: `… tx | sh`.

## Commands

| command | what it does |
| --- | --- |
| `slots` | the local slots: name, bytes, hash, path |
| `preview` | render the page locally; `-out FILE` to write it |
| `status` | diff `content/` against the chain manifest, one query, no bodies |
| `tx` | print `gnokey maketx call` for each outdated slot |
| `packages` | print the `packages` slot, generated from `contracts.json` |
| `deploy` | preflight the realm against the chain, then print the whole command list |

Shared flags: `-content` `-realm` `-remote` `-chainid` `-key` `-owner`.
`preview` adds `-out` `-height` `-rev`; `tx` adds `-inline` `-all` `-prune`
`-gas-wanted` `-gas-fee` `-max-deposit`; `packages` adds `-catalog` `-network`.
`gnohome <cmd> -h` lists them.

### `deploy`: the preflight, then commands you can read

`gnopm` versions packages, it does not publish them, and `tools/gnopublish`
signs transactions itself. Neither answers *"tell me what is missing, size it,
and hand me commands I can read before anything is signed"*, which is the only
shape that works when the signer is moul's master key and no agent session may
touch `vm/add_package`.

`deploy` is read-only. It reports, in one pass:

- whether the package is **live**, **parked** or **absent**. Those are three
  different states and the usual explorers show two: `gnoland-1` runs
  `code_submission_policy = "inert"`, so `MsgAddPackage` parks the bytes and
  returns `success: true` without making anything live. `vm/qinertpaths` is the
  only read that sees a parked path.
- whether every **non-test** import is already on chain, and stops if not. Test
  imports travel with the package but the VM never runs them, so they do not
  gate a deploy.
- the **payload**, the same bytes the message carries (`.gno` including tests,
  `.toml`, `.md`, no sub-directories), biggest file first, because the README is
  usually the largest thing being paid for.
- **gas** at 1,800/byte, the top of the 1,014 to 1,781 range measured over ten
  successful mainnet `add_package` transactions, and a **fee** at ten times the
  accepted floor.

Then it prints the dry run, the broadcast, the parked-or-live check, and the
content push, in that order. It signs nothing and broadcasts nothing.

```sh
go -C tools tool gnohome deploy
```

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
go -C tools tool gnohome tx -all | sh
```

## Bodies too large for one transaction

`tx` warns past 60 KiB. The realm's `Append` is the escape hatch: `Set` the first
chunk, `Append` the rest. `gnohome` does not chunk automatically, because splitting is a
judgement call about where a body can be cut.
