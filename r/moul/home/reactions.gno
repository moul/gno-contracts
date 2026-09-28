package home

import (
	"gno.land/p/moul/dynreplacer/v0"
	"gno.land/r/moul/reactions/v0"
)

// This file is the one interactive thing on the page: a :reactions: placeholder
// that renders the reaction block from gno.land/r/moul/reactions, keyed on this
// realm's path.
//
// Nothing is stored here. The tallies live in the reactions realm, which is why
// this realm can be redeployed (and wiped, see the package doc) without losing
// anyone's reaction, and why adding this cost one placeholder rather than a
// state machine.
//
// The block renders its own txlinks, so a reader clicks an emoji here and lands
// on the reactions realm's $help form with the page prefilled. This realm has
// no write path of its own for it and does not want one: the point of the
// indirection is that the same block behaves identically on every page that
// embeds it.

// reactionsPlaceholders are the reserved slugs this file answers for. Listed in
// reservedSlugs (home.gno) so a slot can never take one of these names and
// shadow the computed value.
var reactionsPlaceholders = []string{"reactions"}

// registerReactionCallbacks adds the reaction placeholder to r.
//
// dynreplacer only invokes a callback whose placeholder actually occurs in the
// layout, so a layout that does not use :reactions: never calls into the
// reactions realm at all.
//
// RenderBlockFor is used rather than the zero-argument RenderBlock, for the
// same reason config.TopBlockFor is (see render.gno): the zero-argument form
// reads the caller off the stack, which would be correct here, but this realm
// already states its own path as a constant and passing it cannot be wrong.
func registerReactionCallbacks(r *dynreplacer.Replacer) {
	r.RegisterCallback(":reactions:", func() string {
		return reactions.RenderBlockFor(realmPath)
	})
}
