package cron

import (
	"testing"
	"time"
)

// at is shorthand for a UTC instant, so the tables below read as dates.
func at(y int, mo time.Month, d, h, mi int) time.Time {
	return time.Date(y, mo, d, h, mi, 0, 0, time.UTC)
}

func TestParseRejects(t *testing.T) {
	cases := []struct {
		name string
		expr string
	}{
		{"empty", ""},
		{"blank", "   "},
		{"four fields", "* * * *"},
		{"six fields", "* * * * * *"},
		{"minute out of range", "60 * * * *"},
		{"hour out of range", "* 24 * * *"},
		{"day zero", "* * 0 * *"},
		{"month thirteen", "* * * 13 *"},
		{"weekday eight", "* * * * 8"},
		{"backwards range", "* * * * 5-1"},
		{"zero step", "*/0 * * * *"},
		{"negative step", "*/-2 * * * *"},
		{"empty list item", "1,,2 * * * *"},
		{"not a number", "abc * * * *"},
		{"unknown name", "* * * smarch *"},
		{"unknown macro", "@fortnightly"},
		{"macro with fields", "@daily extra"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := Parse(tc.expr); err == nil {
				t.Fatalf("Parse(%q): want error, got nil", tc.expr)
			}
		})
	}
}

func TestNext(t *testing.T) {
	base := at(2026, time.March, 10, 9, 17)
	cases := []struct {
		name string
		expr string
		from time.Time
		want time.Time
	}{
		{"every minute", "* * * * *", base, at(2026, time.March, 10, 9, 18)},
		{"quarter hour", "*/15 * * * *", base, at(2026, time.March, 10, 9, 30)},
		{"top of hour", "0 * * * *", base, at(2026, time.March, 10, 10, 0)},
		{"list", "5,25,45 * * * *", base, at(2026, time.March, 10, 9, 25)},
		{"step from value", "5/20 * * * *", base, at(2026, time.March, 10, 9, 25)},
		{"range with step", "0-30/10 * * * *", base, at(2026, time.March, 10, 9, 20)},
		{"workday morning", "30 8 * * 1-5", base, at(2026, time.March, 11, 8, 30)},
		{"weekend only", "0 12 * * sat,sun", base, at(2026, time.March, 14, 12, 0)},
		{"month list", "0 0 1 jan,jul *", base, at(2026, time.July, 1, 0, 0)},
		{"end of month", "0 0 31 * *", base, at(2026, time.March, 31, 0, 0)},
		{"leap day", "0 0 29 2 *", base, at(2028, time.February, 29, 0, 0)},
		{"next minute is exclusive", "17 9 * * *", base, at(2026, time.March, 11, 9, 17)},
		{"seconds are discarded", "* * * * *", base.Add(42 * time.Second), at(2026, time.March, 10, 9, 18)},
		{"year rolls over", "0 0 1 1 *", base, at(2027, time.January, 1, 0, 0)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s, err := Parse(tc.expr)
			if err != nil {
				t.Fatalf("Parse(%q): %v", tc.expr, err)
			}
			got, ok := s.Next(tc.from)
			if !ok {
				t.Fatalf("Next(%q): no match within the horizon", tc.expr)
			}
			if !got.Equal(tc.want) {
				t.Errorf("Next(%q) from %v = %v, want %v", tc.expr, tc.from, got, tc.want)
			}
		})
	}
}

// TestDayOrDay pins the one rule a cron parser is actually written for: when
// both day fields are restricted the match is a UNION, not an intersection.
func TestDayOrDay(t *testing.T) {
	// The 13th of March 2026 is a Friday, so a naive AND would hide the bug.
	// April 2026 separates them: Friday the 3rd comes before the 13th.
	s, err := Parse("0 0 13 * 5")
	if err != nil {
		t.Fatal(err)
	}
	got, ok := s.Next(at(2026, time.March, 20, 0, 0))
	if !ok {
		t.Fatal("no match")
	}
	if want := at(2026, time.March, 27, 0, 0); !got.Equal(want) {
		t.Errorf("first = %v, want %v (a Friday, not the 13th)", got, want)
	}
	got, ok = s.Next(at(2026, time.April, 8, 0, 0))
	if !ok {
		t.Fatal("no match")
	}
	if want := at(2026, time.April, 10, 0, 0); !got.Equal(want) {
		t.Errorf("second = %v, want %v", got, want)
	}
}

func TestDayFieldRestriction(t *testing.T) {
	cases := []struct {
		name string
		expr string
		from time.Time
		want time.Time
	}{
		// Day-of-week alone: every day-of-month qualifies, so it is an AND
		// with a field that matches everything.
		{"dow only", "0 0 * * 3", at(2026, time.March, 10, 0, 0), at(2026, time.March, 11, 0, 0)},
		// Day-of-month alone, same reasoning mirrored.
		{"dom only", "0 0 15 * *", at(2026, time.March, 10, 0, 0), at(2026, time.March, 15, 0, 0)},
		// Neither restricted: the next midnight.
		{"neither", "0 0 * * *", at(2026, time.March, 10, 0, 0), at(2026, time.March, 11, 0, 0)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s, err := Parse(tc.expr)
			if err != nil {
				t.Fatal(err)
			}
			got, ok := s.Next(tc.from)
			if !ok {
				t.Fatal("no match")
			}
			if !got.Equal(tc.want) {
				t.Errorf("Next(%q) = %v, want %v", tc.expr, got, tc.want)
			}
		})
	}
}

