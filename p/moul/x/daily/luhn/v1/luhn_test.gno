package luhn

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestValid(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"known-good test card", "4539148803436467", true},
		{"spaces ignored", "4539 1488 0343 6467", true},
		{"hyphens ignored", "4539-1488-0343-6467", true},
		{"single digit flipped", "4539148803436468", false},
		{"adjacent transposition", "4539148803436647", false},
		{"classic 79927398713", "79927398713", true},
		{"classic off by one", "79927398710", false},
		{"all zeros is valid", "00", true},
		{"letters rejected", "4539abc8803436467", false},
		{"empty rejected", "", false},
		{"one digit rejected", "7", false},
		{"separators only rejected", " - ", false},
		{"over MaxLen rejected", strings.Repeat("0", MaxLen+1), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			uassert.Equal(t, c.want, Valid(c.in))
		})
	}
}

func TestCheckDigit(t *testing.T) {
	cases := []struct {
		payload string
		want    int
	}{
		{"7992739871", 3},
		{"453914880343646", 7},
		{"0", 0},
	}
	for _, c := range cases {
		got, ok := CheckDigit(c.payload)
		uassert.True(t, ok)
		uassert.Equal(t, c.want, got)
	}
}

func TestCheckDigitRejectsBadInput(t *testing.T) {
	for _, in := range []string{"", "abc", " - "} {
		_, ok := CheckDigit(in)
		uassert.False(t, ok)
	}
}

// Append must produce something Valid accepts — the round-trip property.
func TestAppendRoundTrip(t *testing.T) {
	payloads := []string{"7992739871", "453914880343646", "1", "123456789012345"}
	for _, p := range payloads {
		got, ok := Append(p)
		uassert.True(t, ok)
		uassert.True(t, Valid(got))
		uassert.Equal(t, len(p)+1, len(got))
	}
}

// Append strips separators, so a spaced payload yields the same digits.
func TestAppendStripsSeparators(t *testing.T) {
	a, ok := Append("4539 1488 0343 646")
	uassert.True(t, ok)
	b, ok2 := Append("453914880343646")
	uassert.True(t, ok2)
	uassert.Equal(t, b, a)
	uassert.Equal(t, "4539148803436467", a)
}

// Every single-digit change to a valid number must be caught: that is the
// guarantee Luhn actually makes.
func TestDetectsEverySingleDigitError(t *testing.T) {
	const base = "4539148803436467"
	uassert.True(t, Valid(base))
	for i := 0; i < len(base); i++ {
		for d := byte('0'); d <= '9'; d++ {
			if d == base[i] {
				continue
			}
			mutated := base[:i] + string(d) + base[i+1:]
			uassert.False(t, Valid(mutated))
		}
	}
}
