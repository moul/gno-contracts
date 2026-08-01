// Package sievedemo is a small gnoweb demo of the Sieve of Eratosthenes
// provided by the [p/moul/x/daily/sieve](/p/moul/x/daily/sieve/v1) library: it
// renders the primes up to MaxN, the first 100 primes, and an interactive
// "primes up to n" grid.
//
// It contains no sieve logic of its own — everything comes from
// `sieve.PrimesUpTo` and `sieve.MaxN`.
package sievedemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/sieve/v1"
)

// Render renders the sieve for gnoweb.
//
//	Render("")      / Render("/") -> first 100 primes + total count up to MaxN
//	Render("/<n>")               -> every prime <= n, laid out as a grid
func Render(path string) string {
	n, hasN := parseN(path)

	var b strings.Builder
	b.WriteString("# Sieve of Eratosthenes\n\n")
	b.WriteString("A deterministic on-chain port of Go's classic concurrent prime-sieve example, ")
	b.WriteString("demoing the [`p/moul/x/daily/sieve`](/p/moul/x/daily/sieve/v1) library.\n\n")

	if !hasN {
		primes := sieve.PrimesUpTo(sieve.MaxN)
		b.WriteString("There are **")
		b.WriteString(strconv.Itoa(len(primes)))
		b.WriteString("** primes up to ")
		b.WriteString(strconv.Itoa(sieve.MaxN))
		b.WriteString(".\n\n")
		b.WriteString("## First 100 primes\n\n")
		first := primes
		if len(first) > 100 {
			first = first[:100]
		}
		b.WriteString(grid(first, 10))
		b.WriteString("\n> Try `/500` or `/1000` to sieve up to any n (max ")
		b.WriteString(strconv.Itoa(sieve.MaxN))
		b.WriteString(").\n")
		return b.String()
	}

	if n < 2 {
		b.WriteString("No primes <= ")
		b.WriteString(strconv.Itoa(n))
		b.WriteString(".\n")
		return b.String()
	}

	clamped := n
	if clamped > sieve.MaxN {
		clamped = sieve.MaxN
	}
	primes := sieve.PrimesUpTo(clamped)
	b.WriteString("## Primes up to ")
	b.WriteString(strconv.Itoa(clamped))
	if clamped != n {
		b.WriteString(" (clamped from ")
		b.WriteString(strconv.Itoa(n))
		b.WriteString(")")
	}
	b.WriteString("\n\n")
	b.WriteString("Count: **")
	b.WriteString(strconv.Itoa(len(primes)))
	b.WriteString("**\n\n")
	b.WriteString(grid(primes, 10))
	return b.String()
}

// parseN extracts n from a Render path like "/1000". Returns hasN=false for
// the empty/root path.
func parseN(path string) (int, bool) {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if s == "" {
		return 0, false
	}
	// keep only the first segment
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0, false
	}
	return v, true
}

// grid formats primes into a Markdown table with `cols` columns per row.
func grid(primes []int, cols int) string {
	if len(primes) == 0 {
		return "_none_\n"
	}
	if cols < 1 {
		cols = 1
	}

	var b strings.Builder
	// header + separator so gnoweb renders it as a table
	b.WriteString("|")
	for c := 0; c < cols; c++ {
		b.WriteString(" · |")
	}
	b.WriteString("\n|")
	for c := 0; c < cols; c++ {
		b.WriteString("---|")
	}
	b.WriteString("\n")

	for i := 0; i < len(primes); i += cols {
		b.WriteString("|")
		for c := 0; c < cols; c++ {
			b.WriteString(" ")
			if i+c < len(primes) {
				b.WriteString(strconv.Itoa(primes[i+c]))
			}
			b.WriteString(" |")
		}
		b.WriteString("\n")
	}
	return b.String()
}
