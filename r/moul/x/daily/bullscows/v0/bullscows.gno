// Package bullscows is a shared on-chain Bulls & Cows puzzle: one secret
// 4-digit code (distinct digits) per round, guessed cooperatively/competitively
// by anyone who calls Guess. Bulls = right digit, right spot. Cows = right
// digit, wrong spot. Whoever hits 4 bulls wins the round and a leaderboard
// entry; a fresh secret is drawn immediately after.
package bullscows

import (
	"chain/runtime"
	"strconv"
	"strings"
)

const (
	maxHistory = 10
	maxRecords = 5
)

type guessLog struct {
	player   string
	guess    string
	bulls    int
	cows     int
}

type record struct {
	player   string
	attempts int
	round    int
}

var (
	secret   [4]int
	round    int
	attempts int
	history  []guessLog
	records  []record
)

func init() {
	round = 1
	secret = newSecret(seedFor(round))
}

// seedFor derives a per-round PRNG seed from the current chain height so
// nobody can precompute the next secret before the round actually starts.
func seedFor(r int) int64 {
	return runtime.ChainHeight()*1000003 + int64(r)*7919 + 17
}

// nextRand is a minimal LCG (glibc constants) — no crypto strength needed
// for a casual puzzle, just enough spread across digits.
func nextRand(seed int64) int64 {
	return (seed*1103515245 + 12345) & 0x7fffffff
}

func newSecret(seed int64) [4]int {
	var used [10]bool
	var digits [4]int
	s := seed
	for i := 0; i < 4; i++ {
		for {
			s = nextRand(s)
			d := int(s % 10)
			if !used[d] {
				used[d] = true
				digits[i] = d
				break
			}
		}
	}
	return digits
}

// parseGuess validates a 4-digit, distinct-digit guess string.
func parseGuess(guess string) ([4]int, bool) {
	var out [4]int
	if len(guess) != 4 {
		return out, false
	}
	var used [10]bool
	for i := 0; i < 4; i++ {
		c := guess[i]
		if c < '0' || c > '9' {
			return out, false
		}
		d := int(c - '0')
		if used[d] {
			return out, false
		}
		used[d] = true
		out[i] = d
	}
	return out, true
}

// score returns (bulls, cows) for guess against target, assuming both have
// distinct digits (guaranteed by parseGuess / newSecret).
func score(target, guess [4]int) (int, int) {
	bulls, cows := 0, 0
	for i := 0; i < 4; i++ {
		if guess[i] == target[i] {
			bulls++
			continue
		}
		for j := 0; j < 4; j++ {
			if i != j && guess[i] == target[j] {
				cows++
				break
			}
		}
	}
	return bulls, cows
}

func addHistory(l guessLog) {
	history = append(history, l)
	if len(history) > maxHistory {
		history = history[len(history)-maxHistory:]
	}
}

// addRecord keeps the top maxRecords fastest solves, ascending by attempts.
func addRecord(r record) {
	records = append(records, r)
	for i := len(records) - 1; i > 0 && records[i].attempts < records[i-1].attempts; i-- {
		records[i], records[i-1] = records[i-1], records[i]
	}
	if len(records) > maxRecords {
		records = records[:maxRecords]
	}
}

func startNewRound() {
	round++
	attempts = 0
	history = nil
	secret = newSecret(seedFor(round))
}

// Guess submits a 4-distinct-digit code against the current round's secret.
// Returns the bulls/cows feedback, or "solved!" text when it's a win.
func Guess(cur realm, guess string) string {
	digits, ok := parseGuess(guess)
	if !ok {
		panic("guess must be 4 digits, 0-9, no repeats (e.g. \"1972\")")
	}

	player := cur.Previous().Address().String()
	attempts++
	bulls, cows := score(secret, digits)
	addHistory(guessLog{player: player, guess: guess, bulls: bulls, cows: cows})

	if bulls == 4 {
		wonRound := round
		wonAttempts := attempts
		addRecord(record{player: player, attempts: wonAttempts, round: wonRound})
		startNewRound()
		return "*** SOLVED *** " + guess + " was it — round " + strconv.Itoa(wonRound) +
			" cracked in " + strconv.Itoa(wonAttempts) + " guesses. New round " +
			strconv.Itoa(round) + " has begun, good luck!"
	}

	return guess + " -> " + strconv.Itoa(bulls) + " bulls, " + strconv.Itoa(cows) + " cows"
}

// GiveUp reveals the current secret and starts a fresh round without
// awarding a leaderboard record.
func GiveUp(cur realm) string {
	revealed := digitsToString(secret)
	oldRound := round
	startNewRound()
	return "round " + strconv.Itoa(oldRound) + "'s code was " + revealed +
		" — round " + strconv.Itoa(round) + " is live now."
}

func digitsToString(d [4]int) string {
	var sb strings.Builder
	for _, v := range d {
		sb.WriteString(strconv.Itoa(v))
	}
	return sb.String()
}

func Render(path string) string {
	var sb strings.Builder
	sb.WriteString("# Bulls & Cows\n\n")
	sb.WriteString("One shared secret 4-digit code (no repeated digits). Call `Guess(\"1972\")` ")
	sb.WriteString("to get **bulls** (right digit, right spot) and **cows** (right digit, wrong spot). ")
	sb.WriteString("First to 4 bulls wins the round; `GiveUp()` reveals the code and starts over.\n\n")

	sb.WriteString("## Round " + strconv.Itoa(round) + "\n\n")
	sb.WriteString("Attempts so far: **" + strconv.Itoa(attempts) + "**\n\n")

	if len(history) == 0 {
		sb.WriteString("_No guesses yet this round — be the first._\n\n")
	} else {
		sb.WriteString("### Recent guesses\n\n")
		sb.WriteString("| player | guess | bulls | cows |\n|---|---|---|---|\n")
		for i := len(history) - 1; i >= 0; i-- {
			h := history[i]
			sb.WriteString("| " + shortAddr(h.player) + " | " + h.guess + " | " +
				strconv.Itoa(h.bulls) + " | " + strconv.Itoa(h.cows) + " |\n")
		}
		sb.WriteString("\n")
	}

	sb.WriteString("## Leaderboard (fastest solves)\n\n")
	if len(records) == 0 {
		sb.WriteString("_Nobody has cracked a code yet._\n")
	} else {
		sb.WriteString("| rank | player | attempts | round |\n|---|---|---|---|\n")
		for i, r := range records {
			sb.WriteString("| " + strconv.Itoa(i+1) + " | " + shortAddr(r.player) + " | " +
				strconv.Itoa(r.attempts) + " | " + strconv.Itoa(r.round) + " |\n")
		}
	}

	return sb.String()
}

func shortAddr(a string) string {
	if len(a) <= 12 {
		return a
	}
	return a[:6] + "…" + a[len(a)-4:]
}
