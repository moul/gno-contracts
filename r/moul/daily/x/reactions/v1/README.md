# Reaction Board

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


An on-chain emoji reaction board. Each topic collects emoji reactions, and each
caller may register at most one reaction per topic (voters are tracked in an AVL
set). `Render` lists every topic with its emoji tallies and a total count.

**Realm path:** `gno.land/r/REPLACE_ADDR/reactions`

## Example calls

```
# React to a topic (creates the topic on demand). One reaction per caller.
React("gno 0.9 launch", "👍")
React("gno 0.9 launch", "❤️")

# Optionally pre-create an empty topic.
CreateTopic("weekend poll")

# View the board (all topics), or a single topic.
Render("")
Render("gno 0.9 launch")
```

A topic renders as a row like `👍 3  ❤️ 5  🎉 1` (sorted by count, then emoji),
followed by its total. Reacting twice to the same topic from the same address
aborts.
