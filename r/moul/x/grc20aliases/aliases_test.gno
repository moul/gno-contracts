package grc20aliases

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/moul/authz/v1"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/moul/x/pairs/aaa/v0"
	"gno.land/r/moul/x/pairs/bbb/v0"
)

var editor = testutils.TestAddress("alias-curator")

func resetRegistry() {
	aliases = make(map[string]string)
	curator = authz.NewWithMembers(editor)
	pending = ""
}

func TestCanonicalKeyDoesNotNeedAnAlias(t *testing.T) {
	resetRegistry()
	uassert.Equal(t, "", Resolve("test-alpha"))
	uassert.Equal(t, "", Resolve("gno.land/r/moul/x/pairs/aaa/v0.UNKNOWN"))
	uassert.Equal(t, aaa.Key, Resolve(aaa.Key))
	uassert.Equal(t, bbb.Key, Resolve(bbb.Key))
}

func TestAliasLifecycle(cur realm, t *testing.T) {
	resetRegistry()
	testing.SetRealm(testing.NewUserRealm(editor))
	SetAlias(cross(cur), "test-alpha", "", aaa.Key)
	uassert.Equal(t, aaa.Key, Resolve("test-alpha"))
	uassert.AbortsContains(t, cur, "alias changed", func() {
		SetAlias(cross(cur), "test-alpha", "", bbb.Key)
	})
	SetAlias(cross(cur), "test-alpha", aaa.Key, bbb.Key)
	uassert.Equal(t, bbb.Key, Resolve("test-alpha"))
	uassert.AbortsContains(t, cur, "alias changed", func() {
		RemoveAlias(cross(cur), "test-alpha", aaa.Key)
	})
	RemoveAlias(cross(cur), "test-alpha", bbb.Key)
	uassert.Equal(t, "", Resolve("test-alpha"))
	uassert.Equal(t, bbb.Key, Resolve(bbb.Key))
	SetAlias(cross(cur), "test-alpha", "", aaa.Key)
	uassert.Equal(t, aaa.Key, Resolve("test-alpha"))
}

func TestInvalidAliasAndUnknownKeyDoNotCreateEntries(cur realm, t *testing.T) {
	resetRegistry()
	testing.SetRealm(testing.NewUserRealm(editor))
	for _, name := range []string{"", "test Alpha", "Alpha", "-alpha", "alpha-", strings.Repeat("a", 33), aaa.Key} {
		uassert.AbortsContains(t, cur, "invalid alias", func() {
			SetAlias(cross(cur), name, "", aaa.Key)
		})
	}
	uassert.AbortsContains(t, cur, "unknown registry key", func() {
		SetAlias(cross(cur), "test-alpha", "", "unknown")
	})
	uassert.Equal(t, 0, len(aliases))
}

func TestDirectoryRemainsBounded(cur realm, t *testing.T) {
	resetRegistry()
	testing.SetRealm(testing.NewUserRealm(editor))
	for i := 0; i < maxAliases; i++ {
		aliases["token-"+strconv.Itoa(i)] = aaa.Key
	}
	uassert.AbortsContains(t, cur, "alias limit reached", func() {
		SetAlias(cross(cur), "extra", "", bbb.Key)
	})
	SetAlias(cross(cur), "token-0", aaa.Key, bbb.Key)
	RemoveAlias(cross(cur), "token-0", bbb.Key)
	SetAlias(cross(cur), "extra", "", bbb.Key)
	uassert.Equal(t, maxAliases, len(aliases))
}

func TestCuratorHandoffToDAORealm(cur realm, t *testing.T) {
	resetRegistry()
	dao := testing.NewCodeRealm("gno.land/r/test/aliasdao")
	testing.SetRealm(dao)
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		SetAlias(cross(cur), "test-alpha", "", aaa.Key)
	})
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		ProposeCurator(cross(cur), dao.Address())
	})

	testing.SetRealm(testing.NewUserRealm(editor))
	ProposeCurator(cross(cur), dao.Address())
	ProposeCurator(cross(cur), "")
	testing.SetRealm(dao)
	uassert.AbortsContains(t, cur, "not the nominated curator", func() {
		AcceptCurator(cross(cur))
	})
	testing.SetRealm(testing.NewUserRealm(editor))
	ProposeCurator(cross(cur), dao.Address())
	uassert.AbortsContains(t, cur, "not the nominated curator", func() {
		AcceptCurator(cross(cur))
	})
	SetAlias(cross(cur), "test-alpha", "", aaa.Key)

	testing.SetRealm(dao)
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		RemoveAlias(cross(cur), "test-alpha", aaa.Key)
	})
	AcceptCurator(cross(cur))
	SetAlias(cross(cur), "test-alpha", aaa.Key, bbb.Key)

	testing.SetRealm(testing.NewUserRealm(editor))
	uassert.Equal(t, bbb.Key, Resolve("test-alpha"))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		RemoveAlias(cross(cur), "test-alpha", bbb.Key)
	})
}

func TestRender(cur realm, t *testing.T) {
	resetRegistry()
	uassert.True(t, strings.Contains(Render(""), "No aliases have been curated yet."))
	testing.SetRealm(testing.NewUserRealm(editor))
	SetAlias(cross(cur), "zeta", "", bbb.Key)
	SetAlias(cross(cur), "alpha", "", aaa.Key)
	home := Render("")
	alpha := strings.Index(home, "| alpha | "+ui.Cell(aaa.Key)+" |")
	zeta := strings.Index(home, "| zeta | "+ui.Cell(bbb.Key)+" |")
	uassert.True(t, alpha >= 0 && zeta > alpha, home)
	uassert.True(t, strings.Contains(Render("alpha"), "# Test Alpha"))
	uassert.Equal(t, Render(aaa.Key), Render("alpha"))
	uassert.Equal(t, "Unknown token alias or registry key.", Render("[bad](https://example.org)"))
}
