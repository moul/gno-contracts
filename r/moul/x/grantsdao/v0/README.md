# grantsdao

A working grant program: a treasury anyone can top up, a board of members who decide in
public, and applicants who get paid one milestone at a time, each tranche against a proof
the board accepted.

The state machine lives in [`p/moul/x/grants/v0`](/p/moul/x/grants/v0), which is pure and
knows nothing about coins. This realm is the half that touches the chain: it owns the
singleton board, turns the caller into an address and the block into a height, moves ugnot
through the banker, and renders the whole thing.

## The flow

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
gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Fund -send 5000000ugnot …
gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Apply \
  -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' …
gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Vote -args 4 -args true -args 'reason' …
gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func SubmitProof \
  -args 4 -args 0 -args url -args 'https://…' -args 'what it is' …
gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Review -args 4 -args 0 -args true -args 'looks done' …
```

## What "transparent" means here, concretely

Nothing about a decision is private or derived:

- **Every ballot** is stored with its voter, its reason and the height it was cast at, and
  `Render` prints all of them, including the ones on proofs that were **refused**. A
  rejected grant keeps the sentences that rejected it.
- **Every payment** is appended to a ledger (`:ledger`) with the height, the request, the
  milestone, the payee and the amount, and also emits a `Release` event. Every donation
  through `Fund` is on the same page with the donor's address.
- **The treasury panel** prints the balance next to what the board has already promised, so
  an over-committed board is visible on the front page rather than discovered at payout
  time.
- **A voter who has left the board** is still shown, marked, with their ballot no longer
  counting. See `Standing` in the library.

## The treasury is not escrowed

Approving a grant promises money; it does not move or lock any. `Committed()` is what
approved-but-unreleased milestones add up to, `Available()` is the balance minus that, and
**`Available()` can go negative**. That is deliberate: a board that can only approve what it
already holds cannot approve anything before a donor shows up.

The cost is that a release can come due against an empty treasury. `Review` handles it by
checking *before it records anything* whether this verdict would release a tranche, and
refusing the call outright if the balance cannot cover it. Nothing is written, no milestone
is marked released that nobody can settle, and the same member can still record a
**refusal** (which costs the treasury nothing).

## The seeded state

The realm is not an empty page at deploy. `seed()` writes three requests: a membership
change the board carried, a grant it carried that is mid-delivery with a proof under
review, and a grant it turned down. **No coins moved for any of it** (a seed can write
votes and proofs, it cannot mint a treasury), so the ledger starts empty and the seeded
grant shows on the front page as a promise the board has not yet been funded to keep.

The seeded applicants are **placeholder addresses**, derived the way `p/nt/testutils`
derives a test address: readable bytes, valid checksum, and no key behind them. They cannot
sign, so a seeded request can never be carried further by its applicant, and a tranche
released to one would go nowhere. Every seeded request page says so in a callout.

## Who the caller is

Every actor is `PreviousRealm().Address()`, the immediate caller. Called through another
realm, that is the calling **realm**, not the user behind it. A realm can therefore be a
member, an applicant or a donor, which is a feature (a DAO can hold a seat) and worth
knowing before you wire one up.
