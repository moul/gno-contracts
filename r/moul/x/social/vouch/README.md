# `gno.land/r/moul/x/social/vouch/v0`

**A web of trust other realms gate on.** One address vouches for another, in
writing, optionally with GNOT locked behind it. Any realm can then ask whether
an address is vouched for by at least N distinct people and refuse to serve it
if it is not.

```go
import "gno.land/r/moul/x/social/vouch/v0"

func Claim(cur realm) {
	if !vouch.IsTrusted(cur.Previous().Address(), 2) {
		panic("get two people to vouch for you first")
	}
	...
}
```

That is the whole product. It exists because the apps beside it do not have a
sybil gate: a realm that mints a point per distinct replier is farmed by two
addresses replying to each other, and a realm that counts one vote per address
is farmed by holding a hundred addresses. Neither can fix it alone, because
neither knows anything about the people behind the addresses.

## The API

| write | |
|---|---|
| `Vouch(target, reason)` | payable. Records the caller's vouch. Coins sent are locked as a bond on it. Vouching again updates the reason and adds to the bond |
| `Revoke(target)` | removes the caller's vouch and credits the bond back to them |
| `Withdraw()` | pays the caller every bond their revocations freed |

| read | |
|---|---|
| `IsTrusted(addr, min)` | **the gate.** At least `min` distinct vouchers, `min` below one read as one |
| `ScoreOf(addr)` | distinct inbound vouchers |
| `BondedFor(addr)` | total ugnot bonded on them |
| `VouchedBy(addr)` / `VouchesOf(addr)` | the two directions, sorted |
| `Mutual(a, b)` | whether they vouch for each other |
| `ReasonFrom(from, to)` / `BondFrom(from, to)` | one edge |
| `Count`, `People`, `Owed`, `TotalBonded`, `TotalOwed` | the totals |
| `Badge(addr)` | the one-line trust mark, for a host realm's own page |

The engine is `p/moul/x/social/vouch/v0`,
which holds the graph, the validation and the refund ledger and takes the
height, the caller and the bond as arguments. This realm is the chain wiring
and the `Render`.

## Three traps it avoids

**A score counts people, not vouches.** A second vouch from the same address to
the same target is an edit: the reason is replaced, the bond is added to, and
the score does not move. Without that, the gate measures transactions, and
transactions are for sale.

**It never loops and sends.** `Revoke` credits a ledger and `Withdraw` pays one
payee, zeroing the credit before the coins leave. A realm that sent on revoke
would hand control to the recipient mid-transition, and a recipient that
refuses coins could make revoking impossible.

**A realm cannot forward a bond.** The payment envelope belongs to the
transaction, not to the frame, so a realm that was itself paid and then calls
`Vouch` would report coins sitting at its own address. This realm refuses that
call outright rather than quietly reading the bond as zero. A realm may vouch;
it may not vouch while holding somebody else's payment.

## No slashing in v0, and that is the hard part

A bond is value at risk only in the sense that it is illiquid: it can be
recovered by revoking, and nothing can take it away. That is not an oversight,
and the missing half is not the accounting.

Slashing needs an arbiter, somebody who decides that a vouch was a lie. A DAO
vote is a popularity contest against whoever is unpopular this month. A
challenge market pays whoever is loudest and turns the graph into a griefing
surface. An oracle is one key that can confiscate anybody's money. Shipping any
of them by default would be shipping the wrong one, so v0 ships the part that
is uncontroversial: who said what, who put money behind it, and the gate that
reads it.

The bond still earns its place without slashing. An illiquid deposit is a cost
a hundred throwaway addresses cannot all pay at once, which is exactly the
shape the gate is defending against.

## And can it have a token?

**No, and the reason is the point.** Every app in this family is asked the same
question, and here the honest answer is no. A transferable vouch is a bought
reputation: the moment a vouch can be sold, the score stops measuring what it
claims to measure, and what it measures instead is who had the most money this
week. That is the one failure mode a sybil gate cannot survive, because it is
not a degradation, it is the attack.

The bond is GNOT. It is value at risk without being a market in trust itself:
you can lock your own money behind a claim, and you cannot sell the claim.

What would change the answer is a token whose **only** use is being locked and
slashed, with no transfer path that buys standing, and that needs an arbiter
first, because without something that can slash it the token is a scoreboard
with a price. If that day comes, the shape to issue it under is
`p/moul/x/social/coin/v0`, a sibling package: a GRC20 that refuses to exist
until its mint rule, its sink and its buyer are written down. It is not
imported here, deliberately. Saying no with a reason is the deliverable.

## Public, not private

Realms in this family default to `private = true`, which buys redeploy in
place. This one is public and its `gnomod.toml` argues why: a private realm
cannot be imported, and a gate that can only be read over the chain is not a
gate, since a realm cannot pause mid-transaction to query itself. The second
reason settles it: the graph and the refund ledger are package-level variables
while the bonded ugnot sits at the realm's address, so a redeploy would wipe
the record of whose money that is and keep the money. A realm holding somebody
else's coins should not be able to forget who they belong to.
