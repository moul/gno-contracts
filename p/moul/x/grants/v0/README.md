# grants

A grant board governed by a member set: anyone may ask the board for money, the members
vote in the open, and the money leaves in tranches that each have to be earned by
producing a proof the members accept.

The package is **pure**. It holds no coins, reads no chain state, and imports nothing from
`chain`: the caller supplies the acting address and the block height, and the caller
performs the transfer. That is what makes the whole state machine unit-testable without a
node, and what lets the same board be driven by a realm, by a test, or by a different
payment rail.

Live demo: [`r/moul/x/grantsdao/v0`](/r/moul/x/grantsdao/v0).

## The lifecycle

```
Submit ──▶ Pending ──vote──▶ Approved ──┬─▶ SubmitProof ──▶ Review ──┬─▶ Released ─┐
             │                          │                            │             │
             │                          │                            └─▶ Refused ──┘
             │                          │                                (try again)
             ├──vote──▶ Rejected        └─▶ every milestone released ──▶ Completed
             └──Withdraw──▶ Withdrawn
```

A `Request` is a title, a body, and an ordered list of `Milestone`s, each with its own
amount. **Approving a request pays nothing**: it only makes the first milestone claimable.
To get a tranche the applicant submits a `Proof` (a URL, a hash, or plain text) and the
members review *that specific proof*. A refused proof does not kill the grant, it closes
one `Attempt`; the applicant submits another. Every attempt, accepted or not, stays on the
record with the ballots that decided it.

## Who may vote, and how many it takes

Every member, once, per decision. There is no changing your mind: that is the price of
every ballot being a permanent public statement, stored with its voter, its reason and the
height it was cast at.

**The party a decision is about is excluded.** An applicant does not vote on their own
grant, and the subject of a membership change does not vote on their own membership. The
bar is a majority of the addresses actually *eligible*, recomputed on every ballot, so a
member who applies shrinks the room rather than packing it, and a board that grows
mid-vote raises its own bar.

`Standing` counts only ballots from addresses that are members **right now**; decisions use
it. `Request.Tally` counts the raw record. The two differ exactly when a voter has since
been removed from the board: their ballot stays readable and stops carrying weight.

## Membership is a request like any other

`SubmitMemberChange` files a `KindMember` request. It asks for no money, and when it
carries it executes immediately, going straight to `Completed`. Only a member may file one:
opening a grant board's own composition to anyone with a keypair is how it gets captured.
The last member cannot be removed.

## Usage

```go
import "gno.land/p/moul/x/grants/v0"

board := grants.New(alice, bob, carol)

r, _ := board.Submit(dave, "Port the thing", "why it matters", []*grants.Milestone{
    grants.NewMilestone("design", 100),
    grants.NewMilestone("ship", 400),
}, height)

board.Vote(alice, r.ID, true, "cheap for what it tells us", height)
board.Vote(bob, r.ID, true, "agreed", height)   // majority of three: approved

board.SubmitProof(dave, r.ID, 0, grants.Proof{Kind: "url", Ref: "https://…", Height: height})
out, _ := board.Review(alice, r.ID, 0, true, "merged, I reviewed it", height)
out, _ = board.Review(carol, r.ID, 0, true, "confirmed", height)
if out == grants.Accepted {
    // r.Milestones[0].Released is now true; move the coins yourself.
}
```

`Decides` and `ReviewDecides` preview what a ballot *would* do without casting it, which is
how a caller checks a precondition it cannot roll back. The demo realm uses `ReviewDecides`
to refuse the verdict that would release a tranche its treasury cannot pay, rather than
marking a milestone released that nobody can settle.

## What this deliberately does not do

No weights, no delegation, no quadratic anything, no deadline. A request with no majority
either way stays `Pending` until someone breaks the tie or the applicant withdraws it.
Those are all reasonable things to build on top; none is needed to show the shape.
