# gnopublish

Publishes this repo's packages to a gno.land network, in dependency order, signing
with your local **gnokey** key — asking for the password **once** and reusing it for
every transaction (via [`gnoclient`](https://github.com/gnolang/gno/tree/master/gno.land/pkg/gnoclient)).

## What it does

1. Reads `contracts.json`, resolves the path selectors you pass, and drops `draft`
   / `ignore = true` packages.
2. Queries the target network to find which selected packages are **missing** (or,
   with `-full`, whose on-chain file content differs from the local source).
3. Orders the work **dependencies-first** (a package is always published before
   anything that imports it).
4. Prints the plan, asks your gnokey password once, and broadcasts:
   - **`-mode individual`** (default): one tx per package — separate blocks.
   - **`-mode merge`**: all packages in a single tx/block.

## Build requirements

It links the full gno client stack, so it is a **separate Go module** (kept out of
the CI `gnocontracts` tool). Building it needs:

- **Go ≥ 1.25** (auto-downloaded via `GOTOOLCHAIN=auto`),
- a **C toolchain** (gno pulls a cgo storage backend),
- a local **gno checkout** — the `replace` in `go.mod` points at `../../../../gnoland/gno`
  (i.e. `~/p/gh/gnoland/gno`). Adjust it if yours lives elsewhere.

## Usage

Run it from anywhere inside the repo (it finds the root via `gnowork.toml`):

```sh
cd tools/gnopublish

# see the plan without broadcasting
go run . -net portal-loop -dry-run ./...

# publish everything missing under p/moul, one tx per package
go run . -net portal-loop -key mykey ./p/moul/...

# publish a single package, all in one merged tx
go run . -net test6 -key mykey -mode merge ./r/moul/hello

# also re-publish packages whose on-chain content drifted from local
go run . -net portal-loop -key mykey -full ./...
```

Or via the repo Makefile:

```sh
make upload ARGS="-net portal-loop -key mykey -dry-run ./..."
```

### Flags

| flag | meaning |
|---|---|
| `-net` | network name from `contracts.json` (default: first) |
| `-rpc` / `-chain-id` | override the network's RPC / chain id |
| `-key` | gnokey key name or address (or `$GNOKEY_KEY`) |
| `-home` | gnokey home dir (default `$GNOKEY_HOME` or `~/.gnokey`) |
| `-mode` | `individual` (default) or `merge` |
| `-full` | also re-publish content-drifted packages |
| `-gas-fee` / `-gas-wanted` / `-deposit` | tx tuning |
| `-dry-run` | print the plan and stop |
| `-yes` | skip the confirmation prompt |

`$GNOKEY_PASSWORD` is read if set (for automation); otherwise the password is
prompted once, with no echo.

## Selectors

Repo-relative, default `./...`:

- `./...` — every package
- `./p/moul/hello` — the `hello` package (all its versions)
- `./p/moul/hello/v1` — one exact version
- `./r/moul/...` — everything under `r/moul`
