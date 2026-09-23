// Package blog is moul's personal blog on gno.land: one realm, one author,
// posts that live in chain storage rather than in the code.
//
// # The shape
//
// A post is markdown plus four fields (slug, title, date, tags). Writing one
// is a single Set transaction, so publishing never redeploys the realm and
// fixing a typo costs one small call instead of a new package path.
//
// The reader-facing paths are deliberately short, because they get pasted into
// other people's chats:
//
//	gno.land/r/moul/blog             the index, newest first
//	gno.land/r/moul/blog:<slug>      one post
//	gno.land/r/moul/blog:t/<tag>     every post carrying a tag
//
// # Ordering without sort
//
// gno has no sort.Slice, and avl.Tree iterates by key. So posts live in two
// trees: `posts` keyed by slug, for the O(log n) lookup a permalink needs, and
// `order` keyed by "<date>/<slug>", walked in reverse for newest-first. The
// date is YYYY-MM-DD precisely so that lexical order is chronological order,
// which is what makes the second tree free.
//
// # Versioning
//
// gnomod.toml declares private = true, which lets the creator re-add the
// package at this exact path. That redeploy re-runs init() and WIPES every
// post here, so the markdown kept off chain is the source of truth and
// tools/gnoblog pushes it back. Trading that risk for a stable URL is the
// whole design: a /v1 would break every link already shared, a redeploy does
// not, and Manifest() makes restoring the content one diff.
package blog

