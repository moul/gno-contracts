package main

import (
	"strconv"
	"strings"
)

// defaultLayout mirrors r/moul/home/render.gno, so a preview of a repo with no
// layout.md shows the same page a fresh deploy would.
const defaultLayout = "# gno.land/r/moul/home\n\n" +
	"No layout slot yet. Set one, then the page is whatever you make it:\n\n" +
	"    gnokey maketx call -pkgpath gno.land/r/moul/home -func Set \\\n" +
	"      -args layout -args \"$(/bin/cat content/layout.md)\" \\\n" +
	"      -gas-fee 1000000ugnot -gas-wanted 20000000 \\\n" +
	"      -broadcast -chainid gnoland-1 -remote https://rpc.gno.land:443 moul\n\n" +
	"## Slots\n\n:slots:\n\n---\n\nrev :rev: · height :height: · :chainid:\n"

const layoutSlug = "layout"

// env holds the values the realm computes from chain state. Locally they are
// supplied, not observed: preview is exact for everything else, and these five
// are the only places its output can differ from the chain's.
type env struct {
	owner   string
	realm   string
	chainID string
	height  int64
	rev     int
}

// render reproduces the realm's renderPage exactly: one non-recursive pass of
// p/moul/dynreplacer over the layout, substituting only the placeholders that
// actually occur in it.
//
// Order-independence holds here for the same reason it holds on chain: every
// placeholder is :slug: and a slug may not contain ':', so no placeholder can
// be a prefix of another and strings.Replacer has no ambiguity to resolve.
func render(slots []slotFile, e env) string {
	layout := defaultLayout
	for _, s := range slots {
		if s.slug == layoutSlug {
			layout = s.body
			break
		}
	}

	pairs := make([]string, 0, 2*(len(slots)+6))
	add := func(placeholder, value string) {
		if strings.Contains(layout, placeholder) {
			pairs = append(pairs, placeholder, value)
		}
	}

	add(":owner:", e.owner)
	add(":realm:", e.realm)
	add(":chainid:", e.chainID)
	add(":height:", strconv.FormatInt(e.height, 10))
	add(":rev:", strconv.Itoa(e.rev))
	add(":slots:", slotLinks(slots))
	for _, s := range slots {
		add(":"+s.slug+":", s.body)
	}

	if len(pairs) == 0 {
		return layout
	}
	return strings.NewReplacer(pairs...).Replace(layout)
}

// slotLinks mirrors the realm's :slots: placeholder.
func slotLinks(slots []slotFile) string {
	if len(slots) == 0 {
		return "_no slots yet_"
	}
	var b strings.Builder
	for i, s := range slots {
		if i > 0 {
			b.WriteString("\n")
		}
		b.WriteString("- [" + s.slug + "](/r/moul/home:slots/" + s.slug + ")")
	}
	return b.String()
}
