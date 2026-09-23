package blog

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var stranger = testutils.TestAddress("stranger")

// Everything here goes through the real crossing functions rather than seed(),
// because the author check, the re-key on a date change and the panic messages
// only exist on that path and are exactly what a typo would break on a
// permanent path.

func TestSetPublishesAndRenders(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(author))
	Set(cross(cur), "hello", "Hello", "2026-09-23", "Gno, tooling", "The body.")

	uassert.Equal(t, 1, Count(), "one post")
	uassert.Equal(t, "The body.", Get("hello"), "the body round-trips")
	uassert.True(t, strings.Contains(Render("hello"), "# Hello"), "it renders")
	// Tags are normalized on write, not on read, so the hash the tool computed
	// locally is the hash the manifest reports.
	uassert.True(t, strings.Contains(Manifest(), "\t"+hashOf(record("Hello", "2026-09-23", "gno,tooling", "The body."))),
		"the manifest hashes the normalized record")
}

func TestOnlyTheAuthorMayWrite(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(stranger))
	// AbortsWithMessage, not PanicsWithMessage: a panic that crosses a realm
	// boundary becomes an abort, which recover() cannot catch, so asserting it
	// as a panic does not fail the assertion, it kills the whole test binary.
	uassert.AbortsWithMessage(t, cur, "restricted to the author", func() {
		Set(cross(cur), "nope", "Nope", "2026-09-23", "", "Body.")
	})
	uassert.AbortsWithMessage(t, cur, "restricted to the author", func() {
		SetIntro(cross(cur), "mine now")
	})
	uassert.Equal(t, 0, Count(), "nothing was written")
}

// The one case a second tree can get wrong: re-dating a post must MOVE its
// index entry, not leave a ghost at the old key rendering the post twice.
func TestSetRedatingMovesTheIndexEntry(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(author))
	Set(cross(cur), "a", "A", "2026-01-01", "", "Body A.")
	Set(cross(cur), "a", "A", "2026-12-31", "", "Body A.")

	uassert.Equal(t, 1, Count(), "still one post")
	out := Render("")
	uassert.Equal(t, 1, strings.Count(out, "](/r/moul/blog:a)"), "listed exactly once")
	uassert.True(t, strings.Contains(out, "2026-12-31"), "under the new date")
	uassert.False(t, strings.Contains(out, "2026-01-01"), "and not the old one")
}

func TestSetRejectsWhatTheToolRejects(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(author))
	uassert.AbortsContains(t, cur, "invalid slug", func() {
		Set(cross(cur), "Caps", "T", "2026-09-23", "", "Body.")
	})
	uassert.AbortsContains(t, cur, "reserved slug", func() {
		Set(cross(cur), introSlug, "T", "2026-09-23", "", "Body.")
	})
	uassert.AbortsContains(t, cur, "invalid date", func() {
		Set(cross(cur), "ok", "T", "23-09-2026", "", "Body.")
	})
	uassert.AbortsContains(t, cur, "a post needs a title", func() {
		Set(cross(cur), "ok", "  ", "2026-09-23", "", "Body.")
	})
	uassert.Equal(t, 0, Count(), "none of them was written")
}

func TestAppendAndDelete(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(author))
	Set(cross(cur), "long", "Long", "2026-09-23", "", "First half.")
	Append(cross(cur), "long", " Second half.")
	uassert.Equal(t, "First half. Second half.", Get("long"), "append concatenates, it does not replace")

	uassert.AbortsWithMessage(t, cur, `no such post: "ghost"`, func() {
		Append(cross(cur), "ghost", "x")
	})

	Delete(cross(cur), "long")
	uassert.Equal(t, 0, Count(), "deleted")
	uassert.True(t, strings.Contains(Render(""), "Nothing published yet."), "and gone from the index")
	uassert.AbortsWithMessage(t, cur, `no such post: "long"`, func() {
		Delete(cross(cur), "long")
	})
}

func TestRevisionMovesOnEveryWrite(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(author))
	uassert.Equal(t, 0, Revision(), "a fresh realm is at zero")
	Set(cross(cur), "a", "A", "2026-09-23", "", "Body.")
	Append(cross(cur), "a", "!")
	SetIntro(cross(cur), "# Header")
	Delete(cross(cur), "a")
	uassert.Equal(t, 4, Revision(), "one per mutation, so a client can tell nothing moved")
}
