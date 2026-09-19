package eightball

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestAnswerIndexInRange(t *testing.T) {
	cases := []struct {
		height int64
		n      int
	}{
		{0, 0}, {1, 0}, {19, 0}, {20, 0}, {21, 5},
		{999999, 3}, {-1, 0}, {-1000, 7},
	}
	for _, c := range cases {
		idx := answerIndex(c.height, c.n)
		uassert.True(t, idx >= 0 && idx < len(answers),
			"index out of range for height="+itoa(c.height))
	}
}

func TestAnswerIndexDeterministic(t *testing.T) {
	uassert.Equal(t, answerIndex(42, 3), answerIndex(42, 3), "same inputs, same slot")
}

func TestRenderEmpty(t *testing.T) {
	out := Render("")
	uassert.NotEmpty(t, out, "render must not be empty")
	uassert.True(t, len(answers) == 20, "classic 8-ball has 20 answers")
}

func itoa(n int64) string {
	neg := n < 0
	if neg {
		n = -n
	}
	if n == 0 {
		return "0"
	}
	var b [24]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
