package collatz

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestStopping(t *testing.T) {
	cases := []struct {
		n     int64
		steps int
		peak  int64
	}{
		{1, 0, 1},
		{2, 1, 2},
		{6, 8, 16},
		{7, 16, 52},
		{27, 111, 9232},
	}
	for _, c := range cases {
		steps, peak := stopping(c.n)
		uassert.Equal(t, c.steps, steps)
		uassert.Equal(t, c.peak, peak)
	}
}

func TestComputeAndLeaderboard(cur realm, t *testing.T) {
	addr := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(addr))

	Compute(cross(cur), 27)
	Compute(cross(cur), 6)

	out := Render("")
	uassert.True(t, strings.Contains(out, "Leaderboard"), "has leaderboard")
	uassert.True(t, strings.Contains(out, "9232"), "shows peak of 27")
	// 27 has more steps than 6, so it must appear first (rank 1).
	i27 := strings.Index(out, "[27]")
	i6 := strings.Index(out, "[6]")
	uassert.True(t, i27 >= 0 && i6 >= 0, "both rows present")
	uassert.True(t, i27 < i6, "27 ranked above 6")
}

func TestComputeRejectsNonPositive(cur realm, t *testing.T) {
	addr := testutils.TestAddress("bob")
	testing.SetRealm(testing.NewUserRealm(addr))
	uassert.AbortsWithMessage(t, cur, "n must be > 0", func() {
		Compute(cross(cur), 0)
	})
}

func TestRenderSequence(t *testing.T) {
	out := Render("/6")
	uassert.True(t, strings.Contains(out, "6 → 3 → 10 → 5 → 16 → 8 → 4 → 2 → 1"), "full seq for 6")
	uassert.True(t, strings.Contains(out, "steps: 8"), "reports 8 steps")

	bad := Render("/abc")
	uassert.True(t, strings.Contains(bad, "Invalid"), "rejects non-numeric path")
}
