package gnopm

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestValidCommit(t *testing.T) {
	sha1 := strings.Repeat("a", 40)
	sha256 := strings.Repeat("0", 64)
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"sha1", sha1, true},
		{"sha256", sha256, true},
		{"mixed hex", "0123456789abcdef0123456789abcdef01234567", true},
		{"empty", "", false},
		{"too short", strings.Repeat("a", 39), false},
		{"between the two lengths", strings.Repeat("a", 41), false},
		{"uppercase", strings.Repeat("A", 40), false},
		{"non hex", strings.Repeat("g", 40), false},
		{"abbreviated", "0123456", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidCommit(tc.in), tc.name)
	}
}

func TestValidRepo(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"github", "https://github.com/gnolang/gno", true},
		{"no path", "https://example.com", true},
		{"trailing slash", "https://example.com/x/", true},
		{"port is not a host character here", "https://example.com:8443/x", false},

		{"empty", "", false},
		{"http", "http://github.com/gnolang/gno", false},
		{"git scheme", "git://github.com/gnolang/gno", false},
		{"ssh scheme", "ssh://git@github.com/gnolang/gno", false},
		{"javascript", "javascript:alert(1)", false},
		{"data url", "data:text/html,<script>", false},
		{"scheme relative", "//github.com/gnolang/gno", false},
		{"no host", "https:///gnolang/gno", false},
		{"bare host with no dot", "https://localhost/x", false},
		{"userinfo disguise", "https://github.com@evil.example/gnolang/gno", false},
		{"parent traversal", "https://example.com/../x", false},
		{"space", "https://example.com/a b", false},
		{"markdown link break-out", "https://example.com/a)[x](y", false},
		{"newline", "https://example.com/a\nb", false},
		{"bidi override", "https://example.com/a‮b", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidRepo(tc.in), tc.name)
	}
}

func TestValidDir(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"repo root", "", true},
		{"one element", "examples", true},
		{"nested", "examples/gno.land/p/nt/avl", true},
		{"dots in a name", "p/moul.io/x", true},

		{"absolute", "/examples", false},
		{"trailing slash", "examples/", false},
		{"empty element", "a//b", false},
		{"dot element", "a/./b", false},
		{"parent traversal", "a/../b", false},
		{"backslash", "a\\b", false},
		{"space", "a b", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidDir(tc.in), tc.name)
	}
}

func TestValidRef(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"absent is legal", "", true},
		{"branch", "refs/heads/main", true},
		{"tag", "refs/tags/v1.2.0", true},

		{"unqualified branch", "main", false},
		{"double dot", "refs/heads/a..b", false},
		{"reflog syntax", "refs/heads/a@{1}", false},
		{"trailing slash", "refs/heads/", false},
		{"lock suffix", "refs/heads/main.lock", false},
		{"leading dot", "refs/heads/.hidden", false},
		{"caret", "refs/heads/a^b", false},
		{"space", "refs/heads/a b", false},

		// Narrower than git on purpose: these are legal ref names that would
		// break out of a markdown table cell or an inline-code span, and every
		// other field in this package is an allowlist so that no consumer has
		// to escape anything.
		{"pipe breaks a table cell", "refs/heads/a|b", false},
		{"backtick breaks a code span", "refs/heads/a`b", false},
		{"brackets open a link", "refs/heads/a[b]c", false},
		{"parens close a link", "refs/heads/a(b)c", false},
		{"hash opens a heading", "refs/heads/a#b", false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidRef(tc.in), tc.name)
	}
}
