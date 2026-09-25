# GNOT faucet

A two-step, on-the-record way to get a small amount of GNOT to someone who has
none: anyone files a request on their behalf, an approver releases it, and both
halves stay on the page with a reason attached.

It exists because the accounts that most need a first coin are exactly the ones
that cannot ask for it. An empty account cannot pay the gas to call anything,
so `Request` takes the recipient as an argument and the filer pays for the ask.

This is not the grant board. The grant board weighs work against milestones and
proofs; this hands over pocket change so somebody can try the chain at all.

## The float

The faucet spends only what has been sent to its own package address, never the
approver's balance. Top it up with a plain bank send to that address, or with
`Fund` if you want the donation on the record. `Withdraw` takes it back, to the
owner and nowhere else.

## `v0` is on chain, frozen, and not this code

`gno.land/r/moul/faucet/v0` was published to mainnet at block 245194, two
minutes before the commit that added `private = true`. `private` is read off the
submitted package at deploy time, so the chain never saw the flag, and a public
path cannot later be redeployed as a private one or at all. `v0` is therefore
frozen forever, carrying an unbounded `Render` whose page and query gas grow
with every request.

That is what this `v1` exists to replace. Its float lives at a different
address, its float was moved by hand, and `v0`'s page still answers with an
empty board. **If you found `v0` first, this is the live one.**

The lesson is cheap to state and was not cheap to learn: **publish from the
commit you mean to publish**, because for a public realm the deploy is the last
moment anything about it can change.

## It is a private realm

`gnomod.toml` declares `private = true`, so the creator can redeploy this path
with corrected code rather than abandon it for a `v2`. On a realm holding other
people's rent money that is worth having, and `v0` is the demonstration of what
its absence costs.

What a redeploy costs is exact, and measured rather than assumed:

| across a redeploy | |
|---|---|
| the code | replaced |
| the float | **kept** — coins live at the address, which is bank state |
| requests, approvers, counters | **wiped** — every initializer runs again |
| storage deposit | accumulates; the old objects are not evicted, so nothing refunds them |

So a bug fix here is cheap in money and expensive in history. That is the right
way round for a faucet and the wrong way round for anything whose ledger people
rely on, which is why this is a per-realm decision and not a repo-wide default.

Private is **one-way and set at the first deploy**: a public path can never
become private, nor the reverse. And no other realm may import this one or hold
a reference to its objects. Nothing else here does, and reading it from outside
is unaffected: `vm/qrender` and `vm/qeval` both work normally on a private
realm.

## The two calls, and why they travel together

| call | who | what it does |
|---|---|---|
| `Request(to, amount, reason)` | anyone | files an ask, returns its id, moves no money |
| `Approve(id, to, amount)` | an approver | pays it out of the float |
| `Deny(id, why)` | an approver | closes it unpaid, with the reason on the page |
| `Fund()` | anyone, payable | credits the float and emits an event |
| `Withdraw(amount)` | the owner | returns float to the owner |
| `AddApprover` / `RemoveApprover` / `SetMaxPerRequest` | the owner | the knobs |

A tm2 transaction carries a list of messages, runs them in order, and stops at
the first failure; a failed transaction writes none of their state, only the
fee and the sequence survive. So `Request` and `Approve` sent as two messages of
one transaction either both happen or neither does, and the common case is a
single signature.

### The id the second message cannot know

`Approve` names a request by id, and message 2 of a transaction cannot read what
message 1 returned. The caller reads `NextID` before signing and writes that
number into the approval, which is a race: another request landing in between
shifts the id, and the approval would pay a stranger.

That is why `Approve` also takes the recipient and the amount it believes it is
approving, and aborts when the stored request disagrees. The race then costs a
failed transaction instead of the wrong person's money.

## Calls

```sh
# Ask, on someone else's behalf. Amount is in ugnot.
gnokey maketx call -pkgpath "gno.land/r/moul/faucet/v1" -func Request \
  -args "g1..." -args 100000000 -args "no gas, wants to try the chain" \
  -gas-fee 30000ugnot -gas-wanted 3000000 -broadcast -chainid gnoland-1 moul

# What id the next request will get, so an approval can be signed alongside it.
gnokey query vm/qeval -data 'gno.land/r/moul/faucet/v1.NextID()'

# What the float holds.
gnokey query vm/qeval -data 'gno.land/r/moul/faucet/v1.Balance()'

# The page.
gnokey query vm/qrender -data 'gno.land/r/moul/faucet/v1:'
```

## Reading it

`Render("")` is the board: float, open requests, decided ones, approvers.
`Render("req/<id>")` is one request, with its reason and, if it was refused, why.

Each table shows at most 20 rows, open oldest first and decided newest first,
and says how many it is hiding. The cap is not cosmetic: the totals come from
the realm's counters, so the walk stops once a table is full. A board that
rendered every request ever filed would grow its page and its gas cost forever,
and this path is permanent. Anything hidden is still reachable by id.

Every caller-supplied string on those pages is escaped before it is rendered.
A reason is arbitrary text from an arbitrary account and `Render` output is
markdown that gnoweb parses, so an unescaped one can plant a link, an image
beacon or page chrome on a page the realm signs for. This path is permanent, so
that bug could only ever be fixed at a new path.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/faucet/v1 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/faucet/v1/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
