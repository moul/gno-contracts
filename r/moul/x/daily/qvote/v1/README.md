# Quadratic Voting

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

A Gno port of the classic Solidity 'Ballot' voting contract, but swapping one-address-one-vote for quadratic voting: every address gets a fixed 100-credit budget per poll, and stacking N votes on one option costs N^2 credits, so spreading conviction is cheap but dominating one option gets steep fast. Create a poll with CreatePoll, spend (or refund) credits with Vote(pollID, optionIdx, delta), and the creator ends it with ClosePoll. Render shows the poll board, per-poll results, and any voter's standing.

Built for sapphire (gno 0.9). Live demo (agent address): https://sapphire.testnets.gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/qvote
