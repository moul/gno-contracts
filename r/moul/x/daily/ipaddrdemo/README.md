# `gno.land/r/moul/x/daily/ipaddrdemo/v0`

**Demo of the [`p/moul/x/daily/ipaddr`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/ipaddr)
library.** No addressing logic of its own, no state, so `Render` is
deterministic.

Three things on the page:

- **The registry.** All sixteen IANA special-purpose blocks with their real
  bounds and sizes, computed rather than transcribed. The row that earns its
  place is `172.16.0.0/12`: it ends at 172.31.255.255, so `172.32.0.1` is a
  public address that a hand-written check on the second octet usually
  swallows.
- **Inside one prefix.** `192.168.1.37/24`, written with a host octet rather
  than its network address, so the page shows the masking happening instead of
  describing it.
- **A range is almost never a prefix.** `10.0.0.5` to `10.0.0.20` is sixteen
  addresses and five CIDR blocks, widening then narrowing again because each
  block has to start on its own alignment.

`Render` takes a query: an address (`/8.8.8.8`), a block (`/172.16.0.0/12`), or
a range (`/10.0.0.5-10.0.0.20`). All three are caller text, and all three can
fail to parse, so the refusal path echoes the query through `ui.Inline` rather
than into a code span a backtick in it could close. `escape_test.gno` pins all
three branches; `query_test.gno` pins the views themselves, on the cases where
the arithmetic has an exception (a `/31`, the doubly-classified
255.255.255.255, a backwards range).
