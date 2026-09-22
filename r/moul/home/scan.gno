package home

import (
	"strings"

	"chain/runtime"

	"gno.land/p/moul/dynreplacer/v0"
	"gno.land/p/moul/mygnoscan/v0"
	"gno.land/r/moul/config/v1"
)

// This file is the explorer half of the page: a handful of computed
// placeholders that turn what this realm already knows (its own path, its
// owner, the block it is rendering at) into links a reader can click.
//
// They are COMPUTED, not slots, so they are always current: the layout slot
// says where a link goes on the page, and nothing in storage has to be
// rewritten when the answer changes.
//
// The explorer they point at comes from gno.land/r/moul/config, not from a
// constant here. That is the whole point of the indirection: moving every one
// of moul's realms to a different explorer is one transaction against config,
// not a redeploy of each realm that links to one. When config has no setting,
// mygnoscan.DefaultBase answers, so this realm renders correctly on a chain
// where nothing was ever configured.

// scanPlaceholders are the reserved slugs this file answers for. They are
// listed in reservedSlugs (home.gno) so a slot can never take one of these
// names and shadow the computed value.
var scanPlaceholders = []string{
	"scan",       // the explorer base URL, as plain text
	"scan.realm", // this realm on the explorer
	"scan.me",    // the owner's account page
	"scan.block", // the block this render is happening at
	"scan.links", // the three above, on one line
}

// scanner returns the configured link builder.
//
// config.Scanner() is a read, and a cheap one: an avl lookup plus a struct.
// It is called once per render and the result reused, rather than once per
// placeholder, because dynreplacer may invoke several of the callbacks below
// and each would otherwise repeat the cross-realm call.
func scanner() mygnoscan.Scanner { return config.Scanner() }

// registerScanCallbacks adds the explorer placeholders to r.
//
// dynreplacer only invokes a callback whose placeholder actually occurs in the
// layout, so a layout using none of these costs one config.Scanner() call and
// nothing else.
func registerScanCallbacks(r *dynreplacer.Replacer) {
	s := scanner()

	r.RegisterCallback(":scan:", func() string { return s.Base() })
	r.RegisterCallback(":scan.realm:", func() string {
		return mygnoscan.Link("mygnoscan", s.Realm(realmPath))
	})
	r.RegisterCallback(":scan.me:", func() string {
		return mygnoscan.Link("my account", s.Address(admin))
	})
	r.RegisterCallback(":scan.block:", func() string {
		return mygnoscan.Link("this block", s.Block(runtime.ChainHeight()))
	})
	r.RegisterCallback(":scan.links:", func() string { return scanLinks(s) })
}

// scanLinks is the :scan.links: placeholder: everything above on one line, for
// a layout that wants the footer and does not want to lay it out by hand.
func scanLinks(s mygnoscan.Scanner) string {
	parts := []string{
		mygnoscan.Link("this realm", s.Realm(realmPath)),
		mygnoscan.Link("my account", s.Address(admin)),
		mygnoscan.Link("this block", s.Block(runtime.ChainHeight())),
	}
	return strings.Join(parts, " · ")
}
