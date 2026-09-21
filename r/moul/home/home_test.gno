package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var stranger = testutils.TestAddress("mallory")

// reset clears realm state. Realm globals live for the whole test binary, so
// every test that reads Render or Manifest starts from a known tree.
func reset() {
	slots = avl.NewTree()
	rev = 0
}

// seed writes a slot without going through the admin check, for tests (and the
// Example) that only care about the rendering side.
func seed(slug, body string) {
	rev++
	slots.Set(slug, &slot{body: body, rev: rev, updated: 0})
}

func TestSetGetDelete(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	Set(cross(cur), "bio", "Building on gno.")
	uassert.Equal(t, "Building on gno.", Get("bio"))
	uassert.Equal(t, 1, Revision())

	// Set is idempotent in shape: a second write replaces, never appends.
	Set(cross(cur), "bio", "Still building.")
	uassert.Equal(t, "Still building.", Get("bio"))
	uassert.Equal(t, 2, Revision())

	Delete(cross(cur), "bio")
	uassert.Equal(t, "", Get("bio"), "a deleted slot reads as empty")
	uassert.Equal(t, 3, Revision())

	uassert.AbortsWithMessage(t, cur, "no such slot: bio", func() {
		Delete(cross(cur), "bio")
	})
}

func TestAppendChunks(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	// The escape hatch for a body too large for one transaction.
	Set(cross(cur), "long", "part one. ")
	Append(cross(cur), "long", "part two.")
	uassert.Equal(t, "part one. part two.", Get("long"))

	// Append creates the slot when it is absent.
	Append(cross(cur), "fresh", "hello")
	uassert.Equal(t, "hello", Get("fresh"))
}

func TestWritesAreAdminOnly(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(stranger))

	uassert.AbortsWithMessage(t, cur, "restricted to admin", func() {
		Set(cross(cur), "bio", "pwned")
	})
	uassert.AbortsWithMessage(t, cur, "restricted to admin", func() {
		Append(cross(cur), "bio", "pwned")
	})
	uassert.AbortsWithMessage(t, cur, "restricted to admin", func() {
		Delete(cross(cur), "bio")
	})
	uassert.Equal(t, "", Get("bio"))
}

func TestSlugRules(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	uassert.True(t, validSlug("bio"))
	uassert.True(t, validSlug("now.2026-09"))
	uassert.True(t, validSlug("latest_packages"))
	uassert.False(t, validSlug(""), "empty")
	uassert.False(t, validSlug("Bio"), "uppercase: a slot must have one name")
	uassert.False(t, validSlug("a b"), "space")
	uassert.False(t, validSlug("a:b"), "a colon would break out of the :slug: placeholder")
	uassert.False(t, validSlug(strings.Repeat("a", maxSlugLen+1)), "too long")

	uassert.AbortsContains(t, cur, "invalid slug", func() {
		Set(cross(cur), "Bad Slug", "x")
	})

	// A reserved name would shadow a value computed from chain state.
	for _, name := range reservedSlugs {
		uassert.AbortsContains(t, cur, "reserved slug", func() {
			Set(cross(cur), name, "x")
		})
	}

	// "layout" is special but NOT reserved: it is a real, writable slot.
	Set(cross(cur), layoutSlug, "# hi")
	uassert.Equal(t, "# hi", Get(layoutSlug))
}

func TestManifestIsTheDiffSurface(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	Set(cross(cur), "bio", "hello")
	Set(cross(cur), "alpha", "")

	// Sorted by slug (avl order), one line each, four tab-separated fields.
	lines := strings.Split(strings.TrimSuffix(Manifest(), "\n"), "\n")
	uassert.Equal(t, 2, len(lines))

	alpha := strings.Split(lines[0], "\t")
	uassert.Equal(t, 4, len(alpha))
	uassert.Equal(t, "alpha", alpha[0])
	uassert.Equal(t, "0", alpha[2], "byte length of an empty body")
	// sha256(""), pinning that the hash is over the body, not over a wrapper.
	uassert.Equal(t, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", alpha[3])

	bio := strings.Split(lines[1], "\t")
	uassert.Equal(t, "bio", bio[0])
	uassert.Equal(t, "5", bio[2])
	// sha256("hello")
	uassert.Equal(t, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", bio[3])
}

func TestRenderFillsTheLayoutSlot(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	Set(cross(cur), layoutSlug, "# :owner:\n\n:bio:\n\n:missing:\n")
	Set(cross(cur), "bio", "Building on gno.")

	out := Render("")
	uassert.True(t, strings.Contains(out, "# "+admin.String()),
		"a computed placeholder is filled from chain state")
	uassert.True(t, strings.Contains(out, "Building on gno."),
		"a slot placeholder is filled from the tree")
	uassert.True(t, strings.Contains(out, ":missing:"),
		"an unmatched placeholder survives verbatim, so a gap is visible")
}

func TestRenderDoesNotRecurse(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	// A slot body that looks like a placeholder must not expand: substitution
	// is one pass, which is what makes cycles impossible.
	Set(cross(cur), layoutSlug, ":a:")
	Set(cross(cur), "a", ":b:")
	Set(cross(cur), "b", "should not appear")

	uassert.Equal(t, ":b:", Render(""))
}

func TestRenderUnsetLayoutFallsBack(t *testing.T) {
	reset()
	out := Render("")
	uassert.True(t, strings.Contains(out, "No layout slot yet"))
	uassert.False(t, strings.Contains(out, ":slots:"),
		"the default layout must not leave its own placeholders unresolved")
	uassert.False(t, strings.Contains(out, ":rev:"))
	uassert.False(t, strings.Contains(out, ":height:"))
	uassert.False(t, strings.Contains(out, ":chainid:"))
}

func TestRenderSubPaths(t *testing.T) {
	reset()
	seed("bio", "Building on gno.")

	idx := Render("slots")
	uassert.True(t, strings.Contains(idx, "| [bio](/r/moul/home:slots/bio) |"))

	raw := Render("slots/bio")
	uassert.True(t, strings.Contains(raw, "Building on gno."))
	uassert.True(t, strings.Contains(raw, "16 bytes"))

	uassert.True(t, strings.Contains(Render("slots/nope"), "No slot named"))
	uassert.True(t, strings.Contains(Render("whatever"), "No such path"))
}

func TestRenderEmptyIndex(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render("slots"), "_no slots yet_"))
}
