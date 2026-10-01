package linktree

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A profile holds a bounded number of links of bounded size, and removing one
// keeps the others in order.
func TestLinksAreBounded(cur realm, t *testing.T) {
	who := testutils.TestAddress("bounded")
	testing.SetRealm(testing.NewUserRealm(who))
	uassert.AbortsContains(t, cur, "bio too long", func() { SetBio(cross(cur), strings.Repeat("b", MaxBioLen+1)) })
	for i := 0; i < MaxLinks; i++ {
		AddLink(cross(cur), "l", "https://e.example/"+strings.Repeat("x", i))
	}
	uassert.AbortsContains(t, cur, "at most", func() { AddLink(cross(cur), "l", "https://e.example/") })
	RemoveLink(cross(cur), 0)
	p := profiles.Get(who.String()).(*profile)
	uassert.Equal(t, MaxLinks-1, len(p.Links))
	uassert.Equal(t, "https://e.example/x", p.Links[0].URL)
}
