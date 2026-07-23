// Package hello is a canary realm: it proves the end-to-end pipeline (workspace
// resolution of a versioned local dependency, gno test, gno lint, and CI)
// works from the very first commit. It has no external dependencies. Remove it
// once real realms land.
package hello

import (
	"strings"

	"gno.land/p/moul/greet/v1"
)

// greets counts how many times Greet has been called (persistent state).
var greets int

// Greet records a greeting from the caller and returns it. Crossing function:
// it mutates persistent state, so it takes `cur realm` per the gno 0.9
// interrealm convention.
func Greet(cur realm, name string) string {
	greets++
	return greet.Greet(name)
}

// Count returns how many greetings have been recorded. Read-only.
func Count() int { return greets }

// Render is the gnoweb Markdown view.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# r/moul/hello/v1\n\n")
	b.WriteString("Canary realm for the gno-contracts repository.\n\n")
	b.WriteString("- Greetings recorded: ")
	b.WriteString(itoa(greets))
	b.WriteString("\n")
	return b.String()
}

// itoa avoids importing strconv for a single conversion in the canary.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
