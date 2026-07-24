// Package trivia is a rotating multiple-choice trivia quiz realm.
//
// One question is live at a time. Anyone can call Answer with a choice
// index; the first caller to answer correctly scores a point and the quiz
// advances to the next question. The starting question is picked
// deterministically from the block height at deploy time so repeated
// deploys don't always open on question one.
package trivia

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

// round holds the mutable state of the currently open question.
type round struct {
	number   int // 1-based round counter, increments forever
	qIdx     int // index into questions for this round
	attempts int // guesses made against this round so far
	solved   bool
	winner   string
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
		{"Who wrote the original Go proverb 'Don't communicate by sharing memory'?", [4]string{"Linus Torvalds", "Rob Pike", "Guido van Rossum", "Brendan Eich"}, 1},
	}

	current *round
	scores  = avl.NewTree() // addr(string) -> *int, points across all rounds

	totalCorrect int // lifetime count of correctly-answered questions
)

func init() {
	current = newRound(1, runtime.ChainHeight())
}

// newRound builds a fresh round. The question index cycles through the fixed
// list, offset by a height-derived starting point so consecutive deploys
// don't all open on the same question.
func newRound(number int, height int64) *round {
	return &round{
		number: number,
		qIdx:   questionIndex(number, height),
	}
}

// questionIndex maps a round number and a height (entropy source for the
// starting offset) to a slot in the questions slice. Deterministic and pure
// so it's easy to unit test.
func questionIndex(number int, height int64) int {
	if height < 0 {
		height = -height
	}
	n := len(questions)
	offset := int(height % int64(n))
	return (offset + number - 1) % n
}

// Answer submits a choice (0..3) for the current question. Crossing
// function: caller invokes as Answer(cross(cur), choiceIdx).
func Answer(cur realm, choiceIdx int) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	q := questions[current.qIdx]
	if choiceIdx < 0 || choiceIdx >= len(q.choices) {
		panic("choice must be in 0.." + strconv.Itoa(len(q.choices)-1))
	}
	if current.solved {
		panic("this question is already solved; the next one is already live")
	}

	current.attempts++
	caller := cur.Previous().Address().String()

	if choiceIdx != q.correctIdx {
		return "Wrong — try again."
	}

	current.solved = true
	current.winner = caller
	addScore(caller)
	totalCorrect++

	chain.Emit("QuestionSolved",
		"round", strconv.Itoa(current.number),
		"winner", caller,
		"answer", q.choices[choiceIdx],
	)

	solvedRound := current.number
	current = newRound(solvedRound+1, runtime.ChainHeight())

	return "Correct! The answer was \"" + q.choices[choiceIdx] + "\". A new question is now live."
}

// addScore bumps addr's lifetime point count.
func addScore(addr string) {
	if v, ok := scores.Get(addr); ok {
		p := v.(*int)
		*p++
		return
	}
	one := 1
	scores.Set(addr, &one)
}

func scoreOf(addr string) int {
	if v, ok := scores.Get(addr); ok {
		return *(v.(*int))
	}
	return 0
}

// leaderboardEntry is a snapshot row used only for rendering, sorted by
// score descending.
type leaderboardEntry struct {
	addr  string
	score int
}

func leaderboard() []leaderboardEntry {
	var rows []leaderboardEntry
	scores.Iterate("", "", func(addr string, v any) bool {
		rows = append(rows, leaderboardEntry{addr: addr, score: *(v.(*int))})
		return false
	})
	// simple insertion sort by score desc; leaderboards here stay small.
	for i := 1; i < len(rows); i++ {
		j := i
		for j > 0 && rows[j-1].score < rows[j].score {
			rows[j-1], rows[j] = rows[j], rows[j-1]
			j--
		}
	}
	return rows
}

// Render produces the gnoweb Markdown view of the quiz.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Trivia Quiz\n\n")
	b.WriteString("A rotating on-chain trivia quiz. Call `Answer(choiceIdx)` with 0-3 ")
	b.WriteString("to answer the current question — first correct answer scores the point ")
	b.WriteString("and a new question goes live.\n\n")

	q := questions[current.qIdx]
	b.WriteString("## Round " + strconv.Itoa(current.number) + "\n\n")
	b.WriteString("**" + q.text + "**\n\n")
	letters := [4]string{"A", "B", "C", "D"}
	for i, c := range q.choices {
		b.WriteString("- **" + letters[i] + "** (" + strconv.Itoa(i) + "): " + c + "\n")
	}
	b.WriteString("\n- Attempts so far this round: " + strconv.Itoa(current.attempts) + "\n\n")

	b.WriteString("## Leaderboard\n\n")
	rows := leaderboard()
	if len(rows) == 0 {
		b.WriteString("_No one has scored yet — be the first!_\n\n")
	} else {
		b.WriteString("| Player | Points |\n|---|---|\n")
		for _, r := range rows {
			b.WriteString("| `" + r.addr + "` | " + strconv.Itoa(r.score) + " |\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("Total questions answered correctly across all rounds: " + strconv.Itoa(totalCorrect) + "\n\n")

	b.WriteString("## How to play\n\n")
	b.WriteString("```\n")
	b.WriteString("gnokey maketx call -pkgpath gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/trivia \\\n")
	b.WriteString("  -func Answer -args <0|1|2|3> ...\n")
	b.WriteString("```\n")

	return b.String()
}
