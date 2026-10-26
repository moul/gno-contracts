package rps

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParse(t *testing.T) {
	cases := []struct {
		in   string
		want Move
		ok   bool
	}{
		{"rock", Rock, true},
		{"Rock", Rock, true},
		{" r ", Rock, true},
		{"PAPER", Paper, true},
		{"p", Paper, true},
		{" scissors ", Scissors, true},
		{"S", Scissors, true},
		{"lizard", 0, false},
		{"", 0, false},
		{"ro", 0, false},
	}
	for _, c := range cases {
		got, ok := Parse(c.in)
		uassert.Equal(t, c.ok, ok, c.in)
		uassert.Equal(t, int(c.want), int(got), c.in)
	}
}

func TestString(t *testing.T) {
	uassert.Equal(t, "rock", Rock.String())
	uassert.Equal(t, "paper", Paper.String())
	uassert.Equal(t, "scissors", Scissors.String())
	uassert.Equal(t, "?", Move(3).String())
	uassert.Equal(t, "?", Move(-1).String())
}

func TestBeats(t *testing.T) {
	cases := []struct {
		a, b Move
		want int
	}{
		{Rock, Rock, 0},
		{Paper, Paper, 0},
		{Scissors, Scissors, 0},
		{Paper, Rock, 1},
		{Scissors, Paper, 1},
		{Rock, Scissors, 1},
		{Rock, Paper, 2},
		{Paper, Scissors, 2},
		{Scissors, Rock, 2},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Beats(c.a, c.b), c.a.String()+" vs "+c.b.String())
	}
}

// Every move parses back from its own name.
func TestRoundTrip(t *testing.T) {
	for _, m := range []Move{Rock, Paper, Scissors} {
		got, ok := Parse(m.String())
		uassert.True(t, ok)
		uassert.Equal(t, int(m), int(got))
	}
}
