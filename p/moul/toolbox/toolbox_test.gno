package toolbox

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestValidSlug(t *testing.T) {
	cases := []struct {
		name string
		slug string
		want bool
	}{
		{"plain", "usernames", true},
		{"dashed", "gov-dao", true},
		{"digits", "base64", true},
		{"all dashes", "--", true},
		{"empty", "", false},
		{"uppercase", "Usernames", false},
		{"underscore", "gov_dao", false},
		{"slash", "a/b", false},
		{"space", "gov dao", false},
		{"dot", "v0.1", false},
		{"percent", "a%2Fb", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, ValidSlug(tc.slug))
		})
	}
}

func TestBasePath(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"versioned realm", "gno.land/r/moul/toolbox/v0", "gno.land/r/moul/toolbox"},
		{"two digit version", "gno.land/r/moul/toolbox/v12", "gno.land/r/moul/toolbox"},
		{"nested tool", "gno.land/r/moul/toolbox/usernames/v0", "gno.land/r/moul/toolbox/usernames"},
		{"unversioned", "gno.land/r/moul/home", "gno.land/r/moul/home"},
		{"idempotent", "gno.land/r/moul/toolbox", "gno.land/r/moul/toolbox"},
		{"v with no digit", "gno.land/r/moul/v", "gno.land/r/moul/v"},
		{"v with a letter", "gno.land/r/moul/v0a", "gno.land/r/moul/v0a"},
		{"no slash", "toolbox", "toolbox"},
		{"empty", "", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, BasePath(tc.in))
		})
	}
}

func TestIsUnderAndSlugOf(t *testing.T) {
	const hub = "gno.land/r/moul/toolbox/v0"
	cases := []struct {
		name      string
		path      string
		wantUnder bool
		wantSlug  string
	}{
		{"direct tool", "gno.land/r/moul/toolbox/usernames/v0", true, "usernames"},
		{"unversioned tool", "gno.land/r/moul/toolbox/usernames", true, "usernames"},
		{"tool at another version", "gno.land/r/moul/toolbox/usernames/v3", true, "usernames"},
		{"nested deeper", "gno.land/r/moul/toolbox/a/b/v0", true, ""},
		{"the hub itself", hub, false, ""},
		{"hub unversioned", "gno.land/r/moul/toolbox", false, ""},
		{"prefix sibling", "gno.land/r/moul/toolboxtwo/v0", false, ""},
		{"unrelated realm", "gno.land/r/moul/home", false, ""},
		{"empty", "", false, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.wantUnder, IsUnder(hub, tc.path))
			uassert.Equal(t, tc.wantSlug, SlugOf(hub, tc.path))
		})
	}
}

// TestIsUnderEmptyHub pins the one input that would otherwise make every path
// a tool: an empty hub path has no family to be below.
func TestIsUnderEmptyHub(t *testing.T) {
	uassert.False(t, IsUnder("", "gno.land/r/moul/toolbox/usernames/v0"))
	uassert.Equal(t, "", SlugOf("", "gno.land/r/moul/toolbox/usernames/v0"))
}

func TestToolValidate(t *testing.T) {
	ok := Tool{Slug: "usernames", Path: "gno.land/r/moul/toolbox/usernames/v0", Title: "Usernames"}
	cases := []struct {
		name string
		tool Tool
		want error
	}{
		{"complete", ok, nil},
		{"no slug", Tool{Path: ok.Path, Title: ok.Title}, ErrEmptySlug},
		{"bad slug", Tool{Slug: "User Names", Path: ok.Path, Title: ok.Title}, ErrBadSlug},
		{"no path", Tool{Slug: ok.Slug, Title: ok.Title}, ErrEmptyPath},
		{"no title", Tool{Slug: ok.Slug, Path: ok.Path}, ErrEmptyTitle},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.tool.Validate()
			if tc.want == nil {
				uassert.NoError(t, got)
				return
			}
			uassert.ErrorIs(t, got, tc.want)
		})
	}
}

func TestToolURL(t *testing.T) {
	cases := []struct {
		name string
		path string
		want string
	}{
		{"chain path", "gno.land/r/moul/toolbox/usernames/v0", "/r/moul/toolbox/usernames/v0"},
		{"other domain", "example.com/r/x/v0", "/r/x/v0"},
		{"already a url", "/r/moul/toolbox/v0", "/r/moul/toolbox/v0"},
		{"no slash", "toolbox", "toolbox"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, Tool{Path: tc.path}.URL())
		})
	}
}

func TestToolHasTag(t *testing.T) {
	tool := Tool{Tags: []string{"identity", "read"}}
	uassert.True(t, tool.HasTag("identity"))
	uassert.True(t, tool.HasTag("read"))
	uassert.False(t, tool.HasTag("Identity"))
	uassert.False(t, tool.HasTag(""))
	uassert.False(t, Tool{}.HasTag("identity"))
}
