# `gno.land/p/moul/x/games/accrual/v0`

**Stock that fills at a rate while nobody is playing**: `New`, `Rate.Advance`, `Rate.At`,
`Rate.Full`.

```go
import "gno.land/p/moul/x/games/accrual/v0"

r, _ := accrual.New(1, 60, 120)              // 1 ore a minute, the mine holds 120
stock, anchor, _ := r.Advance(0, t, t+3599)  // → 59, t+3540   (the anchor is NOT t+3599)
stock, _ = r.At(stock, anchor, t+7200)       // → 120, capped, and nothing was written
full, _ := r.Full(0, t)                      // → t+7200, when production starts spilling
```

An idle game's resource field, a 4X's warehouse, a pet's hunger: all the same shape. Store
what you had and when, compute the rest on demand, and a player who is away for a month
costs the chain nothing. No cron, no keeper, no per-block hook.

**The anchor does not advance to `now`, deliberately.** It advances by the whole periods it
actually paid for, and the part-period in progress stays on the clock. That single decision
is the package:

> `Advance(s, a, c) == Advance(Advance(s, a, b), b, c)` for `a <= b <= c`

How often you call must not change where you end up. Re-anchor to `now` instead and the
division truncates, so every call forfeits the fraction it landed in. Run backwards on a
decaying stat it stops being unfair and starts being free: `r/moul/x/daily/tamagotchi`
decayed by `elapsed/2` and `elapsed/3`, so at `elapsed == 1` it decayed by nothing, and
feeding once per block made the pet immortal while every other cadence died inside 240
blocks. Fixed in #221. The test here asserts the invariant over pseudo-random partitions,
because hand-picked spans are exactly the ones a wrong implementation already passes:
reverting the anchor fix turns four tests red.

Three more behaviours worth knowing before you use it:

- **`At` is `Advance` with the anchor discarded.** One implementation, two call sites. The
  same realm's second bug was a Render with its own copy of the decay, so the page showed a
  state the next call would not honour; two implementations of one rule means one of them is
  the stale one somebody acts on.
- **A capped rate never returns `ErrOverflow`.** However long the player was away, the
  answer is the cap, so a realm can size a warehouse without also bounding its own lifetime.
  Only an uncapped rate can run out of `int64`, and it says so rather than wrapping into a
  negative stock.
- **`now` before the anchor is an error, not zero elapsed.** Time running backwards means a
  stored anchor from another clock or a test that rewound. Swallowing it hides the bug for
  as long as the stock looks plausible.

Everything is O(1) in elapsed time, which is a requirement rather than an optimisation:
`Render` runs under a query gas limit and may not write, so the player who comes back after
a month is exactly the one whose page would time out if the projection were iterative.

Times are `int64` in the caller's unit. Prefer a timestamp over a block height: a
height-denominated rate reprices itself every time the chain's block time moves, and
gno.land's has moved from about 4.1s to 3.405s inside a month.

Live demo: [r/moul/x/games/idle](/r/moul/x/games/idle/v0).