// TestSundayIsSevenToo pins the historical alias: 0 and 7 are both Sunday, and
// 5-7 therefore has to mean Friday through Sunday rather than running backwards.
func TestSundayIsSevenToo(t *testing.T) {
	from := at(2026, time.March, 10, 0, 0) // a Tuesday
	zero, err := Parse("0 0 * * 0")
	if err != nil {
		t.Fatal(err)
	}
	seven, err := Parse("0 0 * * 7")
	if err != nil {
		t.Fatal(err)
	}
	a, _ := zero.Next(from)
	b, _ := seven.Next(from)
	if !a.Equal(b) {
		t.Errorf("dow 0 gave %v, dow 7 gave %v", a, b)
	}
	if want := at(2026, time.March, 15, 0, 0); !a.Equal(want) {
		t.Errorf("Sunday = %v, want %v", a, want)
	}

	wrap, err := Parse("0 0 * * 5-7")
	if err != nil {
		t.Fatalf("5-7 must span Friday to Sunday: %v", err)
	}
	for _, d := range []int{13, 14, 15} {
		if !wrap.Matches(at(2026, time.March, d, 0, 0)) {
			t.Errorf("5-7 should match March %d", d)
		}
	}
	if wrap.Matches(at(2026, time.March, 16, 0, 0)) {
		t.Error("5-7 should not match Monday")
	}
}

func TestMacros(t *testing.T) {
	cases := []struct {
		macro string
		same  string
	}{
		{"@yearly", "0 0 1 1 *"},
		{"@annually", "0 0 1 1 *"},
		{"@monthly", "0 0 1 * *"},
		{"@weekly", "0 0 * * 0"},
		{"@daily", "0 0 * * *"},
		{"@midnight", "0 0 * * *"},
		{"@hourly", "0 * * * *"},
	}
	from := at(2026, time.March, 10, 9, 17)
	for _, tc := range cases {
		t.Run(tc.macro, func(t *testing.T) {
			m, err := Parse(tc.macro)
			if err != nil {
				t.Fatal(err)
			}
			plain, err := Parse(tc.same)
			if err != nil {
				t.Fatal(err)
			}
			a, _ := m.Next(from)
			b, _ := plain.Next(from)
			if !a.Equal(b) {
				t.Errorf("%s = %v, %s = %v", tc.macro, a, tc.same, b)
			}
			if m.Expr() != tc.macro {
				t.Errorf("Expr() = %q, want the original %q", m.Expr(), tc.macro)
			}
		})
	}
}

// TestImpossible: a schedule with no instant at all must say so rather than
// loop. February never has a 30th.
func TestImpossible(t *testing.T) {
	s, err := Parse("0 0 30 2 *")
	if err != nil {
		t.Fatalf("Parse must accept it, only Next can know: %v", err)
	}
	if got, ok := s.Next(at(2026, time.March, 10, 0, 0)); ok {
		t.Errorf("want no match, got %v", got)
	}
}

func TestMatches(t *testing.T) {
	s, err := Parse("30 8 * * 1-5")
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		at   time.Time
		want bool
	}{
		{"wednesday 8:30", at(2026, time.March, 11, 8, 30), true},
		{"wednesday 8:31", at(2026, time.March, 11, 8, 31), false},
		{"saturday 8:30", at(2026, time.March, 14, 8, 30), false},
		{"seconds ignored", at(2026, time.March, 11, 8, 30).Add(59 * time.Second), true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := s.Matches(tc.at); got != tc.want {
				t.Errorf("Matches(%v) = %v, want %v", tc.at, got, tc.want)
			}
		})
	}
}

func TestNextN(t *testing.T) {
	s, err := Parse("0 */6 * * *")
	if err != nil {
		t.Fatal(err)
	}
	got := s.NextN(at(2026, time.March, 10, 9, 17), 4)
	want := []time.Time{
		at(2026, time.March, 10, 12, 0),
		at(2026, time.March, 10, 18, 0),
		at(2026, time.March, 11, 0, 0),
		at(2026, time.March, 11, 6, 0),
	}
	if len(got) != len(want) {
		t.Fatalf("got %d times, want %d", len(got), len(want))
	}
	for i := range want {
		if !got[i].Equal(want[i]) {
			t.Errorf("[%d] = %v, want %v", i, got[i], want[i])
		}
	}
	if n := len(s.NextN(at(2026, time.March, 10, 9, 17), 0)); n != 0 {
		t.Errorf("NextN(_, 0) returned %d times, want none", n)
	}
	impossible, err := Parse("0 0 30 2 *")
	if err != nil {
		t.Fatal(err)
	}
	if n := len(impossible.NextN(at(2026, time.March, 10, 0, 0), 3)); n != 0 {
		t.Errorf("an impossible schedule yielded %d times", n)
	}
}

func TestMustParsePanics(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Error("MustParse must panic on a bad expression")
		}
	}()
	MustParse("nonsense")
}
