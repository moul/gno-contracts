package wiki

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/wiki/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	// carol edits only in TestCooldown: the cooldown is keyed by address and
	// by block height, and gno's testing.SkipHeights is relative, so a test
	// that reused an address another test already edited with would see a
	// zero-height delta and trip the cooldown before it meant to.
	carol = testutils.TestAddress("carol")
)

// TestBasePathMatchesTheRealm pins the constant used to build every link
// against the realm's own path. A wrong basePath produces a page whose links
// all 404, and nothing else would catch it.
func TestBasePathMatchesTheRealm(t *testing.T) {
	uassert.True(t, strings.HasSuffix(basePath, "/r/moul/x/wiki/v0"), basePath)
	out := Render("Gno_land")
	uassert.True(t, strings.Contains(out, "("+basePath+":Tendermint2)"), out)
}

func TestRenderRoutes(t *testing.T) {
	cases := []struct {
		path string
		want string
	}{
		{"", "# Wiki"},
		{"Gno_land", "# Gno land"},
		{"gno_land", "# Gno land"},                      // titles normalize
		{"Gno_land/history", "# History of Gno land"},   //
		{"Gno_land/raw", "# Source of Gno land"},        //
		{"Gno_land/rev/1", "revision 1"},                //
		{"Nonexistent_page", "does not exist yet"},      //
		{"Special:AllPages", "# All pages"},             //
		{"Special:allpages", "# All pages"},             // case-insensitive
		{"Special:Categories", "# Categories"},          //
		{"Special:RecentChanges", "# Recent changes"},   //
		{"Special:Stats", "# Wiki stats"},               //
		{"Special:Backlinks?page=Gno", "Pages that link to Gno"},
		{"Special:Nope", "404"},
		{"Gno_land/nope", "404"},
		{"Gno_land/rev/999", "404"},
		{"Category:Chains", "Pages in this category"},
		{"Gno_land/talk", "# Discussion: Gno land"},
	}
	for _, c := range cases {
		out := Render(c.path)
		uassert.True(t, strings.Contains(out, c.want),
			"Render("+c.path+") should contain "+c.want+", got: "+first80(out))
	}
}

func TestRenderIsTotal(t *testing.T) {
	// Render is reached from a URL, so malformed input must produce a page,
	// never an abort that makes the realm unreadable.
	for _, path := range []string{"Gno|land", "Special:Backlinks?page=", "Gno_land/diff?from=x&to=y", "//"} {
		uassert.NotEmpty(t, Render(path), path)
	}
}

func TestEditAndRevert(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	rev := Edit(cross(cur), "Alice page", "First body.\n", "create")
	uassert.True(t, rev > 0)

	testing.SetRealm(testing.NewUserRealm(bob))
	Edit(cross(cur), "Alice page", "Vandalized.\n", "oops")
	uassert.True(t, strings.Contains(Render("Alice_page"), "Vandalized."))

	testing.SetRealm(testing.NewUserRealm(alice))
	Revert(cross(cur), "Alice page", rev, "rv")
	out := Render("Alice_page")
	uassert.True(t, strings.Contains(out, "First body."))
	// The vandalism is still in the history: that is the point of a wiki.
	uassert.True(t, strings.Contains(Render("Alice_page/history"), "oops"))
}

func TestEditRejectsAnEmptyBody(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "empty title", func() {
		Edit(cross(cur), "", "body\n", "")
	})
	uassert.AbortsContains(t, cur, "empty body", func() {
		Edit(cross(cur), "Some page", "", "")
	})
}

func TestBannedAddressCannotEdit(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(steward))
	Ban(cross(cur), bob)

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "banned", func() {
		Edit(cross(cur), "Ban test", "body\n", "")
	})

	testing.SetRealm(testing.NewUserRealm(steward))
	Unban(cross(cur), bob)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.True(t, Edit(cross(cur), "Ban test", "body\n", "") > 0)
}

func TestProtectionLevels(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Protected page", "body\n", "")

	testing.SetRealm(testing.NewUserRealm(steward))
	Protect(cross(cur), "Protected page", "semi")

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "semi-protected", func() {
		Edit(cross(cur), "Protected page", "sneaky\n", "")
	})

	testing.SetRealm(testing.NewUserRealm(steward))
	AddEditor(cross(cur), alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.True(t, Edit(cross(cur), "Protected page", "allowed\n", "") > 0)

	testing.SetRealm(testing.NewUserRealm(steward))
	Protect(cross(cur), "Protected page", "locked")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "caller is not owner", func() {
		Edit(cross(cur), "Protected page", "still sneaky\n", "")
	})
}

func TestStewardOnlyFunctionsRejectOthers(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Steward test", "body\n", "")

	for _, call := range []struct {
		name string
		fn   func()
	}{
		{"Protect", func() { Protect(cross(cur), "Steward test", "locked") }},
		{"Move", func() { Move(cross(cur), "Steward test", "Elsewhere", "") }},
		{"Blank", func() { Blank(cross(cur), "Steward test", "") }},
		{"Purge", func() { Purge(cross(cur), "Steward test") }},
		{"Ban", func() { Ban(cross(cur), bob) }},
		{"SetCooldown", func() { SetCooldown(cross(cur), 5) }},
	} {
		testing.SetRealm(testing.NewUserRealm(alice))
		uassert.AbortsContains(t, cur, "caller is not owner", call.fn, call.name)
	}
}

