# `gno.land/p/moul/x/envelope/v0`

**Reading and forwarding the coins a transaction attached to a call.** The `-send`
field of a `MsgCall`, credited to the called realm's address before a line of its
code runs.

"Payable" is not a keyword in gno, it is a runtime fact: the VM rejects a
`MsgCall` that carried coins the callee never looked at, and reading the envelope
is what counts as looking. So every realm taking payment writes the same three
things by hand. This is those three things.

```go
import "gno.land/p/moul/x/envelope/v0"

func Publish(cur realm, slug string) {
    envelope.RequireExactly(Price, 500)   // aborts, naming the flag, if unpaid
    // ...
}

func Route(cur realm, to address) int64 {
    return envelope.ForwardAll(0, cur, to, Denom)  // spends the envelope, nothing else
}
```

| | |
|---|---|
| `Amount` · `All` · `IsEmpty` | read it, and make the call payable |
| `Require` · `RequireAtLeast` · `RequireExactly` | read it and abort usefully when it is wrong |
| `Only` | refuse an envelope carrying anything else |
| `Forward` · `ForwardAll` | spend it, and nothing but it |
| `BalanceOf` | what an address holds of a denom, from the bank |

## Why the abort messages are long

`Require` aborts with `attach coins with -send <amount>/gno.land/r/...:coin`. The
abort is the realm's user interface at the moment somebody got it wrong:
"insufficient funds" sends them to their wallet, naming the flag sends them to the
fix.

`RequireExactly` refuses an **over**payment too. A realm that silently keeps the
excess has invented a fee nobody agreed to, and one that refunds it has to move
coins back out, which is a second failure mode.

## Two things that are not obvious

**`Forward` is about who entered, not how deep you are.** It mints a
`BankerTypeOriginSend` banker, which `NewBanker` allows only when
`rlm.Previous().IsUserCall()`, and that is literally `pkgPath == ""`. So a realm
may pass its `cur` down through as many of its own helpers as it likes (measured
at three nested calls, through a function value, and through a closure), and it
may **not** forward an envelope handed to it by another realm, nor be driven from
`gnokey maketx run`, whose entry package is a code realm.

**`Forward` is tested from a realm, not from here.** Minting the banker calls
`rlm.Previous()`, and a `p/` package's test has no realm frame to walk: it dies
with `frame not found: cannot seek beyond origin caller override`. The tests live
in [`r/moul/x/nativeify`](https://gno.land/r/moul/x/nativeify/v0), which is also
the realm that uses it.

Related: a native coin is push-only, so the envelope is its entire inbound path.
There is no allowance for one, which is what
[`r/moul/x/nativeify`](https://gno.land/r/moul/x/nativeify/v0) is about.
