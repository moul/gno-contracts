package sieve

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPrimesUpTo(t *testing.T) {
	cases := []struct {
		name string
		n    int
		want []int
	}{
		{"below two", 1, []int{}},
		{"exactly two", 2, []int{2}},
		{"ten", 10, []int{2, 3, 5, 7}},
		{"thirty", 30, []int{2, 3, 5, 7, 11, 13, 17, 19, 23, 29}},
	}

	for _, tc := range cases {
		got := PrimesUpTo(tc.n)
		uassert.Equal(t, len(tc.want), len(got), tc.name+": length")
		for i := range tc.want {
			if i >= len(got) {
				break
			}
			uassert.Equal(t, tc.want[i], got[i], tc.name+": element")
		}
	}

	// π(100) == 25, π(1000) == 168 — classic sieve landmarks.
	uassert.Equal(t, 25, len(PrimesUpTo(100)), "pi(100)")
	uassert.Equal(t, 168, len(PrimesUpTo(1000)), "pi(1000)")

	// clamping: anything above MaxN yields the same set as MaxN.
	uassert.Equal(t, len(PrimesUpTo(MaxN)), len(PrimesUpTo(MaxN+5000)), "clamp")
}

func TestIsPrimeAndNthPrime(t *testing.T) {
	primeCases := []int{2, 3, 5, 7, 11, 13, 9973}
	for _, p := range primeCases {
		uassert.True(t, IsPrime(p), "expected prime")
	}

	compositeCases := []int{0, 1, 4, 9, 100, 9975}
	for _, c := range compositeCases {
		uassert.False(t, IsPrime(c), "expected non-prime")
	}

	uassert.Equal(t, 2, NthPrime(1), "1st prime")
	uassert.Equal(t, 29, NthPrime(10), "10th prime")
	uassert.Equal(t, 541, NthPrime(100), "100th prime")
	uassert.Equal(t, 0, NthPrime(0), "0th prime is invalid")
}
