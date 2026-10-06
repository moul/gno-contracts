# `gno.land/p/moul/x/social/curated/v0`

**The engine behind a list where being on it costs something**: `New`, `Apply`,
`Challenge`, `Vote`, `Resolve`, `Unlist`, `Withdraw`, plus the reads a page
needs.

```go
r := curated.New(1_000_000, 1000)              // deposit, challenge window
r.Apply("gnoswap", "/r/gnoswap", "the DEX", owner, paid, height)
r.Challenge("gnoswap", challenger, bond, height) // bond matches the deposit
r.Vote("gnoswap", voter, false, height)
r.Resolve("gnoswap", height+1001)                // credits the winner
```

**A list anybody can write to for free is a list nobody can read**, because the
cheapest way to be on it is to be on it a thousand times. A deposit does not
make an entry good. It makes a bad entry expensive to leave standing, because
somebody who disagrees can put the same amount at risk and take yours. The list
is worth reading in proportion to what it would cost to pollute it.

**This package moves no coins.** Every payout is a credit in an internal ledger
the payee collects with `Withdraw`, which zeroes it before returning the amount;
the realm sends afterwards. A registry that looped over winners and sent to each
one would fail entirely when one of them could not be paid.

Three rules worth knowing before you read the code:

- **A tie keeps the entry.** The incumbent wins ties, so a challenge that
  convinces nobody costs the challenger their bond. A challenge has to be worth
  making, which means losing one has to hurt.
- **An owner may not challenge their own entry.** It is free for them (a kept
  entry credits the owner the bond, which would be their own money back) and it
  would make the entry immune to a real challenge for the whole window.
- **A removed key is free to apply for again.** Burning the name forever
  punishes the name rather than the entry.

**Votes are one address, one vote, and that is sybil-prone**: a hundred
addresses are cheap and nothing here can tell them apart. Gating who counts is
the job of a vouch graph, `r/moul/x/social/vouch` in this family, and wiring the
two together is the first real upgrade this package wants. Voters are also paid
nothing in v0, which is the second.

`Locked()` plus `Owed()` is the solvency invariant: what the registry is holding
as deposits and bonds, plus what it owes people who have not collected yet,
should equal the realm's balance. The realm's test suite asserts exactly that
against the chain at every step of a full round.

**Live realm:** [`r/moul/x/social/curated`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/social/curated),
which carries the reasoning for why the bonds are GNOT and not a token of its own.
