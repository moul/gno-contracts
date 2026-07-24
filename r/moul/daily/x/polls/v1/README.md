# Polls & Voting

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


An on-chain poll and voting realm for gno.land (test13, gno 0.9). Anyone can
create a poll with a question and a comma-separated set of options; every caller
address may cast exactly one vote per poll. The realm's `Render` page lists each
poll with its options, live tallies drawn as `▓░` bar charts, per-option
percentages, and the total number of votes.

## Realm path

`gno.land/r/REPLACE_ADDR/polls`

## Exported transactions

- `CreatePoll(question string, options string) int` — create a poll. `options`
  is a comma-separated list (blank entries are dropped; at least 2 required).
  Returns the new poll's id.
- `Vote(pollID int, optionIndex int)` — cast one vote for `optionIndex` on poll
  `pollID`. One vote per caller address per poll; a second vote aborts.

Both are gno 0.9 crossing functions (first parameter `cur realm`); the caller
address is read via `runtime.PreviousRealm().Address()`.

## Read path

- `Render("")` — index of all polls with bar-chart tallies.
- `Render("<id>")` — a single poll by id.

## Example calls

```sh
# create a poll (returns its id, e.g. 0)
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/polls" \
  -func CreatePoll -args "Best L1 for smart contracts?" -args "gno,eth,sol" \
  -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 mykey

# vote for option index 0 on poll 0
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/polls" \
  -func Vote -args 0 -args 0 \
  -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 mykey

# view results in gnoweb
#   https://gno.land/r/REPLACE_ADDR/polls
#   https://gno.land/r/REPLACE_ADDR/polls:0
```

## Testing

```sh
gno test .
```
