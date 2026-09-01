# Streaks — on-chain habit-streak tracker

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

A tiny on-chain habit tracker: call CheckIn() and it builds a streak as long as you come back within 100 blocks of your last visit; wait longer and the streak resets to zero on your next check-in. It tracks current streak, longest streak ever, and total check-ins per address, with a sorted leaderboard and a per-address detail view in Render. Neat because it turns block height — the one clock Gno actually has — into a believable stand-in for 'don't break the chain' daily habit tracking, with no wall-clock hacks.

Built for sapphire (gno 0.9). Live demo (agent address): https://sapphire.testnets.gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/streaks
