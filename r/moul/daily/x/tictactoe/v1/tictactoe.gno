package tictactoe

import (
	"chain"
	"chain/runtime/unsafe"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// Cell states.
const (
	empty = 0
	markX = 1
	markO = 2
)

// Game holds a single tic-tac-toe match.
type Game struct {
	id       int
	playerX  address // caller of NewGame
	playerO  address // opponent
	board    [9]int  // 0 empty, 1 X, 2 O
	moves    int     // number of moves played
	turn     int     // markX or markO — whose turn it is
	winner   int     // 0 none, 1 X, 2 O
	draw     bool
	finished bool
}

var (
	games  = avl.NewTree() // id (padded string) -> *Game
	nextID = 1
)

func pad(id int) string {
	s := strconv.Itoa(id)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}

// NewGame creates a game. Caller is X, opponent is O. Returns the game id.
func NewGame(cur realm, opponent address) int {
	caller := unsafe.PreviousRealm().Address()
	if opponent == caller {
		panic("opponent must differ from caller")
	}
	if !opponent.IsValid() {
		panic("invalid opponent address")
	}
	id := nextID
	nextID++
	g := &Game{
		id:      id,
		playerX: caller,
		playerO: opponent,
		turn:    markX,
	}
	games.Set(pad(id), g)
	chain.Emit("GameCreated", "id", strconv.Itoa(id), "x", caller.String(), "o", opponent.String())
	return id
}

// Move plays cell (0-8) for the calling player. Enforces turn order and rejects taken cells.
func Move(cur realm, gameID int, cell int) {
	v, ok := games.Get(pad(gameID))
	if !ok {
		panic("game not found")
	}
	g := v.(*Game)
	if g.finished {
		panic("game already finished")
	}
	if cell < 0 || cell > 8 {
		panic("cell out of range (0-8)")
	}
	if g.board[cell] != empty {
		panic("cell already taken")
	}
	caller := unsafe.PreviousRealm().Address()

	var mark int
	switch caller {
	case g.playerX:
		mark = markX
	case g.playerO:
		mark = markO
	default:
		panic("caller is not a player in this game")
	}
	if mark != g.turn {
		panic("not your turn")
	}

	g.board[cell] = mark
	g.moves++

	if won(g.board, mark) {
		g.winner = mark
		g.finished = true
		chain.Emit("GameWon", "id", strconv.Itoa(gameID), "winner", markName(mark))
	} else if g.moves == 9 {
		g.draw = true
		g.finished = true
		chain.Emit("GameDraw", "id", strconv.Itoa(gameID))
	} else {
		if g.turn == markX {
			g.turn = markO
		} else {
			g.turn = markX
		}
		chain.Emit("Move", "id", strconv.Itoa(gameID), "cell", strconv.Itoa(cell), "mark", markName(mark))
	}
}

var lines = [8][3]int{
	{0, 1, 2}, {3, 4, 5}, {6, 7, 8}, // rows
	{0, 3, 6}, {1, 4, 7}, {2, 5, 8}, // cols
	{0, 4, 8}, {2, 4, 6}, // diagonals
}

func won(b [9]int, mark int) bool {
	for _, l := range lines {
		if b[l[0]] == mark && b[l[1]] == mark && b[l[2]] == mark {
			return true
		}
	}
	return false
}

func markName(m int) string {
	switch m {
	case markX:
		return "X"
	case markO:
		return "O"
	default:
		return "-"
	}
}

func cellGlyph(m int) string {
	switch m {
	case markX:
		return "X"
	case markO:
		return "O"
	default:
		return "·"
	}
}

// GetGame returns a game by id (read helper for tests / callers).
func GetGame(id int) (*Game, error) {
	v, ok := games.Get(pad(id))
	if !ok {
		return nil, errors.New("game not found")
	}
	return v.(*Game), nil
}

func renderBoard(b [9]int) string {
	var sb strings.Builder
	for r := 0; r < 3; r++ {
		sb.WriteString("| ")
		for c := 0; c < 3; c++ {
			sb.WriteString(cellGlyph(b[r*3+c]))
			sb.WriteString(" | ")
		}
		sb.WriteString("\n")
	}
	return sb.String()
}

func gameStatus(g *Game) string {
	if g.finished {
		if g.draw {
			return "Draw."
		}
		return "Winner: " + markName(g.winner)
	}
	return "Turn: " + markName(g.turn)
}

// Render draws the list of games, or a single game board at path "/<id>".
func Render(path string) string {
	p := strings.TrimPrefix(path, "/")
	if p == "" {
		return renderList()
	}
	id, err := strconv.Atoi(p)
	if err != nil {
		return "# Tic-Tac-Toe\n\nInvalid game id: " + p + "\n"
	}
	g, gerr := GetGame(id)
	if gerr != nil {
		return "# Tic-Tac-Toe\n\nGame " + p + " not found.\n"
	}
	var sb strings.Builder
	sb.WriteString("# Tic-Tac-Toe — Game #")
	sb.WriteString(strconv.Itoa(g.id))
	sb.WriteString("\n\n")
	sb.WriteString("- X: `")
	sb.WriteString(g.playerX.String())
	sb.WriteString("`\n- O: `")
	sb.WriteString(g.playerO.String())
	sb.WriteString("`\n\n")
	sb.WriteString(renderBoard(g.board))
	sb.WriteString("\n**")
	sb.WriteString(gameStatus(g))
	sb.WriteString("**\n\nCell indices:\n\n")
	sb.WriteString("| 0 | 1 | 2 |\n| 3 | 4 | 5 |\n| 6 | 7 | 8 |\n")
	return sb.String()
}

func renderList() string {
	var sb strings.Builder
	sb.WriteString("# Tic-Tac-Toe\n\n")
	sb.WriteString("2-player tic-tac-toe. Call `NewGame(opponent)` to start; view a game at `/<id>`.\n\n")
	if games.Size() == 0 {
		sb.WriteString("_No games yet._\n")
		return sb.String()
	}
	sb.WriteString("| # | X | O | Status |\n|---|---|---|--------|\n")
	games.Iterate("", "", func(key string, value interface{}) bool {
		g := value.(*Game)
		sb.WriteString("| ")
		sb.WriteString(strconv.Itoa(g.id))
		sb.WriteString(" | `")
		sb.WriteString(g.playerX.String())
		sb.WriteString("` | `")
		sb.WriteString(g.playerO.String())
		sb.WriteString("` | ")
		sb.WriteString(gameStatus(g))
		sb.WriteString(" |\n")
		return false
	})
	return sb.String()
}
