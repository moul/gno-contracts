// Package semver is an on-chain port of the core of golang.org/x/mod/semver
// (and the spirit of github.com/Masterminds/semver): parse "vMAJOR.MINOR.PATCH
// [-prerelease][+build]" strings and compare them with correct Semantic
// Versioning 2.0.0 precedence. Pure and deterministic — no time, randomness,
// goroutines, or I/O.
//
// This package holds only the pure parsing/comparison API. For a live,
// stateful gnoweb demo that imports it and keeps an on-chain "submitted
// versions" board, see
// [r/moul/x/daily/semverdemo](/r/moul/x/daily/semverdemo/v1).
package semver

import (
	"errors"
	"strings"
)

// Version is a parsed semantic version. Build metadata is retained for display
// but, per the spec, is ignored when comparing precedence.
type Version struct {
	Major, Minor, Patch int
	Pre                 []string // pre-release identifiers (dot-separated)
	Build               string   // build metadata (after '+')
	Orig                string   // original input
}

var errBadVersion = errors.New("invalid semantic version")

// Parse reads "vMAJOR.MINOR.PATCH[-prerelease][+build]". The leading 'v' is
// optional. Numeric fields must be non-empty digit runs without leading zeros.
func Parse(s string) (Version, error) {
	v := Version{Orig: s}
	body := strings.TrimPrefix(s, "v")

	if i := strings.IndexByte(body, '+'); i >= 0 {
		v.Build = body[i+1:]
		body = body[:i]
		if v.Build == "" {
			return Version{}, errBadVersion
		}
	}
	if i := strings.IndexByte(body, '-'); i >= 0 {
		pre := body[i+1:]
		body = body[:i]
		v.Pre = strings.Split(pre, ".")
		for _, id := range v.Pre {
			if !validPreIdent(id) {
				return Version{}, errBadVersion
			}
		}
	}

	parts := strings.Split(body, ".")
	if len(parts) != 3 {
		return Version{}, errBadVersion
	}
	nums := [3]int{}
	for i, p := range parts {
		n, ok := parseNum(p)
		if !ok {
			return Version{}, errBadVersion
		}
		nums[i] = n
	}
	v.Major, v.Minor, v.Patch = nums[0], nums[1], nums[2]
	return v, nil
}

// Compare returns -1, 0, or +1 as a < b, a == b, or a > b under semver
// precedence. Unparseable inputs sort after everything valid (and equal to
// each other), so Compare never panics.
func Compare(a, b string) int {
	va, ea := Parse(a)
	vb, eb := Parse(b)
	switch {
	case ea != nil && eb != nil:
		return 0
	case ea != nil:
		return 1
	case eb != nil:
		return -1
	}
	return va.compare(vb)
}

func (v Version) compare(o Version) int {
	if c := cmpInt(v.Major, o.Major); c != 0 {
		return c
	}
	if c := cmpInt(v.Minor, o.Minor); c != 0 {
		return c
	}
	if c := cmpInt(v.Patch, o.Patch); c != 0 {
		return c
	}
	return comparePre(v.Pre, o.Pre)
}

// comparePre implements SemVer §11: a version WITH a pre-release has lower
// precedence than the same version WITHOUT one.
func comparePre(a, b []string) int {
	if len(a) == 0 && len(b) == 0 {
		return 0
	}
	if len(a) == 0 { // a is a release, b is a pre-release
		return 1
	}
	if len(b) == 0 {
		return -1
	}
	for i := 0; i < len(a) && i < len(b); i++ {
		if c := compareIdent(a[i], b[i]); c != 0 {
			return c
		}
	}
	return cmpInt(len(a), len(b))
}

// compareIdent: numeric identifiers compare numerically and always rank below
// alphanumeric ones; alphanumerics compare in ASCII order.
func compareIdent(a, b string) int {
	an, aNum := parseNum(a)
	bn, bNum := parseNum(b)
	switch {
	case aNum && bNum:
		return cmpInt(an, bn)
	case aNum:
		return -1
	case bNum:
		return 1
	}
	return strings.Compare(a, b)
}

func cmpInt(a, b int) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

// parseNum accepts a non-empty run of ASCII digits with no leading zero (except
// "0" itself), returning the value and whether it qualified.
func parseNum(s string) (int, bool) {
	if s == "" {
		return 0, false
	}
	if len(s) > 1 && s[0] == '0' {
		return 0, false
	}
	n := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	return n, true
}

// validPreIdent allows [0-9A-Za-z-] and rejects empty identifiers.
func validPreIdent(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		ok := (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') || c == '-'
		if !ok {
			return false
		}
	}
	return true
}

// Canonical renders the parsed version back to a canonical string.
func (v Version) Canonical() string {
	s := ufmt(v.Major) + "." + ufmt(v.Minor) + "." + ufmt(v.Patch)
	if len(v.Pre) > 0 {
		s += "-" + strings.Join(v.Pre, ".")
	}
	if v.Build != "" {
		s += "+" + v.Build
	}
	return s
}

func ufmt(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}
