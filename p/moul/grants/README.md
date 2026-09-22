# grants

A grant program governed by a member set: anyone may ask the board for money, the members
vote in the open, and the money leaves in tranches that each have to be earned by producing
a proof the members accept.

The package is **pure**. It holds no coins, calls no banker, reads no chain state, and
imports nothing from `chain`: the caller supplies the acting address, the block height and
the current treasury balance, and the caller executes the transfer. That is what makes the
whole state machine unit-testable without a node, and what makes the realm on top thin
enough to read in one screen.

Live: [`r/moul/grant/v0`](/r/moul/grant/v0), a personal board. A multi-member program is
another realm of the same size over this same package.

## Three layers

| Type | What it owns |
|---|---|
| `Board` | members, requests, ballots, proofs. Every rule and every tally. |
| `Program` | a `Board` plus the money around it: donations in, payments out, the denom. |
| `Renderer` | the three markdown pages, configured by a struct literal. |

A realm holds one `Program`, builds a `Renderer` inside `Render`, and does nothing else but
turn callers into addresses and execute the `Payment` it is handed back.

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

A **one-member board is a legitimate configuration**, and its majority is one: that is what
a personal program looks like. It still cannot self-grant, because a sole member applying
leaves zero eligible voters and `Majority` returns an unreachable 1 rather than 0.

`Standing` counts only ballots from addresses that are members **right now**; decisions use
it. `Request.Tally` counts the raw record. The two differ exactly when a voter has since
been removed from the board: their ballot stays readable and stops carrying weight.

## Asking for someone else

`SubmitFor(applicant, beneficiary, reason, …)` files a request whose tranches pay an address
other than the one that filed it. `Submit` is the same call with the two addresses equal.

The split is not a convenience. **An account with nothing in it cannot pay the gas to ask for
its first coins**, so on a board whose purpose is to fund empty accounts, someone else filing
is the only path that works. Two rules follow from that, and both are in the library:

- **The reason is required** when the payee is someone else. Nothing verifies it; it is a
  claim by the applicant, and the renderer prints it under its own heading so a member can
  check it before voting.
- **Both addresses are excluded from voting**, on the request and on every proof. A member
  paid by a request a friend filed is the same conflict of interest with one address in
  between. `Request.Excludes` is the predicate, `Board.Eligible` recounts over it, and the
  majority moves with it.

Either the applicant or the beneficiary may `SubmitProof`: the payee may not be able to
transact until the first tranche lands, and once they can, they have to be able to show
their own work. `Request.Payee()` is who a released tranche pays, and it is what the
`Payment` handed back to the realm carries.

## Membership is a request like any other

`SubmitMemberChange` files a `KindMember` request. It asks for no money, and when it
carries it executes immediately, going straight to `Completed`. Only a member may file one:
opening a grant board's own composition to anyone with a keypair is how it gets captured.
The last member cannot be removed.

## The money: `Program`

```go
p := grants.NewProgram("ugnot", alice, bob, carol)

p.Fund(donor, 5000, height)                 // put a name on a transfer that already happened
r, _ := p.Apply(dave, "Port the thing", "why it matters", "design:100,ship:400", height)

p.Board.Vote(alice, r.ID, true, "cheap for what it tells us", height)
p.Board.Vote(bob, r.ID, true, "agreed", height)          // majority of three: approved

p.Board.SubmitProof(dave, r.ID, 0, grants.Proof{Kind: "url", Ref: "https://…", Height: height})
p.Review(alice, r.ID, 0, true, "merged, I reviewed it", height, balance)
out, pay, err := p.Review(carol, r.ID, 0, true, "confirmed", height, balance)
if pay != nil {
    // out == grants.Accepted. Send pay.Amount to pay.To; it is already on the ledger.
}
```

**The treasury is not escrowed.** `Committed()` is what approved-but-unreleased milestones
add up to, `Available(balance)` is the balance minus that, and it **can go negative**. That
is deliberate: a board that can only approve what it already holds cannot approve anything
before a donor shows up.

The cost is that a release can come due against an empty treasury, so `Program.Review`
takes the balance and checks, *before recording anything*, whether this verdict would
release a tranche it cannot cover. If so it returns `ErrUnderfunded` and changes nothing:
no ballot, no release, no payment. A **refusal** is always free to record, because it costs
the treasury nothing. `Board.Decides` and `Board.ReviewDecides` expose the same preview for
anything else that needs to check a precondition it cannot roll back.

## The pages: `Renderer`

`Renderer` serves the board at `""`, one request at `request/<id>`, and the money trail at
`ledger`. Everything program-specific is a field (`Title`, `Intro`, `Notes`, `Path`,
`Link`, `Treasury`, `Balance`, `Footer`, and a `Note func(*Request) string` for per-request
callouts), so a realm's whole `Render` is a struct literal.

Build it **inside** `Render`, not in a realm global: `Note` is a func, and `Balance` has to
be read fresh on every call anyway. The five `ExampleRenderer*` tests pin every page of a
board mid-flight, so a change to any rule shows up as a diff in the markdown.

**Escaping happens here, once.** Everything a caller typed goes through
[`p/moul/kit/ui`](/p/moul/kit/ui/v0) and
[`p/nt/markdown/sanitize`](/p/nt/markdown/sanitize/v0) on its way to the page, so a realm
neither repeats it nor pre-escapes (escaping twice shows the backslashes). The bar differs
by slot on purpose: a one-line slot (a title, a milestone name, a reason on a ballot) keeps
nothing a caller typed as markup, while a prose slot (the body of an application, the note
on a proof) goes through `sanitize.Block`, which preserves inline links and emphasis because
a grant application whose link to the merged PR renders as literal text is a worse page.
What `Block` still kills is everything structural, so a paragraph cannot leave its paragraph.
The realm's own `Title`, `Intro`, `Notes` and `Footer` are chrome, written by whoever
deployed it, and are emitted as-is.

`TestEveryCallerSuppliedStringIsEscaped` drives one board through every caller-controlled
slot and asserts no structural line of any page carries a live link, an image or a gnoweb
tag. It asserts the dangerous sequence is dead, never the exact escaped bytes: those belong
to the sanitizer and change when it changes.

## What this deliberately does not do

No weights, no delegation, no quadratic anything, no deadline. A request with no majority
either way stays `Pending` until someone breaks the tie or the applicant withdraws it.
Those are all reasonable things to build on top; none is needed to show the shape.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/p/moul/grants/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/p/moul/grants/v0/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
