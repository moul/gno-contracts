# `gno.land/p/moul/x/daily/ipaddr/v0`

**IPv4 addressing as integer arithmetic** (`ParseAddr`, `ParsePrefix`,
`Prefix.Contains`, `Classify`, `Summarize`).

An address is its 32-bit value and nothing else, so every operation is a shift
or a mask: no allocation on the hot path, no string ever round-trips through a
number to be compared, no float anywhere.

```go
import "gno.land/p/moul/x/daily/ipaddr/v0"

a, ok := ipaddr.ParseAddr("192.168.1.37")   // ok
_, ok = ipaddr.ParseAddr("010.0.0.1")       // false: leading zero

p, _ := ipaddr.ParsePrefix("192.168.1.37/24")
p.String()        // "192.168.1.37/24", kept as written
p.Masked()        // 192.168.1.0/24
p.Contains(a)     // true
p.Last()          // 192.168.1.255
p.Usable()        // 254

b, special := ipaddr.Classify(a)             // private-use, RFC 1918
ipaddr.Summarize(lo, hi)                     // a range, as CIDR blocks
```

**The parser is strict in the one place it matters.** A leading zero in an
octet is rejected rather than read as octal: `010.0.0.1` is 10.0.0.1 to a
browser and 8.0.0.1 to `inet_aton`, so a parser that accepts it has to pick a
reading, and whichever it picks disagrees with something else in the stack.
None of the C shorthands are accepted either, so there is no second spelling of
an address to argue about.

**A prefix keeps the address it was written with**, as Go's `net/netip` does,
so `192.168.1.37/24` renders back as itself. Everything that asks about the
block it names masks first: `Contains`, `First`, `Last` and `Count` all answer
for 192.168.1.0/24. `Masked` is the canonical spelling, `IsMasked` asks whether
you already have it.

`Summarize(first, last)` is the piece CIDR notation cannot express directly: an
arbitrary range almost never is a prefix, and `10.0.0.5` through `10.0.0.20`
takes five blocks. Each one is the widest block that can *start* at the cursor,
narrowed until it also *ends* inside the range. Both steps are load-bearing:
dropping the second returns four blocks for that range, one of which runs past
`10.0.0.20`.

Three small things the 32-bit arithmetic gets right and a hand-rolled version
usually does not. `Count` returns `uint64`, because `0.0.0.0/0` holds 4294967296
addresses and a `uint32` cannot count them. `Next` and `Prev` return a bool
rather than wrapping, so a walk to 255.255.255.255 terminates. `Usable` is the
full count for a `/31` and a `/32` rather than count minus two, since a `/31` is
a point-to-point link whose two addresses are both hosts (RFC 3021).

`SpecialBlocks` is the IANA IPv4 special-purpose registry, sixteen entries with
the RFC that defines each. `Classify` returns the **most specific** match, which
is why 255.255.255.255 comes back as the limited broadcast address rather than
as 240.0.0.0/4.

**IPv6 is deliberately out.** It is 128 bits, has no broadcast address and
carries a zone identifier, and folding the two into one type is what makes a
library like this hard to read.

**Live demo:** [`r/moul/x/daily/ipaddrdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/ipaddrdemo)
· render it at [`/r/moul/x/daily/ipaddrdemo/v0`](https://gno.land/r/moul/x/daily/ipaddrdemo/v0).
