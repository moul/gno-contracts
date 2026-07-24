package urlshort

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestIsAlphanumeric(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"", false},
		{"abc", true},
		{"ABC123", true},
		{"a b", false},
		{"a-b", false},
		{"under_score", false},
		{"9", true},
	}
	for _, c := range cases {
		if got := isAlphanumeric(c.in); got != c.want {
			t.Errorf("isAlphanumeric(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestItoa(t *testing.T) {
	cases := []struct {
		in   int
		want string
	}{
		{0, "0"},
		{7, "7"},
		{42, "42"},
		{1000, "1000"},
	}
	for _, c := range cases {
		if got := itoa(c.in); got != c.want {
			t.Errorf("itoa(%d) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestShortenAndRender(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	Shorten(cross(cur), "gno", "https://gno.land", "the chain")

	url, ok := Lookup("gno")
	uassert.True(t, ok, "alias should exist")
	uassert.Equal(t, "https://gno.land", url)

	// Detail render bumps the click counter.
	out := Render("/gno")
	uassert.True(t, strings.Contains(out, "https://gno.land"), "detail shows url")
	uassert.True(t, strings.Contains(out, "Clicks:** 1"), "click counted")

	// Index lists the alias.
	idx := Render("/")
	uassert.True(t, strings.Contains(idx, "[gno](/gno)"), "index lists alias")
}

func TestShortenOwnershipRules(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice2")
	bob := testutils.TestAddress("bob2")

	testing.SetRealm(testing.NewUserRealm(alice))
	Shorten(cross(cur), "mine", "https://a.example", "")

	// Bob cannot overwrite alice's alias.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "alias already taken by another owner", func() {
		Shorten(cross(cur), "mine", "https://b.example", "")
	})

	// Alice can update her own.
	testing.SetRealm(testing.NewUserRealm(alice))
	Shorten(cross(cur), "mine", "https://a2.example", "updated")
	url, _ := Lookup("mine")
	uassert.Equal(t, "https://a2.example", url)

	// Invalid alias aborts.
	uassert.AbortsWithMessage(t, cur, "alias must be non-empty and alphanumeric", func() {
		Shorten(cross(cur), "bad alias", "https://x.example", "")
	})

	// Empty url aborts.
	uassert.AbortsWithMessage(t, cur, "url must be non-empty", func() {
		Shorten(cross(cur), "okalias", "", "")
	})
}

func TestRemoveRules(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice3")
	bob := testutils.TestAddress("bob3")

	testing.SetRealm(testing.NewUserRealm(alice))
	Shorten(cross(cur), "rm", "https://rm.example", "")

	// Bob cannot remove alice's alias.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "only the owner can remove an alias", func() {
		Remove(cross(cur), "rm")
	})

	// Alice removes her own.
	testing.SetRealm(testing.NewUserRealm(alice))
	Remove(cross(cur), "rm")
	_, ok := Lookup("rm")
	uassert.False(t, ok, "alias should be gone")
}
