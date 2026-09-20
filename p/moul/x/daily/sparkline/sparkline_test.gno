package sparkline

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestInts(t *testing.T) {
	tests := []struct {
		name   string
		values []int
		want   string
	}{
		{"empty", nil, ""},
		{"empty slice", []int{}, ""},
		// A single value is its own min and max, i.e. flat: mid-ramp.
		{"single", []int{42}, "▅"},
		{"flat", []int{7, 7, 7}, "▅▅▅"},
		{"flat at zero", []int{0, 0}, "▅▅"},
		{"two apart", []int{0, 1}, "▁█"},
		{"ramp", []int{0, 1, 2, 3, 4, 5, 6, 7}, "▁▂▃▄▅▆▇█"},
		{"descending", []int{7, 6, 5, 4, 3, 2, 1, 0}, "█▇▆▅▄▃▂▁"},
		{"negatives only", []int{-7, -4, 0}, "▁▄█"},
		{"spans zero", []int{-7, 0, 7}, "▁▄█"},
		{"wide range", []int{0, 50, 100}, "▁▄█"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			uassert.Equal(t, tt.want, Ints(tt.values))
		})
	}
}

func TestScaledClampsOutliers(t *testing.T) {
	// The window is the contract: anything outside it pins to an end rather
	// than rescaling the picture or panicking.
	uassert.Equal(t, "▁▁▄██", Scaled([]int{-100, 0, 50, 100, 999}, 0, 100))
}

func TestScaledEmpty(t *testing.T) {
	uassert.Equal(t, "", Scaled(nil, 0, 10))
}

func TestScaledFlatWindow(t *testing.T) {
	// hi <= lo carries no shape; every value lands mid-ramp.
	uassert.Equal(t, "▅▅▅", Scaled([]int{1, 500, 9}, 5, 5))
	uassert.Equal(t, "▅▅", Scaled([]int{1, 2}, 10, 3))
}

func TestLevel(t *testing.T) {
	tests := []struct {
		name       string
		v, lo, hi  int
		want       int
	}{
		{"at floor", 0, 0, 7, 0},
		{"at ceiling", 7, 0, 7, 7},
		{"below floor clamps", -5, 0, 7, 0},
		{"above ceiling clamps", 99, 0, 7, 7},
		{"flat window", 3, 5, 5, Steps / 2},
		{"inverted window", 3, 9, 2, Steps / 2},
		// Floor rounding: only hi itself reaches the top.
		{"just below ceiling", 99, 0, 100, 6},
		{"exact ceiling", 100, 0, 100, 7},
		{"midpoint", 50, 0, 100, 3},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			uassert.Equal(t, tt.want, Level(tt.v, tt.lo, tt.hi))
		})
	}
}

// Level must stay inside the ramp for every input, including the extremes that
// make the scaling arithmetic wrap. An out-of-range index here would panic the
// realm that called Scaled, so this is the load-bearing invariant.
func TestLevelAlwaysInRange(t *testing.T) {
	const minInt = -maxInt - 1
	vals := []int{minInt, -maxInt, -1000, -1, 0, 1, 1000, maxInt}
	windows := [][2]int{
		{0, 7}, {0, 100}, {-100, 100}, {5, 5}, {9, 2},
		{minInt, maxInt}, // span wraps int
		{0, maxInt},      // span survives, but d*top would wrap
		{minInt, 0},
	}
	for _, w := range windows {
		for _, v := range vals {
			got := Level(v, w[0], w[1])
			if got < 0 || got >= Steps {
				t.Fatalf("Level(%d, %d, %d) = %d, outside [0,%d)", v, w[0], w[1], got, Steps)
			}
		}
	}
}

// The huge-span path halves its way down to safe arithmetic; it must still be
// monotonic, or the picture would lie about the direction of the trend.
func TestLevelMonotonicOnHugeSpan(t *testing.T) {
	prev := -1
	for _, v := range []int{0, maxInt / 8, maxInt / 4, maxInt / 2, maxInt} {
		got := Level(v, 0, maxInt)
		if got < prev {
			t.Fatalf("Level(%d, 0, maxInt) = %d, went down from %d", v, got, prev)
		}
		prev = got
	}
}

func TestBounds(t *testing.T) {
	lo, hi, ok := Bounds([]int{3, -1, 9, 4})
	uassert.True(t, ok, "non-empty series should report ok")
	uassert.Equal(t, -1, lo)
	uassert.Equal(t, 9, hi)

	lo, hi, ok = Bounds(nil)
	uassert.False(t, ok, "empty series should report not-ok")
	uassert.Equal(t, 0, lo)
	uassert.Equal(t, 0, hi)
}

func TestLevelsRampIsEightRunes(t *testing.T) {
	// Scaled indexes this ramp by Level's result, so the two must agree.
	uassert.Equal(t, Steps, len([]rune(Levels)))
}