func TestCooldown(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(steward))
	SetCooldown(cross(cur), 5)

	testing.SetRealm(testing.NewUserRealm(carol))
	Edit(cross(cur), "Cooldown page", "one\n", "")
	uassert.AbortsContains(t, cur, "cooldown", func() {
		Edit(cross(cur), "Cooldown page", "two\n", "")
	})

	testing.SkipHeights(6)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.True(t, Edit(cross(cur), "Cooldown page", "two\n", "") > 0)

	testing.SetRealm(testing.NewUserRealm(steward))
	SetCooldown(cross(cur), 0)
}

func TestBlankAndPurgeReleaseBytes(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Purge page", "a body worth some bytes\n", "")

	testing.SetRealm(testing.NewUserRealm(steward))
	Blank(cross(cur), "Purge page", "policy")
	uassert.True(t, strings.Contains(Render("Purge_page"), "was blanked"))

	testing.SetRealm(testing.NewUserRealm(steward))
	released := Purge(cross(cur), "Purge page")
	uassert.True(t, released > 0, "purging a page with a retained body must release bytes")
	uassert.True(t, strings.Contains(Render("Purge_page/history"), "body evicted"))
}

func TestMoveLeavesARedirect(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Before move", "the body\n", "")

	testing.SetRealm(testing.NewUserRealm(steward))
	Move(cross(cur), "Before move", "After move", "rename")

	uassert.True(t, strings.Contains(Render("After_move"), "the body"))
	// Reading the old title follows the redirect; its history does not.
	uassert.True(t, strings.Contains(Render("Before_move"), "the body"))
	uassert.True(t, strings.Contains(Render("Before_move/raw"), "#REDIRECT"))
}

// TestSeedIsLinkedTogether checks the deployed starting state renders as a
// connected wiki rather than four orphans.
func TestSeedIsLinkedTogether(t *testing.T) {
	uassert.True(t, strings.Contains(Render("Gno_land"), "("+basePath+":Gno)"))
	uassert.True(t, strings.Contains(Render("Special:Backlinks?page=Gno_land"), "[Gno]"))
	uassert.True(t, strings.Contains(Render("Category:Chains"), "[Gno land]"))
}

// TestParseTitleIsTheSameOneTheLibraryUses guards against the realm and the
// library disagreeing about what a title is, which would make a page
// creatable but unreachable.
func TestParseTitleIsTheSameOneTheLibraryUses(t *testing.T) {
	tt := wiki.MustParseTitle("Gno land")
	uassert.Equal(t, "Gno_land", tt.Slug())
	uassert.True(t, strings.Contains(Render(tt.Slug()), "# Gno land"))
}

func first80(s string) string {
	if len(s) > 80 {
		return s[:80]
	}
	return s
}

func TestCommentOnALockedPage(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Locked talk", "body\n", "")

	testing.SetRealm(testing.NewUserRealm(steward))
	Protect(cross(cur), "Locked talk", "locked")

	// Locking an article is how a steward stops an edit war; the discussion
	// is where that war is supposed to move, so it stays open.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "caller is not owner", func() {
		Edit(cross(cur), "Locked talk", "sneaky\n", "")
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Comment(cross(cur), "Locked talk", "I disagree, and here is why.\n", 0)
	uassert.True(t, id > 0)
	uassert.True(t, strings.Contains(Render("Locked_talk/talk"), "I disagree"))
}

func TestCommentRepliesAndModeration(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Talk target", "body\n", "")
	root := Comment(cross(cur), "Talk target", "First.\n", 0)

	testing.SetRealm(testing.NewUserRealm(bob))
	Comment(cross(cur), "Talk target", "Replying.\n", root)

	out := Render("Talk_target/talk")
	uassert.True(t, strings.Contains(out, "First."))
	uassert.True(t, strings.Contains(out, "Replying."))

	testing.SetRealm(testing.NewUserRealm(steward))
	released := HideComment(cross(cur), "Talk target", root)
	uassert.True(t, released > 0, "hiding a message releases its bytes")
	out = Render("Talk_target/talk")
	uassert.True(t, strings.Contains(out, "removed by a steward"))
	uassert.False(t, strings.Contains(out, "First."))
}

func TestBannedAddressCannotComment(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Ban talk", "body\n", "")

	testing.SetRealm(testing.NewUserRealm(steward))
	Ban(cross(cur), bob)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "banned", func() {
		Comment(cross(cur), "Ban talk", "spam\n", 0)
	})
	testing.SetRealm(testing.NewUserRealm(steward))
	Unban(cross(cur), bob)
}

func TestHideCommentIsStewardOnly(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Edit(cross(cur), "Mod talk", "body\n", "")
	id := Comment(cross(cur), "Mod talk", "hello\n", 0)

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "caller is not owner", func() {
		HideComment(cross(cur), "Mod talk", id)
	})
}
