// Package eightball is a Magic 8-Ball realm: ask a yes/no question and the
// block height decides your fate. Deterministic (no real randomness on-chain).
package eightball

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
)

// The 20 classic Magic 8-Ball answers.
var answers = []string{
	"It is certain.", "It is decidedly so.", "Without a doubt.",
	"Yes definitely.", "You may rely on it.", "As I see it, yes.",
	"Most likely.", "Outlook good.", "Yes.", "Signs point to yes.",
	"Reply hazy, try again.", "Ask again later.", "Better not tell you now.",
	"Cannot predict now.", "Concentrate and ask again.",
	"Don't count on it.", "My reply is no.", "My sources say no.",
	"Outlook not so good.", "Very doubtful.",
}

type shake struct {
	asker    string
	question string
	answer   string
	height   int64
}

var history []shake

// answerIndex maps (block height, prior shakes) to an answer slot. Pure and
// deterministic so it can be tested without touching realm state.
func answerIndex(height int64, n int) int {
	i := (height + int64(n)) % int64(len(answers))
	if i < 0 {
		i += int64(len(answers))
	}
	return int(i)
}

// Ask poses a question to the Magic 8-Ball and returns its answer. Crossing
// function: it mutates persistent state, so it takes `cur realm` (gno 0.9).
func Ask(cur realm, question string) string {
	question = strings.TrimSpace(question)
	if question == "" {
		panic("question must not be empty")
	}
	if len(question) > 200 {
		panic("question too long (max 200 chars)")
	}
	h := runtime.ChainHeight()
	ans := answers[answerIndex(h, len(history))]
	history = append(history, shake{
		asker:    unsafe.PreviousRealm().Address().String(),
		question: question,
		answer:   ans,
		height:   h,
	})
	chain.Emit("Shaken", "answer", ans, "height", strconv.FormatInt(h, 10))
	return ans
}

// Asked returns how many questions have been asked. Read-only.
func Asked() int { return len(history) }

// Render is the gnoweb Markdown view.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# 🎱 Magic 8-Ball\n\n")
	b.WriteString("> ⚠️ Experimental, auto-generated with no human supervision (MCP test corpus). ")
	b.WriteString("Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).\n\n")
	b.WriteString("Ask a yes/no question — the block height decides your fate.\n\n")
	b.WriteString("**Questions asked:** ")
	b.WriteString(strconv.Itoa(len(history)))
	b.WriteString("\n\n")

	if len(history) == 0 {
		b.WriteString("_No questions yet. Call `Ask(\"will it rain tomorrow?\")`._\n")
		return b.String()
	}

	last := history[len(history)-1]
	b.WriteString("Last shake: 🎱 _")
	b.WriteString(last.answer)
	b.WriteString("_\n\n| # | asker | question | answer | height |\n")
	b.WriteString("|---|---|---|---|---|\n")

	start := len(history) - 1
	end := start - 14
	if end < 0 {
		end = 0
	}
	for i := start; i >= end; i-- {
		e := history[i]
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(i + 1))
		b.WriteString(" | ")
		b.WriteString(shortAddr(e.asker))
		b.WriteString(" | ")
		b.WriteString(e.question)
		b.WriteString(" | ")
		b.WriteString(e.answer)
		b.WriteString(" | ")
		b.WriteString(strconv.FormatInt(e.height, 10))
		b.WriteString(" |\n")
	}
	return b.String()
}

func shortAddr(a string) string {
	if len(a) <= 13 {
		return a
	}
	return a[:8] + "…" + a[len(a)-4:]
}