import (
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// author is the only address allowed to write. Deliberately a constant rather
// than transferable ownership: this is one person's blog, and the same address
// is the only one the chain lets redeploy the realm anyway, so a second owner
// could publish posts it could never restore after a wipe.
const author = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")

// realmPath is this realm's own path, used to build the links Render emits.
const realmPath = "gno.land/r/moul/blog"

// maxSlugLen bounds a slug so a permalink stays typable and a key stays cheap.
const maxSlugLen = 64

// excerptLen is how much of a post body the index shows.
const excerptLen = 200

// introKey is the manifest key of the index header. It starts with '!', which
// validSlug rejects, so it can never collide with a post.
const introKey = "!intro"

// introSlug is refused as a post slug. Not because this realm needs it: the
// intro lives in its own variable. It is refused so that the local half stays
// representable, where a post is <slug>.md and the header is intro.md. A post
// published at this slug by a hand-written transaction would have no file it
// could live in, and tools/gnoblog would report it as an extra forever.
const introSlug = "intro"

type post struct {
	slug    string
	title   string
	date    string // YYYY-MM-DD, the sort key
	tags    string // comma-separated, normalized by splitTags
	body    string // raw markdown, authored by `author`, rendered unescaped
	rev     int    // rev at the time of the last write to this post
	updated int64  // block height of the last write
}

var (
	posts = avl.NewTree() // slug             -> *post
	order = avl.NewTree() // "<date>/<slug>"  -> *post
	intro string          // markdown shown above the index
	rev   int             // total writes accepted, bumped by every mutation
)

func assertAuthor(cur realm) {
	if cur.Previous().Address() != author {
		panic("restricted to the author")
	}
}

// validSlug reports whether slug is a legal permalink: 1..maxSlugLen bytes of
// [a-z0-9._-]. The character set excludes ':' and '/' so a slug can never
// break out of its own render path, and excludes uppercase so a post has
// exactly one URL.
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

// validDate reports whether date is exactly YYYY-MM-DD. The format is not
// cosmetic: `order` relies on lexical order being chronological order, so a
// date of any other shape would silently sort into the wrong place.
func validDate(date string) bool {
	if len(date) != 10 {
		return false
	}
	for i := 0; i < 10; i++ {
		c := date[i]
		if i == 4 || i == 7 {
			if c != '-' {
				return false
			}
			continue
		}
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// orderKey is the key a post takes in `order`. The slug is appended so two
// posts published on the same day do not collide.
func orderKey(date, slug string) string { return date + "/" + slug }

// splitTags normalizes a comma-separated tag list: trimmed, lowercased,
// deduplicated, empties dropped. It returns the canonical string that gets
// stored, so the hash a client computes locally matches the one on chain.
func splitTags(tags string) []string {
	var out []string
	for _, t := range strings.Split(tags, ",") {
		t = strings.ToLower(strings.TrimSpace(t))
		if t == "" {
			continue
		}
		dup := false
		for _, seen := range out {
			if seen == t {
				dup = true
				break
			}
		}
		if !dup {
			out = append(out, t)
		}
	}
	return out
}

func joinTags(tags []string) string { return strings.Join(tags, ",") }

// record is the canonical serialization a post hashes to. Both this realm and
// tools/gnoblog build it the same way, which is what lets one Manifest() read
// decide whether a local file needs a transaction at all.
func record(title, date, tags, body string) string {
	return title + "\n" + date + "\n" + tags + "\n" + body
}

func hashOf(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// Set creates or replaces the post at slug. This is the ordinary publish: one
// post, one transaction, idempotent.
//
// Changing the date moves the post in the index, so the old order entry is
// removed before the new one is written.
func Set(cur realm, slug, title, date, tags, body string) {
	assertAuthor(cur)
	if !validSlug(slug) {
		panic("invalid slug: want 1-" + strconv.Itoa(maxSlugLen) + " bytes of [a-z0-9._-], got " + strconv.Quote(slug))
	}
	if slug == introSlug {
		panic("reserved slug: " + introSlug + " names the index header, set it with SetIntro")
	}
	if !validDate(date) {
		panic("invalid date: want YYYY-MM-DD, got " + strconv.Quote(date))
	}
	title = strings.TrimSpace(title)
	if title == "" {
		panic("a post needs a title")
	}

	if v := posts.Get(slug); v != nil {
		order.Remove(orderKey(v.(*post).date, slug))
	}

	rev++
	p := &post{
		slug:    slug,
		title:   title,
		date:    date,
		tags:    joinTags(splitTags(tags)),
		body:    body,
		rev:     rev,
		updated: runtime.ChainHeight(),
	}
	posts.Set(slug, p)
	order.Set(orderKey(date, slug), p)
}

// Append adds to the end of a post's body. It exists for a body too large to
// fit in one transaction: Set the first chunk, Append the rest. An ordinary
// edit uses Set, which is idempotent and therefore safe to retry.
func Append(cur realm, slug, body string) {
	assertAuthor(cur)
	v := posts.Get(slug)
	if v == nil {
		panic("no such post: " + strconv.Quote(slug))
	}
	p := v.(*post)
	rev++
	p.body += body
	p.rev = rev
	p.updated = runtime.ChainHeight()
}

// Delete removes a post and its index entry.
func Delete(cur realm, slug string) {
	assertAuthor(cur)
	v, removed := posts.Remove(slug)
	if !removed {
		panic("no such post: " + strconv.Quote(slug))
	}
	order.Remove(orderKey(v.(*post).date, slug))
	rev++
}

// SetIntro replaces the markdown shown above the index. Passing "" restores
// the built-in header.
func SetIntro(cur realm, body string) {
	assertAuthor(cur)
	rev++
	intro = body
}

// Get returns a post's raw markdown body, or "" when there is no such post.
func Get(slug string) string {
	v := posts.Get(slug)
	if v == nil {
		return ""
	}
	return v.(*post).body
}

// Count returns the number of published posts.
func Count() int { return posts.Size() }

// Revision returns the total number of writes this realm has accepted. It
// changes on every mutation, so a client can cheaply tell "nothing moved".
func Revision() int { return rev }

// Manifest returns one tab-separated line per post, plus one for the intro:
//
//	<slug>\t<rev>\t<date>\t<len of body>\t<sha256 of the canonical record>
//
// It is the diff surface tools/gnoblog reads with a single vm/qeval: the hash
// covers the title, date, tags and body together, so one read says exactly
// which local file needs a transaction without downloading a single body.
//
// The intro is reported under the key "!intro" with an empty date. '!' is not
// a legal slug character, so that row can never be confused with a post.
func Manifest() string {
	var b strings.Builder

	b.WriteString(introKey)
	b.WriteString("\t0\t\t")
	b.WriteString(strconv.Itoa(len(intro)))
	b.WriteString("\t")
	b.WriteString(hashOf(intro))
	b.WriteString("\n")

	posts.Iterate("", "", func(key string, value any) bool {
		p := value.(*post)
		b.WriteString(p.slug)
		b.WriteString("\t")
		b.WriteString(strconv.Itoa(p.rev))
		b.WriteString("\t")
		b.WriteString(p.date)
		b.WriteString("\t")
		b.WriteString(strconv.Itoa(len(p.body)))
		b.WriteString("\t")
		b.WriteString(hashOf(record(p.title, p.date, p.tags, p.body)))
		b.WriteString("\n")
		return false
	})
	return b.String()
}
