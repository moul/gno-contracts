// Package home is the realm behind https://gno.land/u/moul.
//
// gnoweb builds a user profile page by calling Render("") on the realm at the
// exact path /r/<username>/home (gno.land/pkg/gnoweb/handler_http.go,
// GetUserView) and embedding the result as the profile body. There is no
// version resolution in that lookup, which is why this realm (alone in this
// repo) carries no /vN suffix: the bare path IS the interface with gnoweb,
// and gno.land/r/moul/home/v0 would never be found.
//
// # Slots
//
// The page is not hard-coded. It is assembled from SLOTS: named markdown
// fragments in an avl tree, each written by its own Set call, so updating one
// paragraph is one small transaction instead of a redeploy.
//
// The layout is itself a slot ("layout"), so the shape of the page (headings,
// order, what appears at all) changes without touching the code.
// p/moul/dynreplacer fills every :slug: placeholder found in the layout, lazily:
// a slot whose placeholder is absent from the layout costs nothing to render.
//
// Substitution is SINGLE-PASS and non-recursive. A placeholder inside a slot
// body is left alone, so no slot can expand into another and no cycle exists.
// Two registered placeholders can never be prefixes of one another either
// (every one is :slug: and a slug may not contain ':'), so the result does not
// depend on registration order.
//
// A placeholder with no matching slot survives into the output verbatim. That
// is deliberate: a missing section should be visible, not silently blank.
//
// # Versioning
//
// gnomod.toml declares private = true, which lets the creator re-add the
// package at this path. That redeploy re-runs init() and RESETS everything
// here, so the markdown under content/ is the source of truth and
// tools/gnohome pushes the slots back afterwards. The intended path is that this
// never happens: slots cover content, and the layout slot covers presentation.
package home

import (
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// admin is the only address allowed to write. Deliberately a constant and not
// transferable ownership: this realm is one person's profile page, and the
// same address is the only one the chain lets redeploy it.
const admin = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")

// layoutSlug names the slot used as the page template.
const layoutSlug = "layout"

// maxSlugLen bounds a slug so an index row stays readable and a key stays cheap.
const maxSlugLen = 64

var (
	slots = avl.NewTree() // slug -> *slot
	rev   int             // total number of writes, bumped by every mutation
)

type slot struct {
	body    string
	rev     int   // rev at the time of the last write to this slot
	updated int64 // block height of the last write
}

// reservedSlugs are placeholder names computed at render time from chain state.
// A slot may not take one, because it would shadow the computed value and make
// the page depend on callback registration order.
var reservedSlugs = []string{"chainid", "height", "owner", "realm", "rev", "slots"}

func assertAdmin(cur realm) {
	if cur.Previous().Address() != admin {
		panic("restricted to admin")
	}
}

// validSlug reports whether slug is a legal slot name: 1..maxSlugLen bytes of
// [a-z0-9._-]. The character set excludes ':' so a slug can never break out of
// its own :slug: placeholder, and excludes uppercase so a slot has one name.
func validSlug(slug string) bool {
	if len(slug) == 0 || len(slug) > maxSlugLen {
		return false
	}
	for i := 0; i < len(slug); i++ {
		c := slug[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case c == '-', c == '_', c == '.':
		default:
			return false
		}
	}
	return true
}

func assertWritableSlug(slug string) {
	if !validSlug(slug) {
		panic("invalid slug: want 1-" + strconv.Itoa(maxSlugLen) + " bytes of [a-z0-9._-], got " + strconv.Quote(slug))
	}
	for _, r := range reservedSlugs {
		if slug == r {
			panic("reserved slug: " + slug + " is computed at render time")
		}
	}
}

// Set creates or replaces the slot named slug. This is the ordinary update: one
// slot, one transaction. Passing the empty body keeps the slot but empties it;
// use Delete to remove it.
func Set(cur realm, slug, body string) {
	assertAdmin(cur)
	assertWritableSlug(slug)
	rev++
	slots.Set(slug, &slot{body: body, rev: rev, updated: chainHeight()})
}

// Append adds to the end of a slot, creating it when absent. It exists for
// content too large to fit in one transaction: Set the first chunk, Append the
// rest. Ordinary updates should use Set, which is idempotent.
func Append(cur realm, slug, body string) {
	assertAdmin(cur)
	assertWritableSlug(slug)
	rev++
	prev := ""
	if v := slots.Get(slug); v != nil {
		prev = v.(*slot).body
	}
	slots.Set(slug, &slot{body: prev + body, rev: rev, updated: chainHeight()})
}

// Delete removes a slot. Deleting the layout slot restores the built-in
// default layout.
func Delete(cur realm, slug string) {
	assertAdmin(cur)
	if _, removed := slots.Remove(slug); !removed {
		panic("no such slot: " + slug)
	}
	rev++
}

// Get returns a slot body, or "" when the slot does not exist.
func Get(slug string) string {
	v := slots.Get(slug)
	if v == nil {
		return ""
	}
	return v.(*slot).body
}

// Revision returns the total number of writes this realm has accepted. It
// changes on every mutation, so a client can cheaply tell "nothing moved".
func Revision() int {
	return rev
}

// Manifest returns one tab-separated line per slot:
//
//	<slug>\t<rev>\t<len>\t<sha256 of body, hex>
//
// It is the diff surface tools/gnohome queries with vm/qeval: one read tells it
// exactly which local file is out of date, without downloading any body.
func Manifest() string {
	var b strings.Builder
	slots.Iterate("", "", func(key string, value any) bool {
		s := value.(*slot)
		sum := sha256.Sum256([]byte(s.body))
		b.WriteString(key)
		b.WriteString("\t")
		b.WriteString(strconv.Itoa(s.rev))
		b.WriteString("\t")
		b.WriteString(strconv.Itoa(len(s.body)))
		b.WriteString("\t")
		b.WriteString(hex.EncodeToString(sum[:]))
		b.WriteString("\n")
		return false
	})
	return b.String()
}
