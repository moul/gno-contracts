# Retired packages

This folder is a ledger, not a backup. Every package below is still on mainnet at its `v0`
path, unchanged, because deleting a directory here sends nothing to the chain. The source
is not lost either: `gnomod.lock` pins each one to the commit that last held it, together
with an `h1:` hash of its files. `gnopm sync` reads that commit back with `git archive` into
the gitignored `.gnopm/`, and refuses the copy if it does not hash to what the lock says;
`gnopm verify` re-hashes every pin from history. `make lint` and `make test` sync first and
then lint and test the copy in `.gnopm/`, so all seven still build on every run. The one
condition is full history: a shallow clone does not hold the pinned commit, which is why CI
checks out with `fetch-depth: 0`.

The code is therefore not kept here. Read it on chain, or in the tree at the pinned commit.

| package | on chain | pin (`commit` + `dir`) | `.gno` + README lines | why it went | instead |
|---|---|---|--:|---|---|
| `entity` | [`gno.land/p/moul/entity/v0`](https://gno.land/p/moul/entity/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/entity) `p/moul/entity` | 81 + 44 | an API sketch for "whoever is acting" whose three constructors panic, with no importer | nothing |
| `ownable` | [`gno.land/p/moul/ownable/v0`](https://gno.land/p/moul/ownable/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/ownable) `p/moul/ownable` | 69 + 49 | an `Owner` interface with empty implementations, wholly redundant with upstream's | `gno.land/p/nt/ownable/v0` |
| `safe` | [`gno.land/p/moul/safe/v0`](https://gno.land/p/moul/safe/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/safe) `p/moul/safe` | 163 + 46 | a multisig shape where 13 of 22 functions panic, every proposal path among them, with no importer | nothing |
| `udao` | [`gno.land/p/moul/udao/v0`](https://gno.land/p/moul/udao/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/udao) `p/moul/udao` | 177 + 45 | a DAO interface seen from the outside whose only importer was `xdao` | nothing; EFFECTIVE_GNO §1.5 and §5.5 still cite its on-chain `v0` as the shape |
| `xdao` | [`gno.land/p/moul/xdao/v0`](https://gno.land/p/moul/xdao/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/xdao) `p/moul/xdao` | 110 + 45 | a whitelist `udao.DAO` where 7 of 14 functions panic, with no importer | nothing |
| `template` | [`gno.land/p/moul/template/v0`](https://gno.land/p/moul/template/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/template) `p/moul/template` | 1,162 + 66 | a `{{ }}` engine with no importer that wrote every variable raw into markdown and reused the previous call's data on a nil map | `gno.land/p/moul/dynreplacer/v0` |
| `mdlist` | [`gno.land/p/moul/mdlist/v0`](https://gno.land/p/moul/mdlist/v0) | [`d867ce00`](https://github.com/moul/gno-contracts/tree/d867ce001a6934a82c5e602c06e925829cf1bcbb/p/moul/mdlist) `p/moul/mdlist` | 294 + 46 | a self-described proof of concept with no importer, whose truncation sliced bytes and panicked below a width of 3 | `ui.Excerpt` in `gno.land/p/moul/kit/ui/v0` |

The pin is `d867ce001a6934a82c5e602c06e925829cf1bcbb` for all seven, the last commit that
touched any of them, and it is on `main`. Line counts are what the deletion removed, tests
and filetests included, READMEs with their generated footer. The reasons come from the
census in #356; the deletion is #363. `p/moul/collection` was reviewed in the same round
and kept, because `gnobench` imports it.

**Why the code is not copied into this folder.** It was tried. gnopm finds a package by its
`gnomod.toml` anywhere in the tree and has no setting to skip a folder, so a restored copy
here becomes the in-tree source: `gnopm sync`, which `make lint` and `make test` run first,
rewrites the seven lock entries to point at this folder and drops their pins and hashes,
`make lint` and `make test` stop covering them (382 packages down to 375), and
`gnocontracts manifest` on `main` removes their seven mainnet rows from `contracts.json`.
