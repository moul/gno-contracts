# Tip Jar

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

A public tip jar realm: anyone can send real ugnot with an optional message via Tip, and the realm tracks a leaderboard of the most generous tippers plus a feed of recent tips, both rendered live in Markdown. Only the deployer (captured as owner at deploy time) can withdraw the accumulated balance. It's a small, complete example of the payment-guard pattern (OriginSend + IsUserCall) paired with a sorted avl.Tree leaderboard.

Built for topaz (gno 0.9). Live demo (agent address): https://topaz.testnets.gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/tipjar
