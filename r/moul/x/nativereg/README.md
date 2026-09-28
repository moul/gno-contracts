# `gno.land/r/moul/x/nativereg/v0`

**The metadata a native coin does not have.**

`/gno.land/r/moul/x/moultest/v0:moultest` is the entire object. The chain stores a
string and a balance: no name, no symbol, no decimals, no icon, no link to the
issuer. A wallet showing you that balance has only the path to print.

This realm is where a denom says what it is. It is the mirror of
[`r/nt/grc20reg`](https://gno.land/r/nt/grc20reg/v0), and the two solve opposite
problems: a GRC20 carries its own name and is hard to **find**, so that registry
maps a key to an object; a native denom is trivial to find and carries **no**
name, so this one maps the denom to what it means.

## Registration is proved, not claimed

A denom embeds the package path of the realm allowed to issue it, verbatim:
`"/" + pkgPath + ":" + baseName`. So the issuer is readable from the string, and
`Register` simply requires the caller to be it. No allowlist, no owner, no
signature scheme.

```go
import "gno.land/r/moul/x/nativereg/v0"

func init(cur realm) {
    nativereg.Register(cross(cur), Denom, "My Coin", "MINE", 6,
        "one line about what it is for")
}
```

A user account cannot register anything, not even a denom it holds every unit of:
there is no package path in a user call to compare against. What is being
described is the issuance, not the holding.

`IssuerOf(denom)` answers the same question for a denom nobody ever registered,
which is the case that matters: given a balance you did not ask for, that is how
you find the code that can take it away.

## Facts and hints

`Denom` and `Issuer` are facts, because the chain enforces the relation between
them. Everything else is whatever the issuing realm chose to say, and `Decimals`
in particular is a **display hint with nothing behind it**: the bank has no notion
of divisibility, so a coin wrapped out of a 6-decimal GRC20 is still counted in
whole units by every balance query.

Trusting an entry means trusting the realm that wrote it, exactly as much as
holding its coin already means trusting it not to call `RemoveCoin` on you.

`?<denom>` shows one entry, `?<pkgpath>` shows everything one realm issues.
