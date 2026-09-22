package config

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const otherRealm = "gno.land/r/moul/gns"

func TestKeyGrammar(t *testing.T) {
	uassert.Equal(t, "pause", KeyFor("pause", ""))
	uassert.Equal(t, "pause@r/moul/home", KeyFor("pause", "gno.land/r/moul/home"))
	uassert.Equal(t, "pause@r/moul/home", KeyFor("pause", "r/moul/home"))

	// A path this cannot scope to falls back to the global key rather than
	// inventing one nobody can type.
	uassert.Equal(t, "pause", KeyFor("pause", "not a path"))
	uassert.Equal(t, "pause", KeyFor("pause", "gno.land/"))

	name, scope := SplitKey("block.top@r/moul/home")
	uassert.Equal(t, "block.top", name)
	uassert.Equal(t, "r/moul/home", scope)

	name, scope = SplitKey("block.top")
	uassert.Equal(t, "block.top", name)
	uassert.Equal(t, "", scope)
}

func TestScope(t *testing.T) {
	uassert.Equal(t, "r/moul/home", Scope("gno.land/r/moul/home"))
	uassert.Equal(t, "r/moul/home", Scope("r/moul/home"))
	uassert.Equal(t, "p/moul/kit/ui", Scope("gno.land/p/moul/kit/ui"))
	uassert.Equal(t, "", Scope(""))
	uassert.Equal(t, "", Scope("gno.land/"))
	uassert.Equal(t, "", Scope("r/moul/ho me"))
	uassert.Equal(t, "", Scope("r//moul"))
}

// TestBlocksDefaultEmpty is the property every realm depends on: a realm that
// renders config.TopBlock() unconditionally must be byte-for-byte what it was
// before, until moul sets something.
func TestBlocksDefaultEmpty(t *testing.T) {
	resetSettings()
	uassert.Equal(t, "", TopBlockFor(otherRealm))
	uassert.Equal(t, "", BottomBlockFor(otherRealm))
}

func TestBlocksGlobalAndScoped(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyBlockTop, "> chain migration on Tuesday")

	// Global alone reaches every realm, and ends with a blank line so a realm
	// can concatenate without a separator of its own.
	uassert.Equal(t, "> chain migration on Tuesday\n\n", TopBlockFor(otherRealm))
	uassert.Equal(t, "> chain migration on Tuesday\n\n", TopBlockFor("gno.land/r/moul/home"))

	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyFor(KeyBlockTop, otherRealm), "> v2 shipped")

	// BOTH are shown, global first. A chain-wide warning and a per-realm
	// changelog are different messages; dropping either would be the
	// surprising behaviour.
	uassert.Equal(t,
		"> chain migration on Tuesday\n\n> v2 shipped\n\n",
		TopBlockFor(otherRealm))

	// And the scoped one reaches only its own realm.
	uassert.Equal(t, "> chain migration on Tuesday\n\n", TopBlockFor("gno.land/r/moul/home"))
}

func TestBottomBlock(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyBlockBottom, "built by moul")

	uassert.Equal(t, "built by moul\n\n", BottomBlockFor(otherRealm))

	// The pause banner belongs to the top only: one banner is enough, and the
	// top is where it gets read.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyPause, "paused")
	uassert.Equal(t, "built by moul\n\n", BottomBlockFor(otherRealm))
}

// TestTopBlockCarriesPause is the integration that makes guarding writes
// enough: a realm that calls AssertWritable and renders TopBlock explains the
// refusal on its own page without writing a line of banner code.
func TestTopBlockCarriesPause(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyPause, "readonly: migrating storage")

	uassert.Equal(t,
		"> **Read-only.** This realm is still readable, but not accepting changes. migrating storage\n\n",
		TopBlockFor(otherRealm))

	// And it comes first, before the messages.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyBlockTop, "> news")
	uassert.Equal(t,
		"> **Read-only.** This realm is still readable, but not accepting changes. migrating storage\n\n> news\n\n",
		TopBlockFor(otherRealm))
}

// TestZeroArgFormsNameTheCaller pins the borrow behaviour the whole
// zero-argument API rests on: these are plain reads with no `cur realm`, so
// gno opens no realm frame and the realm asking is the realm answered about.
//
// If this ever fails, every zero-argument helper here has silently started
// answering for gno.land/r/moul/config instead, and the …For variants are the
// only correct ones.
func TestZeroArgFormsNameTheCaller(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyFor(KeyBlockTop, otherRealm), "> only for gns")

	testing.SetRealm(testing.NewCodeRealm(otherRealm))
	uassert.Equal(t, "> only for gns\n\n", TopBlock())
	uassert.Equal(t, otherRealm, caller())

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/moul/home"))
	uassert.Equal(t, "", TopBlock(), "another realm sees nothing")
	uassert.Equal(t, "gno.land/r/moul/home", caller())
}
