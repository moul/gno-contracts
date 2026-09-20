package forge

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestValidOID(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"sha1", strings.Repeat("a", 40), true},
		{"sha256", strings.Repeat("0", 64), true},
		{"mixed hex", "0123456789abcdef0123456789abcdef01234567", true},
		{"empty", "", false},
		{"too short", strings.Repeat("a", 39), false},
		{"between lengths", strings.Repeat("a", 41), false},
		{"uppercase", strings.Repeat("A", 40), false},
		{"non hex", strings.Repeat("z", 40), false},
		{"abbreviated", "deadbeef", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidOID(tc.in), tc.name)
	}
}

func TestValidRefName(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"branch", "refs/heads/main", true},
		{"nested branch", "refs/heads/feat/on-chain-log", true},
		{"tag", "refs/tags/v1.0.0", true},
		{"stash-like", "refs/stash", true},
		{"unqualified", "main", false},
		{"empty", "", false},
		{"double slash", "refs/heads//main", false},
		{"double dot", "refs/heads/a..b", false},
		{"at brace", "refs/heads/a@{0}", false},
		{"trailing slash", "refs/heads/", false},
		{"trailing dot", "refs/heads/main.", false},
		{"dot prefix", "refs/heads/.hidden", false},
		{"lock suffix", "refs/heads/main.lock", false},
		{"space", "refs/heads/my branch", false},
		{"caret", "refs/heads/main^", false},
		{"colon", "refs/heads/a:b", false},
		{"tilde", "refs/heads/main~1", false},
		{"question", "refs/heads/what?", false},
		{"star", "refs/heads/*", false},
		{"backslash", "refs/heads/a\\b", false},
		{"control", "refs/heads/a\x01b", false},
		{"too long", "refs/heads/" + strings.Repeat("a", 300), false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidRefName(tc.in), tc.name)
	}
}

func TestValidRepoID(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"simple", "moul/forge", true},
		{"digits", "ns0/repo9", true},
		{"dots and dashes", "moul/gno-contracts.x", true},
		{"underscore", "moul/my_repo", true},
		{"no slash", "forge", false},
		{"two slashes", "a/b/c", false},
		{"empty ns", "/forge", false},
		{"empty name", "moul/", false},
		{"uppercase", "Moul/forge", false},
		{"leading dash", "moul/-forge", false},
		{"trailing dot", "moul/forge.", false},
		{"double dot", "moul/fo..rge", false},
		{"double dash", "moul/fo--rge", false},
		{"space", "moul/my forge", false},
		{"too long", "moul/" + strings.Repeat("a", 40), false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidRepoID(tc.in), tc.name)
	}
}

func TestAddressNamespace(t *testing.T) {
	addr := testutils.TestAddress("alice").String()
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"a real address", addr, true},
		{"wrong prefix", "x1" + addr[2:], false},
		{"too short", addr[:39], false},
		{"too long", addr + "a", false},
		{"bech32 drops b i o 1", "g1" + strings.Repeat("b", 38), false},
		{"uppercase", "G1" + addr[2:], false},
		{"a slug is not an address", "moul", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, AddressNamespace(tc.in), tc.name)
	}

	// An address namespace is a valid repo id, and it cannot collide with a
	// claimed name: 40 characters is past the slug cap.
	uassert.True(t, ValidRepoID(addr+"/forge"))
	uassert.False(t, ValidRepoID(strings.Repeat("a", 40)+"/forge"))
	uassert.False(t, ValidRepoID(addr+"/"+addr), "the name half is always a slug")
}

func TestSplitRepoID(t *testing.T) {
	ns, name, ok := SplitRepoID("moul/forge")
	uassert.True(t, ok)
	uassert.Equal(t, "moul", ns)
	uassert.Equal(t, "forge", name)

	for _, bad := range []string{"", "moul", "/forge", "moul/", "a/b/c"} {
		_, _, ok := SplitRepoID(bad)
		uassert.False(t, ok, bad)
	}
}

func TestValidTextAndLine(t *testing.T) {
	uassert.True(t, ValidText("hello\nworld\ttab", 64))
	uassert.False(t, ValidText("bell\x07", 64))
	uassert.False(t, ValidText("too long", 3))
	uassert.True(t, ValidText("", 3))

	uassert.True(t, ValidLine("a single line", 64))
	uassert.False(t, ValidLine("two\nlines", 64))
	uassert.False(t, ValidLine("a\ttab", 64))
}

func TestValidMirrorAndLabel(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"https://github.com/moul/gno-contracts.git", true},
		{"git@github.com:moul/gno-contracts.git", true},
		{"ipfs://bafybeihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku", true},
		{"rad://z3gqcJUoA1n9HaHKufZs5FCSGazv5", true},
		{"ar://1QKPaf1AmsK_tSSdUgtVDEYGLuQBOKTNr", true},
		{"ftp://example.com/repo.git", false},
		{"not a url", false},
		{"", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidMirror(tc.in), tc.in)
	}

	uassert.True(t, ValidLabel("bug"))
	uassert.False(t, ValidLabel(""))
	uassert.False(t, ValidLabel("a,b"))
	uassert.False(t, ValidLabel(strings.Repeat("x", 33)))
}

func TestParseRoleRoundTrip(t *testing.T) {
	for _, r := range []Role{RoleNone, RoleReader, RoleWriter, RoleMaintainer, RoleAdmin, RoleOwner} {
		got, err := ParseRole(r.String())
		uassert.NoError(t, err, r.String())
		uassert.Equal(t, int(r), int(got), r.String())
	}
	_, err := ParseRole("root")
	uassert.ErrorIs(t, err, ErrInvalidRole)
}
