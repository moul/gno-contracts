package home

import (
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/dynreplacer/v0"
	"gno.land/r/moul/config/v1"
)

// defaultLayout is what renders before a layout slot exists, i.e. right after
// the very first deploy. It uses only computed placeholders, so it never shows
// an unresolved :slug: of its own.
const defaultLayout = "# gno.land/r/moul/home\n\n" +
	"No layout slot yet. Set one, then the page is whatever you make it:\n\n" +
	"    gnokey maketx call -pkgpath gno.land/r/moul/home -func Set \\\n" +
	"      -args layout -args \"$(/bin/cat content/layout.md)\" \\\n" +
	"      -gas-fee 1000000ugnot -gas-wanted 20000000 \\\n" +
	"      -broadcast -chainid gnoland-1 -remote https://rpc.gno.land:443 moul\n\n" +
	"## Slots\n\n:slots:\n\n---\n\nrev :rev: · height :height: · :chainid:\n"

func chainHeight() int64 { return runtime.ChainHeight() }

// Render serves three views:
//
//	""            the assembled page, what https://gno.land/u/moul shows
//	"slots"       the slot index: name, size, revision, last write
//	"slots/<slug>" one slot's raw markdown, fenced
func Render(path string) string {
	switch {
	case path == "":
		return renderPage()
	case path == "slots":
		return renderIndex()
	case strings.HasPrefix(path, "slots/"):
		return renderSlot(strings.TrimPrefix(path, "slots/"))
	default:
		return "# Not found\n\nNo such path: " + strconv.Quote(path) +
			"\n\nTry [the slot index](/r/moul/home:slots).\n"
	}
}

// renderPage fills the layout. dynreplacer only invokes the callbacks whose
// placeholder actually occurs in the layout, so an unused slot is never even
// read out of the tree.
func renderPage() string {
	layout := Get(layoutSlug)
	if layout == "" {
		layout = defaultLayout
	}

	r := dynreplacer.New()

	// Computed from chain state. Registered first; assertWritableSlug keeps a
	// slot from ever taking one of these names, so nothing shadows them.
	r.RegisterCallback(":owner:", func() string { return admin.String() })
	r.RegisterCallback(":realm:", func() string { return realmPath })
	r.RegisterCallback(":chainid:", func() string { return runtime.ChainID() })
	r.RegisterCallback(":height:", func() string { return strconv.FormatInt(runtime.ChainHeight(), 10) })
	r.RegisterCallback(":rev:", func() string { return strconv.Itoa(rev) })
	r.RegisterCallback(":slots:", func() string { return slotLinks() })

	// The explorer links, which are computed the same way but come from
	// another realm's configuration. See scan.gno.
	registerScanCallbacks(r)

	// One callback per slot. The closure captures s, which is re-bound on each
	// iteration, so every callback sees its own slot.
	slots.Iterate("", "", func(key string, value any) bool {
		s := value.(*slot)
		r.RegisterCallback(":"+key+":", func() string { return s.body })
		return false
	})

	// The notice blocks, from gno.land/r/moul/config: a warning, a changelog
	// line or a bit of news, set either on every realm of moul's at once or on
	// this one alone, and empty by default. A pause banner rides along at the
	// top, so the page explains itself if this realm is ever held back.
	//
	// The path is passed explicitly rather than using config's zero-argument
	// TopBlock(). That form reads the caller off the stack, which is correct
	// here and is covered by config's own tests, but this realm's Render IS
	// gno.land/u/moul and it already states its own path: passing the constant
	// cannot be wrong, at no cost.
	return config.TopBlockFor(realmPath) + r.Replace(layout) + config.BottomBlockFor(realmPath)
}

// slotLinks is the :slots: placeholder: a bullet list of every slot, linking to
// its raw view.
func slotLinks() string {
	if slots.Size() == 0 {
		return "_no slots yet_"
	}
	var b strings.Builder
	slots.Iterate("", "", func(key string, value any) bool {
		b.WriteString("- [")
		b.WriteString(key)
		b.WriteString("](/r/moul/home:slots/")
		b.WriteString(key)
		b.WriteString(")\n")
		return false
	})
	return strings.TrimSuffix(b.String(), "\n")
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# Slots\n\n")
	b.WriteString("rev ")
	b.WriteString(strconv.Itoa(rev))
	b.WriteString(" · ")
	b.WriteString(strconv.Itoa(slots.Size()))
	b.WriteString(" slot(s)\n\n")
	if slots.Size() == 0 {
		b.WriteString("_no slots yet_\n")
		return b.String()
	}
	b.WriteString("| slot | bytes | rev | height |\n")
	b.WriteString("| --- | ---: | ---: | ---: |\n")
	slots.Iterate("", "", func(key string, value any) bool {
		s := value.(*slot)
		b.WriteString("| [")
		b.WriteString(key)
		b.WriteString("](/r/moul/home:slots/")
		b.WriteString(key)
		b.WriteString(") | ")
		b.WriteString(strconv.Itoa(len(s.body)))
		b.WriteString(" | ")
		b.WriteString(strconv.Itoa(s.rev))
		b.WriteString(" | ")
		b.WriteString(strconv.FormatInt(s.updated, 10))
		b.WriteString(" |\n")
		return false
	})
	return b.String()
}

func renderSlot(slug string) string {
	v := slots.Get(slug)
	if v == nil {
		return "# Not found\n\nNo slot named " + strconv.Quote(slug) +
			".\n\nTry [the slot index](/r/moul/home:slots).\n"
	}
	s := v.(*slot)
	var b strings.Builder
	b.WriteString("# ")
	b.WriteString(slug)
	b.WriteString("\n\n")
	b.WriteString(strconv.Itoa(len(s.body)))
	b.WriteString(" bytes · rev ")
	b.WriteString(strconv.Itoa(s.rev))
	b.WriteString(" · written at height ")
	b.WriteString(strconv.FormatInt(s.updated, 10))
	b.WriteString("\n\n```\n")
	b.WriteString(s.body)
	if !strings.HasSuffix(s.body, "\n") {
		b.WriteString("\n")
	}
	b.WriteString("```\n")
	return b.String()
}
