// Package countminsketchdemo is a small gnoweb demo of the frequency sketch
// provided by the
// [p/moul/x/daily/countminsketch](/p/moul/x/daily/countminsketch/v1) library:
// fixed storage, one-sided error, and what a collision looks like.
//
// It contains no sketch logic of its own. Stateless, so Render is
// deterministic — which is precisely what the library is for.
package countminsketchdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/countminsketch/v1"
)

// stream is the workload: a few heavy hitters and a long tail.
var stream = buildStream()

func buildStream() []string {
	var out []string
	for i := 0; i < 40; i++ {
		out = append(out, "alice")
	}
	for i := 0; i < 25; i++ {
		out = append(out, "bob")
	}
	for i := 0; i < 10; i++ {
		out = append(out, "carol")
	}
	for i := 0; i < 120; i++ { // the tail: 120 distinct one-offs
		out = append(out, "user"+strconv.Itoa(i))
	}
	return out
}

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Count–Min Sketch\n\n")
	b.WriteString("Frequency estimates in fixed space, demoing the ")
	b.WriteString("[`p/moul/x/daily/countminsketch`](/p/moul/x/daily/countminsketch/v1) library.\n\n")

	b.WriteString("## The workload\n\n")
	b.WriteString("`" + strconv.Itoa(len(stream)) + "` events over `123` distinct keys: ")
	b.WriteString("three heavy hitters and a long tail of one-offs.\n\n")

	big, _ := countminsketch.New(1024, 4)
	fill(big)

	b.WriteString("## A generously sized sketch (1024 × 4)\n\n")
	b.WriteString("| key | true | estimate |\n|---|---|---|\n")
	for _, k := range []string{"alice", "bob", "carol", "user0", "never-seen"} {
		b.WriteString("| `" + k + "` | " + strconv.Itoa(trueCount(k)) + " | " +
			strconv.FormatInt(big.Estimate(k), 10) + " |\n")
	}
	b.WriteString("\nExact here, and `never-seen` reads `0` — a **zero estimate is ")
	b.WriteString("definitive**: that key was never added.\n\n")

	tiny, _ := countminsketch.New(8, 2)
	fill(tiny)

	b.WriteString("## A deliberately tiny one (8 × 2)\n\n")
	b.WriteString("Only `" + strconv.Itoa(tiny.Counters()) + "` counters for `123` distinct ")
	b.WriteString("keys, so collisions are guaranteed:\n\n")
	b.WriteString("| key | true | estimate | error |\n|---|---|---|---|\n")
	for _, k := range []string{"alice", "bob", "carol", "user0"} {
		est := tiny.Estimate(k)
		b.WriteString("| `" + k + "` | " + strconv.Itoa(trueCount(k)) + " | " +
			strconv.FormatInt(est, 10) + " | +" +
			strconv.FormatInt(est-int64(trueCount(k)), 10) + " |\n")
	}
	b.WriteString("\nEvery error is **positive**. That is the guarantee: the sketch may ")
	b.WriteString("overcount, never undercount, so an estimate is an upper bound — ")
	b.WriteString("\"at most this often\", never \"exactly this often\".\n\n")

	b.WriteString("## Where the collisions are\n\n")
	b.WriteString("Row 0 of the tiny sketch, and the column each key lands in:\n\n")
	b.WriteString("| column | counter |\n|---|---|\n")
	for c, v := range tiny.Row(0) {
		who := []string{}
		for _, k := range []string{"alice", "bob", "carol"} {
			if tiny.Index(k, 0) == c {
				who = append(who, "`"+k+"`")
			}
		}
		line := "| " + strconv.Itoa(c) + " | " + strconv.FormatInt(v, 10)
		if len(who) > 0 {
			line += " ← " + strings.Join(who, ", ")
		}
		b.WriteString(line + " |\n")
	}
	b.WriteString("\nTaking the **minimum** across rows is what limits the damage: an ")
	b.WriteString("overestimate needs a collision in *every* row at once.\n\n")

	b.WriteString("## Why bother\n\n")
	b.WriteString("| | exact map | sketch (1024 × 4) |\n|---|---|---|\n")
	b.WriteString("| storage | one entry per distinct key, unbounded | ")
	b.WriteString(strconv.Itoa(big.Counters()) + " counters, fixed |\n")
	b.WriteString("| answer | exact | upper bound |\n")
	b.WriteString("\nOn chain the second row is the point: storage driven by user input ")
	b.WriteString("is a liability, and a sketch sized once cannot be made to grow.\n")
	return b.String()
}

func fill(s *countminsketch.Sketch) {
	for _, e := range stream {
		s.Add(e)
	}
}

func trueCount(k string) int {
	n := 0
	for _, e := range stream {
		if e == k {
			n++
		}
	}
	return n
}
