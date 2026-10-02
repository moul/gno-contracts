package linktree

import (
	"strconv"
	"strings"

	"chain"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/nt/avl/v0"
)

// selfPath is this realm's own page. A root-relative link resolves against
// the domain, not the realm, so every link back into it names it in full.
const selfPath = "/r/moul/x/daily/linktree/v1"

// link is a single labeled URL on a profile.
type link struct {
	Label string
	URL   string
}

// profile is one address's personal links page.
type profile struct {
	Bio   string
	Links []link
}

// profiles maps an address (string key) to its *profile.
// avl.Tree keeps iteration deterministic for Render.
var profiles avl.Tree

// The bounds on what a caller may store. Anyone may create a profile, and the
// root page lists every profile while a profile page lists every link.
const (
	MaxProfiles = 1000
	MaxLinks    = 20
	MaxBioLen   = 280
	MaxLabelLen = 64
	MaxURLLen   = 512
)

// SetBio sets (or replaces) the calling address's bio.
func SetBio(cur realm, bio string) {
	addr := caller(cur)
	if len(bio) > MaxBioLen {
		panic("bio too long")
	}
	p := getOrCreate(addr.String())
	p.Bio = bio
	chain.Emit("BioSet", "addr", addr.String())
}

// AddLink appends a labeled URL to the calling address's profile.
func AddLink(cur realm, label string, url string) {
	addr := caller(cur)
	if label == "" {
		panic("label must not be empty")
	}
	if url == "" {
		panic("url must not be empty")
	}
	// The URL becomes a markdown link destination as written, so it is
	// checked here rather than escaped there: http(s) only, and nothing that
	// could close the destination or start another.
	if !safeURL(url) {
		panic("url must be http:// or https:// with no spaces, parentheses or angle brackets")
	}
	if len(label) > MaxLabelLen || len(url) > MaxURLLen {
		panic("label or url too long")
	}
	p := getOrCreate(addr.String())
	if len(p.Links) >= MaxLinks {
		panic("a profile holds at most " + strconv.Itoa(MaxLinks) + " links")
	}
	p.Links = append(p.Links, link{Label: label, URL: url})
	chain.Emit("LinkAdded", "addr", addr.String(), "label", label)
}

// RemoveLink deletes the link at index from the calling address's profile.
func RemoveLink(cur realm, index int) {
	addr := caller(cur)
	key := addr.String()
	v := profiles.Get(key)
	if v == nil {
		panic("no profile for caller")
	}
	p := v.(*profile)
	if index < 0 || index >= len(p.Links) {
		panic("index out of range")
	}
	// A fresh slice, not append(s[:i], s[i+1:]...): the in-place form keeps the
	// old backing array, so the deposit for a removed link never comes back.
	kept := make([]link, 0, len(p.Links)-1)
	kept = append(kept, p.Links[:index]...)
	kept = append(kept, p.Links[index+1:]...)
	p.Links = kept
	chain.Emit("LinkRemoved", "addr", key, "index", strconv.Itoa(index))
}

// getOrCreate returns the profile for key, creating an empty one if absent.
func getOrCreate(key string) *profile {
	if v := profiles.Get(key); v != nil {
		return v.(*profile)
	}
	if profiles.Size() >= MaxProfiles {
		panic("linktree is full at " + strconv.Itoa(MaxProfiles) + " profiles")
	}
	p := &profile{}
	profiles.Set(key, p)
	return p
}

// Render shows all profiles at root, or a single profile at "/<address>".
func Render(path string) string {
	addr := strings.Trim(path, "/")
	if addr == "" {
		return renderIndex()
	}
	return renderProfile(addr)
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# Linktree\n\n")
	if profiles.Size() == 0 {
		b.WriteString("_No profiles yet. Call `SetBio` or `AddLink` to create one._\n")
		return b.String()
	}
	b.WriteString("Profiles:\n\n")
	profiles.Iterate("", "", func(key string, _ interface{}) bool {
		b.WriteString("- [")
		b.WriteString(key)
		b.WriteString("](" + selfPath + ":")
		b.WriteString(key)
		b.WriteString(")\n")
		return false
	})
	return b.String()
}

func renderProfile(addr string) string {
	var b strings.Builder
	b.WriteString("# ")
	b.WriteString(ui.Inline(addr))
	b.WriteString("\n\n")

	v := profiles.Get(addr)
	if v == nil {
		b.WriteString("_No profile for this address._\n")
		return b.String()
	}
	p := v.(*profile)

	if p.Bio != "" {
		b.WriteString(ui.Inline(p.Bio))
		b.WriteString("\n\n")
	}

	if len(p.Links) == 0 {
		b.WriteString("_No links yet._\n")
		return b.String()
	}

	b.WriteString("## Links\n\n")
	for _, l := range p.Links {
		b.WriteString("- [")
		b.WriteString(ui.Inline(l.Label))
		b.WriteString("](")
		b.WriteString(l.URL)
		b.WriteString(")\n")
	}
	return b.String()
}

// caller is the address that crossed into this realm, after checking that the
// realm token is this frame's own.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("linktree: spoofed realm")
	}
	return cur.Previous().Address()
}

// safeURL reports whether u can be written into a markdown link destination
// unescaped.
func safeURL(u string) bool {
	if !strings.HasPrefix(u, "https://") && !strings.HasPrefix(u, "http://") {
		return false
	}
	return !strings.ContainsAny(u, " \t\r\n()<>[]`\\")
}
