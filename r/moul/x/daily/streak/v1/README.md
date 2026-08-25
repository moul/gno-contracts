# Check-in Streaks

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Call `CheckIn()` once per "day" to keep a streak alive. Miss one and the current
streak resets to 1 — but your **best** streak is never lowered, so a broken run
costs the run, not the record.

There is no wall clock on-chain, so a "day" is a fixed window of `BlocksPerDay`
(1000) blocks: `day = ChainHeight() / BlocksPerDay`. Every streak decision is
therefore a pure function of block height — deterministic, replayable, and
impossible to game by waiting for a favourable timestamp.

```
CheckIn()                        → extends or restarts your streak, returns it
Current(addr)                    → live streak (0 once the window has lapsed)
Best(addr)                       → record streak, never lowered
Day()                            → current day index

/r/moul/x/daily/streak/v1        → leaderboard, ranked by best streak
/r/moul/x/daily/streak/v1:g1...  → one address's standing
```

`Current` deliberately reports the *live* truth rather than the stored value:
once a window lapses it returns 0 even though the record still holds the old
number until the next check-in rewrites it.

Checking in twice in the same window is rejected — the streak only moves when
the window does. Only an EOA can check in (`IsUserCall`), so another realm
can't farm streaks on your behalf.

Built for gno 0.9.
