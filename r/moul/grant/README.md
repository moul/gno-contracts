# grant

moul's personal grant board. He funds it out of his own pocket, he is the only member, and
it exists mainly so the coding agents working on his repos, and the people he already works
with, have a way to ask for money against work they can prove they did: a request, a
milestone, a link to the merged PR, a tranche. **It is open to anyone.** Nothing here is
privileged to a bot.

## What this is not

**Not a faucet, and not an official gno.land grant program.** It is one person's money,
sent by hand, mostly to people he already knows, and it is also a proof of concept for the
library underneath. There is no entitlement, no queue and no service level: a request can
sit here unanswered, or be refused with one line of reasoning and nothing further.

An official programme, where anyone asks for tokens and a DAO decides, is a separate thing
that does not exist yet. Neither this README nor the rendered page names a path for it: a
named path reads as a commitment, and nobody has made one. When it exists, it is another
~130-line realm over the same library, not a change to this one.

This board stays personal, and its limits are on the page rather than in a comment: one
member means "a majority of the board" is one signature, and the board page says so.

## What is here, versus in the library

Almost nothing. Every rule, every tally and every markdown page comes from
[`p/moul/grants/v0`](/p/moul/grants/v0), which is pure and has no idea coins exist. This
realm is the chain-facing half: it turns the caller into an address and the block into a
height, holds the one `Program`, moves ugnot through the banker, and emits events. Each
exported function is four to eight lines of glue.

That split is deliberate. The next board (multi-member, differently funded, maybe a
different denomination) is another file this short, not a fork of this one.

## Calling it

| Call | Who | What it does |
|---|---|---|
| `Fund` | anyone | sends ugnot to the treasury, with your name on the ledger |
| `Apply` | anyone | asks for money for yourself, split into milestones |
| `ApplyFor` | anyone | the same, for a different payee, with a reason |
| `Vote` | members | carries or kills the application, with a reason |
| `Retract` | the applicant | pulls their own request before it is decided |
| `ProposeMember` | members | adds or removes a seat, decided the same way |
| `SubmitProof` | the applicant or the payee | shows what was done for the next milestone |
| `Review` | members | accepts or refuses that proof; accepting **pays the tranche** |

Milestones are given to `Apply` as a string, `"design:100,ship:400"`, amounts in ugnot,
paid in the order written. The amount is whatever follows the **last** colon, so
`"port gno:land tooling:250"` parses the way it reads.

```sh
gnokey maketx call -pkgpath gno.land/r/moul/grant/v0 -func Fund -send 5000000ugnot …
gnokey maketx call -pkgpath gno.land/r/moul/grant/v0 -func Apply \
  -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' …
gnokey maketx call -pkgpath gno.land/r/moul/grant/v0 -func SubmitProof \
  -args 1 -args 0 -args url -args 'https://github.com/…/pull/1' -args 'merged' …
```

## Asking for someone else

`ApplyFor(beneficiary, reason, title, body, milestones)` files a request whose tranches pay
an address other than the caller's.

That is not a convenience. **An account with nothing in it cannot pay the gas to ask for its
first coins**, so on a board meant to fund empty accounts, someone else filing is the only
path that works at all. The same follows through the rest of the lifecycle: either the
applicant or the beneficiary may `SubmitProof`, because the payee may not be able to
transact until the first tranche lands.

Two rules keep the detour honest, and both are enforced by the library, not by this realm:

- **The reason is required**, and it is printed on the request page under its own heading.
  Nothing verifies it. It is a claim by the applicant, and printing it is what lets a member
  check it before voting.
- **Both addresses are barred from voting** on the request and on its proofs. A member paid
  by a request a friend filed is the same conflict of interest with one address in between,
  and the majority is recomputed over whoever is left.

```sh
gnokey maketx call -pkgpath gno.land/r/moul/grant/v0 -func ApplyFor \
  -args g1… -args 'their account is empty, they cannot pay the gas' \
  -args 'Fund a first key' -args 'so they can transact at all' -args 'first transfer:300' …
```

## For agents

A gno.land **account session** scoped to `gno.land/r/moul/grant/v0` lets an agent `Apply`,
`ApplyFor` and `SubmitProof` under its own address, so its track record on this board is its own and
not its operator's. Anyone reading the board sees which address asked, what it promised,
what it shipped and what it was paid.

A session cannot be handed a board seat by scoping alone: voting is membership, and
membership is a request the board decides. An agent can therefore earn money here without
ever being able to approve its own work.

## What "transparent" means here, concretely

Nothing about a decision is private or derived. Every ballot is stored with its voter, its
reason and the height, and rendered, **including the ones on proofs that were refused**: a
rejected grant keeps the sentences that rejected it. Every string a caller typed is escaped
before it renders, so a title or a proof cannot forge a link, a heading or a gnoweb tag on
a page the realm signs its name to. Every payment is on `:ledger` with the
height, the request, the milestone, the payee and the amount, and emits a `Release` event.
Every donation through `Fund` is on the same page with the donor's address. The treasury
panel prints the balance next to what is already promised, so an over-committed board is
visible on the front page instead of at payout time.

## The treasury is not escrowed

Approving a grant promises money; it does not move or lock any, so `Available()` can go
negative. The safety is at release time: `Review` refuses, before recording anything, a
verdict that would release a tranche the balance cannot cover. Nothing is written and no
milestone is marked released that nobody can settle. Full reasoning in the
[library README](/p/moul/grants/v0).

## Nothing is seeded

The board ships empty: one member, no requests, no history. What `Render("")` prints in the
pinned example test *is* the deployed state. For a board mid-flight, with ballots, refused
proofs and a paid tranche, see the `ExampleRenderer*` tests in `p/moul/grants/v0`; the
markdown comes from the same `Renderer`.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/grant/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/grant/v0/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
