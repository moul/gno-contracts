# Closest Guess

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

A blind, multiplayer number-guessing puzzle: submit one silent guess per round in 1..1000, then anyone calls Reveal() to disclose the hidden target and crown whoever landed closest. No hints, no iterative narrowing — just one shot and a leaderboard ranked by smallest distance across all-time rounds. It's a deliberately different twist on the genre from higher/lower or bulls-and-cows: the suspense is in not knowing until reveal.

Built for sapphire (gno 0.9). Live demo (agent address): https://sapphire.testnets.gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/closestguess
