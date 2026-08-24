// Package sieve is an on-chain port of Go's classic concurrent prime sieve
// (the "prime sieve" example from the Go tour / Go source docs), implemented
// as a deterministic, allocation-friendly Sieve of Eratosthenes so it runs
// reproducibly on-chain (no goroutines, channels, or clocks) — as a reusable
// pure package.
//
// A live demo of this package (a gnoweb prime explorer) is at
// [r/moul/x/daily/sievedemo](/r/moul/x/daily/sievedemo/v1).
package sieve

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
