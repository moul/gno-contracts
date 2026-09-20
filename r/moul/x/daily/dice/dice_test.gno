package dice

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
)

// resetState clears package globals between tests since realm state is global.
func resetState() {
	count = [6]int{}
	total = 0
	players = avl.NewTree()
}

func TestDeriveFaceRange(t *testing.T) {
	// Every derived face must land in [1,6] regardless of entropy inputs.
	cases := []struct {
		height int64
		addr   string
		n      int
	}{
		{0, "g1abc", 0},
		{1, "g1abc", 1},
		{999999, "g1xyzxyzxyz", 42},
		{-1, "", 0},
		{123456789, "g1deadbeef", 7},
	}
	for _, c := range cases {
		f := deriveFace(c.height, c.addr, c.n)
		if f < 1 || f > 6 {
			t.Errorf("deriveFace(%d,%q,%d) = %d, want 1..6", c.height, c.addr, c.n, f)
		}
	}
}

func TestDeriveFaceDeterministic(t *testing.T) {
	// Same inputs -> same output (provably fair / reproducible).
	a := deriveFace(100, "g1caller", 3)
	b := deriveFace(100, "g1caller", 3)
	if a != b {
		t.Errorf("deriveFace not deterministic: %d != %d", a, b)
	}
	// Different roll count generally changes entropy; at least it must not panic
	// and must stay in range.
	c := deriveFace(100, "g1caller", 4)
	if c < 1 || c > 6 {
		t.Errorf("deriveFace out of range: %d", c)
	}
}

func TestDeriveFaceVariesByCaller(t *testing.T) {
	// Two different addresses at the same height should not be forced equal;
	// verify the hash actually mixes the address by finding at least one
	// differing pair across a small sweep.
	diff := false
	for i := 0; i < 10; i++ {
		if deriveFace(50, "g1alice", i) != deriveFace(50, "g1bob", i) {
			diff = true
			break
		}
	}
	if !diff {
		t.Error("deriveFace never differs between two distinct callers over 10 rolls")
	}
}

func TestRenderEmpty(t *testing.T) {
	resetState()
	out := Render("")
	if !strings.Contains(out, "Provably-Fair Dice") {
		t.Error("Render missing title")
	}
	if !strings.Contains(out, "Total rolls:** 0") {
		t.Errorf("Render should report 0 total rolls, got:\n%s", out)
	}
	if !strings.Contains(out, "No rolls yet") {
		t.Error("Render should show empty-state message")
	}
}

func TestDistributionAccounting(t *testing.T) {
	resetState()
	// Simulate the state mutations Roll performs, without a realm frame.
	faces := []int{1, 1, 3, 6, 6, 6}
	for _, f := range faces {
		count[f-1]++
		total++
	}
	if total != len(faces) {
		t.Errorf("total = %d, want %d", total, len(faces))
	}
	d := Distribution()
	if d[0] != 2 {
		t.Errorf("face 1 count = %d, want 2", d[0])
	}
	if d[5] != 3 {
		t.Errorf("face 6 count = %d, want 3", d[5])
	}
	if d[1] != 0 {
		t.Errorf("face 2 count = %d, want 0", d[1])
	}
	out := Render("")
	if !strings.Contains(out, "Total rolls:** 6") {
		t.Errorf("Render should report 6 total rolls, got:\n%s", out)
	}
}

func TestBar(t *testing.T) {
	full := bar(10, 10, 10)
	if strings.Count(full, "▓") != 10 {
		t.Errorf("full bar want 10 filled, got %q", full)
	}
	empty := bar(0, 10, 10)
	if strings.Count(empty, "░") != 10 {
		t.Errorf("empty bar want 10 unfilled, got %q", empty)
	}
	half := bar(5, 10, 10)
	if strings.Count(half, "▓") != 5 {
		t.Errorf("half bar want 5 filled, got %q", half)
	}
}
