package lottery

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPickIndex(t *testing.T) {
	cases := []struct {
		height int64
		n      int
		want   int
	}{
		{0, 3, 0},
		{1, 3, 1},
		{2, 3, 2},
		{3, 3, 0},
		{10, 4, 2},
		{100, 7, 2},
		{5, 1, 0},
	}
	for _, tc := range cases {
		got := pickIndex(tc.height, tc.n)
		uassert.Equal(t, tc.want, got)
		if got < 0 || got >= tc.n {
			t.Errorf("index %d out of range for n=%d", got, tc.n)
		}
	}
}

func TestWinnerKey(t *testing.T) {
	cases := []struct {
		round int
		want  string
	}{
		{1, "000000001"},
		{42, "000000042"},
		{1000, "000001000"},
		{123456789, "123456789"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, winnerKey(tc.round))
	}
	// Zero-padding must preserve chronological ordering under string compare.
	uassert.True(t, winnerKey(2) > winnerKey(1))
	uassert.True(t, winnerKey(10) > winnerKey(9))
	uassert.True(t, winnerKey(100) > winnerKey(99))
}
