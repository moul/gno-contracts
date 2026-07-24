# Tic-Tac-Toe

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A 2-player tic-tac-toe realm for gno.land. The game creator plays **X**, the named
opponent plays **O**. Moves enforce strict turn order by caller address and reject
cells that are already taken. The realm detects wins (rows, columns, diagonals) and
draws, and `Render` draws the 3×3 board with `X` / `O` / `·`, whose turn it is, and
the final result.

Realm path: `gno.land/r/REPLACE_ADDR/tictactoe`

## Example calls

```
# Alice creates a game against Bob — Alice is X, Bob is O. Returns the game id (e.g. 1).
NewGame(g1pxk...bob)

# Play a cell (0-8), indexed left-to-right, top-to-bottom:
#   0 | 1 | 2
#   3 | 4 | 5
#   6 | 7 | 8
Move(1, 0)   # X (creator) plays top-left
Move(1, 3)   # O (opponent) plays middle-left
Move(1, 1)   # X plays top-middle
Move(1, 4)   # O plays center
Move(1, 2)   # X completes the top row and wins

# View a single game board:
Render("/1")

# List all games:
Render("")
```
