package pairreg

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Loaded on its own, the registry has no instances: the index says so rather
// than rendering an empty table.
func TestRenderEmpty(t *testing.T) {
	out := Render("")
	uassert.True(t, strings.Contains(out, "# AMM pairs"))
	uassert.True(t, strings.Contains(out, "No instance yet"))
	uassert.Equal(t, 0, Size())
	uassert.Equal(t, 0, Couples())
}

func TestRenderUnknownInstance(t *testing.T) {
	out := Render("gno.land/r/nope/v0")
	uassert.True(t, strings.Contains(out, "# 404"))
	uassert.True(t, Get("gno.land/r/nope/v0") == nil)
	uassert.Equal(t, 0, len(InstancesFor("a~b")))
}

// A gnoweb link is the package path minus the chain domain.
func TestWebPath(t *testing.T) {
	uassert.Equal(t, "/r/moul/x/pairs/aaabbb/v0", webPath("gno.land/r/moul/x/pairs/aaabbb/v0"))
	uassert.Equal(t, "r/moul/x/pairs/aaabbb/v0", shortPath("gno.land/r/moul/x/pairs/aaabbb/v0"))
}
