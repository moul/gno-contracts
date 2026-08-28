// Package quizstreak is a multiple-choice trivia quiz where every player
// runs their own independent streak instead of racing others for a single
// shared question.
//
// Each address gets its own current question, picked deterministically from
// the address and the block height of its first answer so different players
// don't all start on the same question. A correct answer extends the
// player's streak and advances them to their next question; a wrong answer
// breaks the streak back to zero but leaves the same question live so they
// can retry. The realm tracks each player's best-ever streak on a global
// leaderboard.
package quizstreak

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// question is one fixed trivia entry.
type question struct {
	text       string
	choices    [4]string
	correctIdx int
}

// playerState is one address's progress through the question bank.
type playerState struct {
	qIdx    int
	streak  int
	best    int
	correct int
	wrong   int
}

var (
	questions = []question{
		{"What is the smallest prime number?", [4]string{"0", "1", "2", "3"}, 2},
		{"Which gas does a plant primarily absorb for photosynthesis?", [4]string{"Oxygen", "Nitrogen", "Carbon dioxide", "Hydrogen"}, 2},
		{"How many continents are there on Earth?", [4]string{"5", "6", "7", "8"}, 2},
		{"In binary, what is 1 + 1?", [4]string{"2", "10", "11", "0"}, 1},
		{"What does 'HTTP' stand for?", [4]string{"HyperText Transfer Protocol", "High Transfer Text Protocol", "Home Tool Transfer Protocol", "HyperText Transmission Path"}, 0},
		{"Which planet is known as the Red Planet?", [4]string{"Venus", "Jupiter", "Mars", "Saturn"}, 2},
		{"What is the time complexity of binary search?", [4]string{"O(n)", "O(log n)", "O(n^2)", "O(1)"}, 1},
		{"Which ocean is the largest by surface area?", [4]string{"Atlantic", "Indian", "Arctic", "Pacific"}, 3},
		{"What does 'CPU' stand for?", [4]string{"Central Processing Unit", "Computer Personal Unit", "Central Program Utility", "Core Processing Unicode"}, 0},
		{"How many bits are in a byte?", [4]string{"4", "8", "16", "32"}, 1},
	}

	players = avl.NewTree() // addr(string) -> *playerState
)

// startIndex picks a deterministic starting question for a brand-new player,
// spreading players across the bank using their address and the height of
// their first answer as entropy.
func startIndex(addr string, height int64) int {
	if height < 0 {
		height = -height
	}
	var sum int64
	for i := 0; i < len(addr); i++ {
		sum += int64(addr[i])
	}
	n := int64(len(questions))
	return int((sum + height) % n)
}

// getPlayer returns addr's state, lazily creating it on first contact.
func getPlayer(addr string) *playerState {
	if v, ok := players.Get(addr).(*playerState); ok {
		return v
	}
	p := &playerState{qIdx: startIndex(addr, runtime.ChainHeight())}
	players.Set(addr, p)
	return p
}

// nextIndex advances a solved player to a fresh-feeling next question: the
// step grows with the streak so a long run doesn't loop through the bank in
// a visibly fixed order.
func nextIndex(cur, streak, n int) int {
	return (cur + 1 + streak) % n
}

// Answer submits a choice (0..3) for the caller's current question.
// Crossing function: caller invokes as Answer(cross(cur), choiceIdx).
func Answer(cur realm, choiceIdx int) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if choiceIdx < 0 || choiceIdx >= len(questions[0].choices) {
		panic("choice must be in 0..3")
	}

	addr := cur.Previous().Address().String()
	p := getPlayer(addr)
	q := questions[p.qIdx]

	if choiceIdx != q.correctIdx {
		brokeStreak := p.streak
		p.streak = 0
		p.wrong++
		if brokeStreak > 0 {
			return "Wrong — streak of " + strconv.Itoa(brokeStreak) + " broken. Same question stays live, try again."
		}
		return "Wrong — try again."
	}

	p.streak++
	p.correct++
	if p.streak > p.best {
		p.best = p.streak
	}
	p.qIdx = nextIndex(p.qIdx, p.streak, len(questions))

	chain.Emit("QuizAnswered",
		"player", addr,
		"streak", strconv.Itoa(p.streak),
		"best", strconv.Itoa(p.best),
	)

	return "Correct! Streak is now " + strconv.Itoa(p.streak) + ". Next question is live."
}

// leaderboardEntry is a snapshot row used only for rendering, sorted by best
// streak descending.
type leaderboardEntry struct {
	addr string
	best int
}

func leaderboard() []leaderboardEntry {
	var rows []leaderboardEntry
	players.Iterate("", "", func(addr string, v any) bool {
		rows = append(rows, leaderboardEntry{addr: addr, best: v.(*playerState).best})
		return false
	})
	for i := 1; i < len(rows); i++ {
		j := i
		for j > 0 && rows[j-1].best < rows[j].best {
			rows[j-1], rows[j] = rows[j], rows[j-1]
			j--
		}
	}
	return rows
}

func renderQuestion(b *strings.Builder, p *playerState) {
	q := questions[p.qIdx]
	letters := [4]string{"A", "B", "C", "D"}
	b.WriteString("**" + q.text + "**\n\n")
	for i, c := range q.choices {
		b.WriteString("- **" + letters[i] + "** (" + strconv.Itoa(i) + "): " + c + "\n")
	}
	b.WriteString("\n- Current streak: " + strconv.Itoa(p.streak) + "\n")
	b.WriteString("- Best streak: " + strconv.Itoa(p.best) + "\n")
	b.WriteString("- Correct / wrong lifetime: " + strconv.Itoa(p.correct) + " / " + strconv.Itoa(p.wrong) + "\n\n")
}

// Render produces the gnoweb Markdown view. The root path shows the rules
// and the leaderboard; a path of a bech32 address shows that player's
// current question and stats.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Quiz Streak\n\n")
	b.WriteString("Everyone plays their own trivia run at their own pace. Call ")
	b.WriteString("`Answer(choiceIdx)` with 0-3 — a correct answer extends your streak ")
	b.WriteString("and moves you to your next question; a wrong answer breaks your ")
	b.WriteString("streak but leaves the same question live so you can retry.\n\n")

	if path != "" {
		if v, ok := players.Get(path).(*playerState); ok {
			b.WriteString("## Your question (`" + path + "`)\n\n")
			renderQuestion(&b, v)
		} else {
			b.WriteString("## `" + path + "`\n\n_No answers submitted yet — call `Answer` to get your first question._\n\n")
		}
	}

	b.WriteString("## Best-streak leaderboard\n\n")
	rows := leaderboard()
	if len(rows) == 0 {
		b.WriteString("_No one has played yet — be the first!_\n\n")
	} else {
		b.WriteString("| Player | Best streak |\n|---|---|\n")
		for _, r := range rows {
			b.WriteString("| `" + r.addr + "` | " + strconv.Itoa(r.best) + " |\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## How to play\n\n")
	b.WriteString("```\n")
	b.WriteString("gnokey maketx call -pkgpath gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/quizstreak \\\n")
	b.WriteString("  -func Answer -args <0|1|2|3> ...\n")
	b.WriteString("```\n\n")
	b.WriteString("View your own dashboard at `.../quizstreak:<your-address>`.\n")

	return b.String()
}
