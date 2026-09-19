# `gno.land/p/moul/x/framelab/v0`

A 30-line probe for one language property: **pure-package code runs in the frame
of the realm that imported it**, when that realm forwards its own `cur`.

The instance-per-realm pattern (`p/moul/x/pair/v0`) rests entirely on this. If
the frame shifted, a shared `p/` could not move an instance's funds and every
instance would have to carry its own copy of the logic.

`r/moul/x/framelab/probe/v0` is the realm that exercises it, and asserts:

- pure-package code reports the **instance realm's** path and address;
- the forwarded `rlm.IsCurrent()` is still true, so grc20's spoof check passes;
- a `TransferFrom` issued from inside the pure package credits the **instance
  realm's** own address.

It also pins the two rules found while proving it: a pure package cannot declare
a crossing function (`func F(cur realm, ...)`), and the realm parameter cannot be
named `cur` there. Hence the `(_ int, rlm realm, ...)` shape used throughout.
