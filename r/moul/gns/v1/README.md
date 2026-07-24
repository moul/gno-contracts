# GNS — Gno Name Service

GNS is an **ENS-equivalent naming system expressed as a single Gno-native
realm**. It provides the capabilities mainstream ENS users rely on —
registration, renewal, expiry & grace, forward/reverse resolution, primary
names, typed and arbitrary records, subnames with policies, delegated
operators, pagination and events — but implements all of it
through **one realm, one ownership model, one record model, one authorization
function and one registration lifecycle**, rather than a collection of
emulated ENS contracts.

Package path: `gno.land/r/moul/gns/v1` · possible future target: `gno.land/r/gnoland/gns`.

Built and tested against **gno 0.9 / master** (`chain`, `chain/banker`,
`chain/runtime`, `gno.land/p/nt/avl/v0`).

## What is and isn't compatible with ENS

GNS deliberately does **not** aim for byte-for-byte ENS/Ethereum compatibility.

**Equivalent user capabilities** (different implementation):

| ENS capability | GNS |
|---|---|
| Register / renew second-level name | `Register`, `Renew` |
| Expiration + grace period | stored expiry + configurable grace |
| Commit–reveal | `Commit` + `Register` (see preimage below) |
| Owner / transfer | `OwnerOf`, `Transfer` |
| Resolver records | built-in typed records (no pluggable resolver) |
| Multichain addresses | `SetCoinAddress` keyed by coin type |
| Text / content hash / pubkey / ABI / interface | typed setters/getters |
| Arbitrary records | `SetRecord` with reverse-DNS namespaces |
| Reverse resolution + primary name | `SetPrimaryName` / `PrimaryName` (forward-verified) |
| Subnames + subname registrar | hierarchical names + `RegistrationPolicy` |
| Wrapped / emancipated names | explicit `ControlPolicy` flags + `LockPolicy` |
| Delegated managers | `SetOperator` with per-permission grants |
| Multicall | not in-realm — loop a typed setter from one `gnokey maketx run` |
| Wildcard resolution | `Resolve(..., NearestAncestor)` |
| Events | append-only `Event` log + native `chain.Emit` |

**Explicitly NOT included** (Ethereum-specific or out of scope for v1): DNSSEC
import, DNS registrar, CCIP-Read, L2 resolution, NFT/ERC-721 ownership, Ethereum
ABI compatibility, Unicode/emoji names, governance DAO, auctions, secondary
marketplace, and arbitrary custom-resolver execution.

## Names

- Second-level names are stored **string-native and suffix-free**: `alice`,
  not `alice.gno`. Display clients may append a `.gno` suffix; it is presentation
  only.
- Hierarchy is `label.parent` (`wallet.alice`, `prod.api.company`).
- Labels: lowercase `a–z`, digits `0–9`, and `-` (not leading/trailing).
  1–63 bytes per label, ≤255 bytes and ≤16 labels total. Input is lowercased;
  **non-ASCII is rejected**. All canonicalization happens in `Normalize`.

## Lifecycle

`Available → Committed → Active → Grace → Expired → (recycled)`, plus `Deleted`
for removed subnames and `Reserved` for admin-held names.

- **Active**: `now < ExpiresAt`. Owner and permitted operators may mutate.
- **Grace**: `ExpiresAt ≤ now < GraceEndsAt`. Only renewal by the existing owner;
  not registrable by others.
- **Expired**: `now ≥ GraceEndsAt`. Registrable again; old state is cleared on
  re-registration and `Generation` is incremented so clients can detect the
  replacement. Subnames carry `ParentGeneration` and do **not** silently
  survive a recycled parent.

## Commit–reveal

The commitment binds the reveal so observers can neither copy nor front-run it:

```
commitment = sha256hex( name | owner | duration | secret | recordsHash | policyRevision )
```

where `|` is `"|"`, `owner` is the bech32 string, integers are base-10, and
`name` is the **normalized** name. Use the on-chain helper `MakeCommitment(...)`
to compute it identically to what `Register` recomputes at reveal.

## Pricing

Deterministic and boring — no oracle, no USD, no auction:

```
price = duration × BasePricePerSecond × lengthMultiplier(label)
```

Default length multipliers: 1→100, 2→25, 3→5, 4→2, 5+→1. `Price(name, duration)`
returns a quote; `Register` always recomputes from state and rejects a stale
`policyRevision`.

