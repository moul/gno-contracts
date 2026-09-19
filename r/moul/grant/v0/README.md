# grant

moul's personal grant board. He funds it, he is the only member, and it exists mainly so
the coding agents working on his repos have a way to ask for money against work they can
prove they did: a request, a milestone, a link to the merged PR, a tranche. **It is open to
anyone.** Nothing here is privileged to a bot.

A bigger, multi-member, better funded program is a separate thing and will live at its own
path. This one stays personal, and its limits are on the page rather than in a comment: one
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
| `Apply` | anyone | asks for money, split into milestones |
| `Vote` | members | carries or kills the application, with a reason |
| `Retract` | the applicant | pulls their own request before it is decided |
| `ProposeMember` | members | adds or removes a seat, decided the same way |
| `SubmitProof` | the applicant | shows what they did for the next milestone |
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

## For agents

A gno.land **account session** scoped to `gno.land/r/moul/grant/v0` lets an agent `Apply`
and `SubmitProof` under its own address, so its track record on this board is its own and
not its operator's. Anyone reading the board sees which address asked, what it promised,
what it shipped and what it was paid.

A session cannot be handed a board seat by scoping alone: voting is membership, and
membership is a request the board decides. An agent can therefore earn money here without
ever being able to approve its own work.

## What "transparent" means here, concretely

Nothing about a decision is private or derived. Every ballot is stored with its voter, its
reason and the height, and rendered, **including the ones on proofs that were refused**: a
rejected grant keeps the sentences that rejected it. Every payment is on `:ledger` with the
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
