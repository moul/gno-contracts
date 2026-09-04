package nestedpkg

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestNsFromPath(t *testing.T) {
	cases := []struct {
		path string
		want string
	}{
		{"gno.land/r/moul/home", "moul"},
		{"gno.land/p/moul/svg/v2", "moul"},
		{"gno.land/r/demo/boards", "demo"},
		{"gno.land/r/moul", "moul"},
		// Fewer than three segments has no namespace slot.
		{"gno.land/r", ""},
		{"gno.land", ""},
		{"", ""},
		// The helper is domain-agnostic: it just takes the third segment.
		{"example.com/r/alice/thing", "alice"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, nsFromPath(c.path), "nsFromPath("+c.path+")")
	}
}

// What these tests can and cannot reach, because it is not obvious:
//
//   - testing.SetRealm sets the realm the helpers read as **current**
//     (rlm.PkgPath()); this test package is what they see as **previous**
//     (rlm.Previous().PkgPath()).
//   - SetRealm's argument must be an `r/` path. PkgPath() panics with
//     "should only be called for Realms" on a `p/` path.
//
// This package is `p/moul/nestedpkg/v1`, so previous is always a `p/` path
// while current is always an `r/` path. A `p/` path can therefore never be a
// prefix of the current one or vice versa, which makes the *matching* branches
// of IsCallerSubPath/IsCallerParentPath unreachable from here — exercising
// those needs a realm-hosted caller (an `r/` test package). The non-matching
// branches and the whole namespace comparison are covered below.
const selfNS = "moul"

func TestIsCallerSubPathRejectsUnrelated(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/other/thing"))
	uassert.False(t, IsCallerSubPath(0, cur), "an unrelated realm is not an ancestor of the caller")
}

func TestIsCallerParentPathRejectsUnrelated(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/other/thing"))
	uassert.False(t, IsCallerParentPath(0, cur), "an unrelated realm is not a descendant of the caller")
}

func TestIsSameNamespace(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/" + selfNS + "/anything"))
	uassert.True(t, IsSameNamespace(0, cur), "same namespace across p/ and r/")

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someoneelse/thing"))
	uassert.False(t, IsSameNamespace(0, cur), "different namespace")
}

func TestAssertCallerIsSubPathPanics(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/other/thing"))
	uassert.PanicsWithMessage(t, cur,
		"call restricted to nested packages. current realm is gno.land/r/other/thing/, previous realm is gno.land/p/moul/nestedpkg/v1/",
		func() { AssertCallerIsSubPath(0, cur) })
}

func TestAssertCallerIsParentPathPanics(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/other/thing"))
	uassert.PanicsWithMessage(t, cur,
		"call restricted to parent packages. current realm is gno.land/r/other/thing/, previous realm is gno.land/p/moul/nestedpkg/v1/",
		func() { AssertCallerIsParentPath(0, cur) })
}

func TestAssertIsSameNamespaceAllowsAndPanics(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/" + selfNS + "/anything"))
	AssertIsSameNamespace(0, cur) // same namespace: must not panic

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/someoneelse/thing"))
	uassert.PanicsWithMessage(t, cur,
		"call restricted to packages from the same namespace. current realm is someoneelse/, previous realm is "+selfNS+"/",
		func() { AssertIsSameNamespace(0, cur) })
}