## Authorization

Every mutation funnels through one internal `authorize(caller, name, permission)`
with a fixed authority order:

1. **Admin** — emergency/protocol operations only; **never** routine power over
   user names or records (admin cannot confiscate).
2. **Direct owner** of an active name.
3. **Active operator** holding the matching permission.
4. **Parent authority**, only where the child `ControlPolicy` allows it.

## Gno-specific deviations from the spec

The spec is written with Ethereum/Go idioms; these are the deliberate,
gno-correct adaptations:

- **Mutations panic, they don't return `error`.** In gno only a panic/abort
  reverts state, so state-changing crossing functions (those taking `cur realm`)
  panic with a **stable machine-readable error code** (`unauthorized`,
  `name_unavailable`, `commitment_missing`, …). Read/quote functions return
  `(value, ok)` or `(value, error)` normally.
- **`avl.Tree` instead of Go maps** for every enumerable collection, so all
  listing APIs (`NamesByOwner`, `Subnames`, `TextKeys`, `CoinTypes`,
  `Operators`, `EventsAfter`) are ordered, bounded, and cursor-based — there is
  no unbounded "return everything" query.
- **String-native storage** rather than namehashes (hashing is used only for
  commitments and event digests).

## Public API (summary)

Read: `Normalize`, `Status`, `Exists`, `OwnerOf`, `GetName`, `Resolve`,
`Address`, `CoinAddress`, `Text`, `ContentHash`, `PublicKey`, `ABI`,
`Interface`, `Record`, `PrimaryName`, `Price`, `MakeCommitment`,
`CommitmentStatus`, `NamesByOwner`, `Subnames`, `TextKeys`, `CoinTypes`,
`Operators`, `EventsAfter`, `EventsForName`, `Render`.

Mutations (crossing): `Commit`, `Register`, `Renew`, `Transfer`,
`CreateSubname`, `DeleteSubname`, `SetRegistrationPolicy`, `LockPolicy`,
`SetOperator`, `RemoveOperator`, `SetPrimaryName`,
`ClearPrimaryName`, and the typed record setters (`SetAddress`, `SetText`,
`SetCoinAddress`, `SetContentHash`, `SetPublicKey`, `SetABI`, `SetInterface`,
`SetRecord`, `SetTTL`).

Admin (two-step transfer): `SetPaused`, `SetRegistrationOpen`, `SetPricing`,
`SetTreasury`, `ReserveName`, `SetLimits`, `TransferAdmin`, `AcceptAdmin`.

## Render explorer

`Render(path)` serves a read-only Markdown explorer:

```
/                 overview + stats
/name/<name>      owner, status, expiry, records, subnames
/address/<g1...>  verified primary name + owned names
/available/<name> availability + price
/events           recent events
/help             API summary
```

## Building & testing

```sh
export GNOROOT=/path/to/gnolang/gno   # a gno master checkout
gno lint .
gno test .
```

The test suite covers the spec's critical invariants: single effective owner,
expired owners lose authority, grace names aren't re-registrable, parents can't
exceed child policy, permanent policies only tighten, forward-verified primary
names, single-use commitments, deterministic overflow-safe pricing, generation
recycling without stale-record leakage, bounded enumeration, and admin
non-confiscation.

> **Testing note.** Because this realm is developed outside the gno examples
> module, it uses local assertion helpers instead of `gno.land/p/nt/uassert`
> (whose working-tree copy fails to preprocess for external packages), and it
> unit-tests rejection paths against the internal error-returning helpers
> (`authorize`, `priceFor`, `available`, `mergeRestrictive`, …) rather than by
> catching crossing-boundary aborts. End-to-end abort/`// Error:` filetests can
> be added once the realm lives in-tree.

## Client caching

Reverse resolution is forward-verified on-chain, so clients and indexers may
safely cache the **user ↔ address** mapping:

- **positive match** (an address has a verified primary name, or a name resolves
  to an address): cache for up to **1 hour**;
- **negative result** (no primary name / no match): cache for only **1 minute**,
  so a freshly-set name becomes visible quickly.

## Status

This is a v1 implementation of the [GNS design spec][spec]. It is staged
for review; it is not deployed.

[spec]: https://gist.github.com/moul/1c160b2cb9ee080714b3d1933ddea60a

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/gns/v1 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/gns/v1/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
