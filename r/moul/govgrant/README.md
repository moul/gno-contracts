# govgrant

A grant board that GovDAO funds and GovDAO governs. GovDAO sends the treasury money once,
a small board of members decides grants out of it in the open, and every tranche leaves
only on a majority of that board. A grant is **not** its own GovDAO proposal; the board is.

## Who may do what

| Who | Calls |
|---|---|
| anyone | `Apply`, `ApplyFor` (for an empty account, with a reason), `Retract` (own pending request), `SubmitProof` (own approved grant), `Fund` |
| a member | `Vote`, `Review`, `ProposeMember` |
| GovDAO, by an executed proposal | seat the board, set the cap, pause payouts, take money back |

The library's rules hold unchanged: the party a decision is about never votes on it, the bar
is a majority of the eligible members, recomputed per ballot, and a tranche is paid in the
same transaction as the review that carries it. On top of them:

- **A board of two cannot remove a member by itself.** Before `p/moul/grants/v1` it could:
  the subject of a removal may not vote, so one member was the whole eligible set, could
  remove the other, then approve a sock's grant alone.
- **One request may ask for at most `Cap()`**, 50 GNOT until GovDAO sets it.
- **Deployed, nobody sits on the board**, so nothing can be decided or paid until GovDAO
  seats its members.

## The GovDAO levers

Each `New*Request` returns a `dao.ProposalRequest`; create it from a `gnokey maketx run`
script and it takes effect only when r/gov/dao executes it after an accepted vote. Arguments
are checked when the request is built, so a bad one fails before the vote.

```go
dao.MustCreateProposal(cross(cur), govgrant.NewSetBoardRequest(cross(cur), members, reason))
dao.MustCreateProposal(cross(cur), govgrant.NewSetCapRequest(cross(cur), 50_000_000, reason))
dao.MustCreateProposal(cross(cur), govgrant.NewSetPausedRequest(cross(cur), true, reason))
dao.MustCreateProposal(cross(cur), govgrant.NewSweepRequest(cross(cur), to, amount, reason))
```

Funding is not a lever here: it is GovDAO's own `impl.NewTreasuryPaymentRequest` with this
realm's `Address()` as the recipient.

## Why public, and why not r/moul/grant

[`r/moul/grant`](../grant) is moul's own pocket money, says so on its page, and is
**private**: its creator can redeploy it with the coins kept and the code replaced. That is
fine for one person's money and wrong for a DAO's. This realm is public, so its code can
never change, and every rule lives in [`p/moul/grants/v1`](../../../p/moul/grants).
