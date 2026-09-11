package semver

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParse(t *testing.T) {
	cases := []struct {
		in    string
		ok    bool
		major int
		minor int
		patch int
		npre  int
		build string
	}{
		{"1.2.3", true, 1, 2, 3, 0, ""},
		{"v1.2.3", true, 1, 2, 3, 0, ""},
		{"1.0.0-alpha", true, 1, 0, 0, 1, ""},
		{"1.0.0-alpha.1", true, 1, 0, 0, 2, ""},
		{"2.0.0+build.5", true, 2, 0, 0, 0, "build.5"},
		{"1.0.0-rc.1+ci.7", true, 1, 0, 0, 2, "ci.7"},
		{"1.2", false, 0, 0, 0, 0, ""},
		{"1.2.3.4", false, 0, 0, 0, 0, ""},
		{"1.2.x", false, 0, 0, 0, 0, ""},
		{"01.2.3", false, 0, 0, 0, 0, ""},
		{"1.0.0-", false, 0, 0, 0, 0, ""},
		{"", false, 0, 0, 0, 0, ""},
	}
	for _, c := range cases {
		v, err := Parse(c.in)
		if !c.ok {
			uassert.Error(t, err, "expected error for "+c.in)
			continue
		}
		uassert.NoError(t, err, "unexpected error for "+c.in)
		uassert.Equal(t, c.major, v.Major, "major "+c.in)
		uassert.Equal(t, c.minor, v.Minor, "minor "+c.in)
		uassert.Equal(t, c.patch, v.Patch, "patch "+c.in)
		uassert.Equal(t, c.npre, len(v.Pre), "pre count "+c.in)
		uassert.Equal(t, c.build, v.Build, "build "+c.in)
	}
}

func TestCompare(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		// numeric fields compare numerically, not lexically
		{"1.2.3", "1.2.10", -1},
		{"1.2.10", "1.2.3", 1},
		{"1.0.0", "1.0.0", 0},
		{"2.0.0", "1.9.9", 1},
		{"1.1.0", "1.0.9", 1},
		// pre-release < release
		{"1.0.0-alpha", "1.0.0", -1},
		{"1.0.0", "1.0.0-alpha", 1},
		{"1.0.0-rc.1", "1.0.0", -1},
		// pre-release ordering per SemVer §11 spec example
		{"1.0.0-alpha", "1.0.0-alpha.1", -1},
		{"1.0.0-alpha.1", "1.0.0-alpha.beta", -1},
		{"1.0.0-alpha.beta", "1.0.0-beta", -1},
		{"1.0.0-beta", "1.0.0-beta.2", -1},
		{"1.0.0-beta.2", "1.0.0-beta.11", -1},
		{"1.0.0-beta.11", "1.0.0-rc.1", -1},
		// build metadata does not affect precedence
		{"1.0.0", "1.0.0+build.99", 0},
		{"1.0.0+a", "1.0.0+b", 0},
		// invalid inputs sort last, equal to each other
		{"nope", "1.0.0", 1},
		{"1.0.0", "nope", -1},
		{"nope", "still-bad", 0},
	}
	for _, c := range cases {
		got := Compare(c.a, c.b)
		uassert.Equal(t, c.want, got, c.a+" vs "+c.b)
	}
}

func TestComparePreHelper(t *testing.T) {
	uassert.Equal(t, 0, comparePre(nil, nil), "both empty")
	uassert.Equal(t, 1, comparePre(nil, []string{"alpha"}), "release > prerelease")
	uassert.Equal(t, -1, comparePre([]string{"alpha"}, nil), "prerelease < release")
	uassert.Equal(t, -1, comparePre([]string{"1"}, []string{"alpha"}), "numeric id < alnum id")
	uassert.Equal(t, -1, comparePre([]string{"alpha"}, []string{"alpha", "1"}), "shorter < longer prefix")
}

func TestParseNumHelper(t *testing.T) {
	n, ok := parseNum("0")
	uassert.True(t, ok, "0 is valid")
	uassert.Equal(t, 0, n, "0 value")

	n, ok = parseNum("123")
	uassert.True(t, ok, "123 valid")
	uassert.Equal(t, 123, n, "123 value")

	_, ok = parseNum("00")
	uassert.False(t, ok, "leading zero invalid")
	_, ok = parseNum("12a")
	uassert.False(t, ok, "non-digit invalid")
	_, ok = parseNum("")
	uassert.False(t, ok, "empty invalid")
}
