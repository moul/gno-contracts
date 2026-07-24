package linktree

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

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

// SetBio sets (or replaces) the calling address's bio.
func SetBio(cur realm, bio string) {
	addr := unsafe.PreviousRealm().Address()
	p := getOrCreate(addr.String())
	p.Bio = bio
	chain.Emit("BioSet", "addr", addr.String())
}

// AddLink appends a labeled URL to the calling address's profile.
func AddLink(cur realm, label string, url string) {
	if label == "" {
		panic("label must not be empty")
	}
	if url == "" {
		panic("url must not be empty")
	}
	addr := unsafe.PreviousRealm().Address()
	p := getOrCreate(addr.String())
	p.Links = append(p.Links, link{Label: label, URL: url})
	chain.Emit("LinkAdded", "addr", addr.String(), "label", label)
}

// RemoveLink deletes the link at index from the calling address's profile.
func RemoveLink(cur realm, index int) {
	addr := unsafe.PreviousRealm().Address()
	key := addr.String()
	v, ok := profiles.Get(key)
	if !ok {
		panic("no profile for caller")
	}
	p := v.(*profile)
	if index < 0 || index >= len(p.Links) {
		panic("index out of range")
	}
	p.Links = append(p.Links[:index], p.Links[index+1:]...)
	chain.Emit("LinkRemoved", "addr", key, "index", strconv.Itoa(index))
}

// getOrCreate returns the profile for key, creating an empty one if absent.
func getOrCreate(key string) *profile {
	if v, ok := profiles.Get(key); ok {
		return v.(*profile)
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
		b.WriteString("](/r/REPLACE_ADDR/linktree:")
		b.WriteString(key)
		b.WriteString(")\n")
		return false
	})
	return b.String()
}

func renderProfile(addr string) string {
	var b strings.Builder
	b.WriteString("# ")
	b.WriteString(addr)
	b.WriteString("\n\n")

	v, ok := profiles.Get(addr)
	if !ok {
		b.WriteString("_No profile for this address._\n")
		return b.String()
	}
	p := v.(*profile)

	if p.Bio != "" {
		b.WriteString(p.Bio)
		b.WriteString("\n\n")
	}

	if len(p.Links) == 0 {
		b.WriteString("_No links yet._\n")
		return b.String()
	}

	b.WriteString("## Links\n\n")
	for _, l := range p.Links {
		b.WriteString("- [")
		b.WriteString(l.Label)
		b.WriteString("](")
		b.WriteString(l.URL)
		b.WriteString(")\n")
	}
	return b.String()
}
