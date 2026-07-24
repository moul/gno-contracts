package connect4

import (
	"chain"
	"chain/runtime/unsafe"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

const (
	cols = 7
	rows = 6
)

// cell values
const (
	empty = 0
	red   = 1 // 🔴 game creator (caller of NewGame)
	yel   = 2 // 🟡 opponent
)

// Game holds the full state of one Connect Four match.
// board is indexed board[row][col]; row 0 is the BOTTOM row.
type Game struct {
	ID       int64
	Red      address // 🔴 creator, moves first
	Yellow   address // 🟡 opponent
	Board    [rows][cols]int
	Turn     int  // whose turn: red or yel
	Winner   int  // empty until decided; red/yel = winner
	Draw     bool // true when board full with no winner
	Finished bool
}

var (
	games  = avl.NewTree() // id (zero-padded string) -> *Game
	nextID int64
)

func idKey(id int64) string {
	// zero-pad so avl iteration order matches numeric order for Render lists
	s := strconv.FormatInt(id, 10)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}

// NewGame creates a match between the caller (🔴) and opponent (🟡).
// Returns the new game id.
func NewGame(cur realm, opponent address) int64 {
	caller := unsafe.PreviousRealm().Address()
	if opponent == caller {
		panic("opponent must differ from caller")
	}
	if opponent.String() == "" {
		panic("opponent address is empty")
	}
	nextID++
	g := &Game{
		ID:     nextID,
		Red:    caller,
		Yellow: opponent,
		Turn:   red,
	}
	games.Set(idKey(g.ID), g)
	chain.Emit("GameCreated",
		"id", strconv.FormatInt(g.ID, 10),
		"red", caller.String(),
		"yellow", opponent.String(),
	)
	return g.ID
}

func getGame(id int64) (*Game, error) {
	v, ok := games.Get(idKey(id))
	if !ok {
		return nil, errors.New("game not found: " + strconv.FormatInt(id, 10))
	}
	return v.(*Game), nil
}

// Drop places the caller's disc into the given column (0-6).
// Enforces turn order by caller, rejects full columns, and detects
// a 4-in-a-row win or a draw.
func Drop(cur realm, gameID int64, column int) {
	if column < 0 || column >= cols {
		panic("column out of range (0-6)")
	}
	g, err := getGame(gameID)
	if err != nil {
		panic(err.Error())
	}
	if g.Finished {
		panic("game already finished")
	}

	caller := unsafe.PreviousRealm().Address()
	var mover int
	switch caller {
	case g.Red:
		mover = red
	case g.Yellow:
		mover = yel
	default:
		panic("caller is not a player in this game")
	}
	if mover != g.Turn {
		panic("not your turn")
	}

	// find lowest empty row in the column
	placed := -1
	for r := 0; r < rows; r++ {
		if g.Board[r][column] == empty {
			g.Board[r][column] = mover
			placed = r
			break
		}
	}
	if placed == -1 {
		panic("column is full")
	}

	if wins(&g.Board, placed, column, mover) {
		g.Winner = mover
		g.Finished = true
		chain.Emit("GameWon",
			"id", strconv.FormatInt(g.ID, 10),
			"winner", caller.String(),
		)
	} else if full(&g.Board) {
		g.Draw = true
		g.Finished = true
		chain.Emit("GameDraw", "id", strconv.FormatInt(g.ID, 10))
	} else {
		if g.Turn == red {
			g.Turn = yel
		} else {
			g.Turn = red
		}
		chain.Emit("DiscDropped",
			"id", strconv.FormatInt(g.ID, 10),
			"col", strconv.Itoa(column),
			"player", caller.String(),
		)
	}

	games.Set(idKey(g.ID), g)
}

func full(b *[rows][cols]int) bool {
	for c := 0; c < cols; c++ {
		if b[rows-1][c] == empty {
			return false
		}
	}
	return true
}

// wins checks whether the disc just placed at (r,c) for player p completes
// a run of 4 in any of the four directions.
func wins(b *[rows][cols]int, r, c, p int) bool {
	// direction pairs: horizontal, vertical, diag /, diag \
	dirs := [4][2]int{{0, 1}, {1, 0}, {1, 1}, {1, -1}}
	for _, d := range dirs {
		count := 1
		count += run(b, r, c, d[0], d[1], p)
		count += run(b, r, c, -d[0], -d[1], p)
		if count >= 4 {
			return true
		}
	}
	return false
}

func run(b *[rows][cols]int, r, c, dr, dc, p int) int {
	n := 0
	for i := 1; i < 4; i++ {
		rr := r + dr*i
		cc := c + dc*i
		if rr < 0 || rr >= rows || cc < 0 || cc >= cols {
			break
		}
		if b[rr][cc] != p {
			break
		}
		n++
	}
	return n
}

func glyph(v int) string {
	switch v {
	case red:
		return "🔴"
	case yel:
		return "🟡"
	default:
		return "·"
	}
}

// Render draws the board with 🔴🟡· and shows whose turn / the winner.
// path "" lists all games; path "<id>" shows a single board.
func Render(path string) string {
	path = strings.TrimSpace(strings.Trim(path, "/"))
	if path == "" {
		return renderList()
	}
	id, err := strconv.ParseInt(path, 10, 64)
	if err != nil {
		return "# Connect Four\n\nInvalid game id: `" + path + "`\n"
	}
	g, err := getGame(id)
	if err != nil {
		return "# Connect Four\n\n" + err.Error() + "\n"
	}
	return renderGame(g)
}

func renderList() string {
	var sb strings.Builder
	sb.WriteString("# Connect Four\n\n")
	sb.WriteString("Two-player Connect Four on a 7×6 board. 🔴 is the game creator, 🟡 the opponent.\n\n")
	if games.Size() == 0 {
		sb.WriteString("_No games yet. Call `NewGame(opponent)` to start one._\n")
		return sb.String()
	}
	sb.WriteString("## Games\n\n")
	sb.WriteString("| ID | 🔴 Red | 🟡 Yellow | Status |\n")
	sb.WriteString("|----|--------|-----------|--------|\n")
	games.Iterate("", "", func(_ string, v any) bool {
		g := v.(*Game)
		status := ""
		switch {
		case g.Winner == red:
			status = "🔴 won"
		case g.Winner == yel:
			status = "🟡 won"
		case g.Draw:
			status = "draw"
		case g.Turn == red:
			status = "🔴 to move"
		default:
			status = "🟡 to move"
		}
		sb.WriteString("| [" + strconv.FormatInt(g.ID, 10) + "](/r:" + strconv.FormatInt(g.ID, 10) + ") | " +
			short(g.Red) + " | " + short(g.Yellow) + " | " + status + " |\n")
		return false
	})
	sb.WriteString("\nOpen a game by its id (e.g. path `1`).\n")
	return sb.String()
}

func short(a address) string {
	s := a.String()
	if len(s) <= 12 {
		return "`" + s + "`"
	}
	return "`" + s[:8] + "…" + s[len(s)-4:] + "`"
}

func renderGame(g *Game) string {
	var sb strings.Builder
	sb.WriteString("# Connect Four — Game " + strconv.FormatInt(g.ID, 10) + "\n\n")
	sb.WriteString("- 🔴 Red: `" + g.Red.String() + "`\n")
	sb.WriteString("- 🟡 Yellow: `" + g.Yellow.String() + "`\n\n")

	// status line
	switch {
	case g.Winner == red:
		sb.WriteString("**🔴 Red wins!**\n\n")
	case g.Winner == yel:
		sb.WriteString("**🟡 Yellow wins!**\n\n")
	case g.Draw:
		sb.WriteString("**Draw — board full.**\n\n")
	case g.Turn == red:
		sb.WriteString("**Turn: 🔴 Red**\n\n")
	default:
		sb.WriteString("**Turn: 🟡 Yellow**\n\n")
	}

	// board top-down (row rows-1 at top, row 0 at bottom)
	sb.WriteString("```\n")
	for r := rows - 1; r >= 0; r-- {
		for c := 0; c < cols; c++ {
			sb.WriteString(glyph(g.Board[r][c]))
		}
		sb.WriteString("\n")
	}
	// column indices
	for c := 0; c < cols; c++ {
		sb.WriteString(strconv.Itoa(c))
	}
	sb.WriteString("\n```\n\n")

	if !g.Finished {
		sb.WriteString("Drop a disc: `Drop(" + strconv.FormatInt(g.ID, 10) + ", <col 0-6>)`\n")
	}
	return sb.String()
}
