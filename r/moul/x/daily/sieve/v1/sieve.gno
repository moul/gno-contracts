// Package sieve is an on-chain port of Go's classic concurrent prime sieve
// (the "prime sieve" example from the Go tour / Go source docs), implemented
// as a deterministic, allocation-friendly Sieve of Eratosthenes so it runs
// reproducibly on-chain (no goroutines, channels, or clocks).
package sieve

import (
	"strconv"
	"strings"
)

// MaxN bounds the sieve so gas stays predictable.
const MaxN = 10000

// PrimesUpTo returns every prime p with 2 <= p <= n, in ascending order,
// using the Sieve of Eratosthenes. n is clamped to [0, MaxN]. Pure.
func PrimesUpTo(n int) []int {
	if n < 2 {
		return []int{}
	}
	if n > MaxN {
		n = MaxN
	}

	// composite[i] == true once i is known to be non-prime.
	composite := make([]bool, n+1)
	for p := 2; p*p <= n; p++ {
		if composite[p] {
			continue
		}
		for m := p * p; m <= n; m += p {
			composite[m] = true
		}
	}

	primes := []int{}
	for i := 2; i <= n; i++ {
		if !composite[i] {
			primes = append(primes, i)
		}
	}
	return primes
}

// NthPrime returns the k-th prime (1-indexed), or 0 if it lies beyond MaxN.
// Pure helper handy for callers and tests.
func NthPrime(k int) int {
	if k < 1 {
		return 0
	}
	primes := PrimesUpTo(MaxN)
	if k > len(primes) {
		return 0
	}
	return primes[k-1]
}

// IsPrime reports whether x is prime (trial division). Pure.
func IsPrime(x int) bool {
	if x < 2 {
		return false
	}
	for d := 2; d*d <= x; d++ {
		if x%d == 0 {
			return false
		}
	}
	return true
}

// Render renders the sieve for gnoweb.
//
//	Render("")      / Render("/") -> first 100 primes + total count up to MaxN
//	Render("/<n>")               -> every prime <= n, laid out as a grid
func Render(path string) string {
	n, hasN := parseN(path)

	var b strings.Builder
	b.WriteString("# Sieve of Eratosthenes\n\n")
	b.WriteString("A deterministic on-chain port of Go's classic concurrent prime-sieve example.\n\n")

	if !hasN {
		primes := PrimesUpTo(MaxN)
		b.WriteString("There are **")
		b.WriteString(strconv.Itoa(len(primes)))
		b.WriteString("** primes up to ")
		b.WriteString(strconv.Itoa(MaxN))
		b.WriteString(".\n\n")
		b.WriteString("## First 100 primes\n\n")
		first := primes
		if len(first) > 100 {
			first = first[:100]
		}
		b.WriteString(grid(first, 10))
		b.WriteString("\n> Try `/500` or `/1000` to sieve up to any n (max ")
		b.WriteString(strconv.Itoa(MaxN))
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
	if clamped > MaxN {
		clamped = MaxN
	}
	primes := PrimesUpTo(clamped)
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
