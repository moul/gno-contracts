# `gno.land/p/moul/x/social/patron/v0`

**The engine behind recurring support for a builder**: a plan somebody
subscribes to, period after period, paid in ugnot. `NewRegistry`, `Open`,
`Subscribe`, `Close`, `Reopen`, `Withdraw`, plus the reads a page needs.

```go
r := patron.NewRegistry()
id, _ := r.Open(creator, "monthly support", "what you get", 1_000_000, 43_200)

pay, _ := r.Subscribe(id, supporter, 2_500_000, height) // 2 periods, 500000 change
plan, _ := r.Get(id)
plan.IsActive(supporter, height)                        // true until pay.PaidThrough

r.Withdraw(creator)   // the earnings
r.Withdraw(supporter) // the change
```

**There is no cron on chain, so a renewal is a pull and not a push.** Nothing
here can charge anybody, and nothing could: a native coin cannot be pulled at
all, since a banker may only spend its own realm's address. A supporter renews
by signing another payment. That is the one sentence a reader arriving from
web2 needs, because the thing they are picturing, a standing mandate on a card,
does not exist anywhere on this chain.

**What it adds over a tip jar.**
[`r/moul/x/daily/tipjar`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/tipjar)
is the one-shot version and is already live: one payment, a leaderboard, done.
The recurrence is the whole difference here. A plan carries a price per period
and a period measured in **blocks**, a payment buys whole periods of it, and
the registry answers "is this address active right now" at any height. It is
the one piece of the `x/social` family that produces a recurring write rather
than a one-off.

**The period arithmetic is the part that has to be right**, so it is stated
rather than left to the reader:

- A payment buys `floor(sent / price)` **whole** periods and refuses anything
  short of one. Rounding is **down**, and the remainder under one period is
  credited back to the supporter rather than kept. Keeping it would be a fee
  nobody agreed to, and a silent fee is the thing a subscription realm must not
  have.
- The extension starts from **whichever is later, now or the current
  `paidThrough`**. Renewing early therefore adds a whole period on top of what
  is left instead of discarding it; renewing after a lapse starts from now,
  because the gap was never paid for.
- `IsActive` is strict: an address paid through height `h` is active at `h-1`
  and not at `h`. One rule at both edges, so two periods never overlap by a
  block.
- `Subscribe` computes the extension through
  [`xmath.MulDiv`](https://github.com/moul/gno-contracts/tree/main/p/moul/xmath).
  The division there is exact by construction, so nothing is rounded a second
  time; what it buys is the 128-bit intermediate, because `spent *
  periodBlocks` overflows an `int64` for a plan priced in whole GNOT with a
  period measured in months, and the naive product wraps to a plausible-looking
  height rather than an obviously wrong one.

**Earnings are credited at the moment of payment, not streamed.** The creator
can withdraw the whole price the instant it arrives, so a supporter who stops
being active is **not** refunded and no part of a paid period ever comes back.
That is a real limitation, and it is v0 on purpose: escrowed streaming, where
the creator claims only what has elapsed and the supporter cancels and reclaims
the rest, needs a claim schedule and a refund path. That is a larger realm than
this one, not a flag on it, and it is the v1.

**The trap it avoids: money leaves by pull, never by a push loop.** Nothing
here moves a coin. `Subscribe` credits a
[`pullpayment`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/pullpayment)
ledger, and `Withdraw` zeroes a credit and reports what was owed so the holding
realm transfers afterwards, with the balance already gone when control leaves.
A realm that looped over payees instead would fail entirely on one unpayable
address and hand a griefer a cheap denial of service.

**A title and a description are attacker-controlled markdown.** `ValidTitle`
and `ValidDescription` bound them and refuse control characters, which is a
different protection from escaping and not a substitute for it. One note for
whoever renders them: `md.Link` escapes its text with the *inline* escaper, and
the inline escaper does not touch a pipe, so a caller's title carried inside a
link inside a table cell still opens a column. In a table, the link text has to
be something the realm owns and the title gets `ui.Cell`.

## v0 ships no token, and that is the answer rather than a gap

A creator coin minted per period paid is the easy half. The sink is not: what a
supporter would redeem it for is a promise the creator makes off chain, and a
token whose only sink is a promise is a scoreboard with a price. It would also
compete with the thing that already works here, which is that a period is paid
in ugnot and either active or not.

What would change the answer is a **redeem the creator can be held to on
chain**: a queue position the realm enforces, an allocation it hands out, an
access gate another realm checks before it lets somebody in. Any of those turns
the coin into a claim rather than a souvenir, and at that point the mint rule,
the sink and the buyer can all be named.

Until one of them exists, the condition is the deliverable. The sibling package
`gno.land/p/moul/x/social/coin/v0` is where that gets enforced: a GRC20 that
refuses to exist until its mint rule, its sink and its buyer are declared. This
package does not import it, and will not until there is something true to
declare.

**Live realm:** [`r/moul/x/social/patron`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/social/patron)
· render it at [`/r/moul/x/social/patron/v0`](https://gno.land/r/moul/x/social/patron/v0).
