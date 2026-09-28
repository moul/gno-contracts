package nativereg

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

const (
	issuerPath = "gno.land/r/test/coiner"
	issuerCoin = "/gno.land/r/test/coiner:testcoin"
	otherPath  = "gno.land/r/test/stranger"
	otherCoin  = "/gno.land/r/test/stranger:othercoin"
)

// testing.SetRealm governs only the crossing calls made from the frame that
// called it, so each switch below is inline in the test body.

func TestOnlyTheIssuerRegisters(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(issuerPath))
	Register(cross(cur), issuerCoin, "Test Coin", "TEST", 6, "a coin for a test")

	e := MustGet(issuerCoin)
	uassert.Equal(t, issuerPath, e.Issuer, "the issuer is read out of the denom, not supplied")
	uassert.Equal(t, "TEST", e.Symbol)
	uassert.Equal(t, 6, e.Decimals)
	uassert.Equal(t, 0, e.Revisions)

	// The same realm cannot describe somebody else's coin.
	uassert.AbortsContains(t, cur, "is issued by "+otherPath, func() {
		Register(cross(cur), otherCoin, "Not Mine", "NOPE", 0, "")
	})
}

func TestAUserAccountCannotRegister(cur realm, t *testing.T) {
	alice := testutils.TestAddress("nr-alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	// Even for a denom she holds every unit of: what is being described is the
	// issuance, and a wallet has no package path to prove.
	uassert.AbortsContains(t, cur, "no package path to prove", func() {
		Register(cross(cur), issuerCoin, "Mine Now", "MINE", 0, "")
	})
}

func TestReregisteringBumpsRevisions(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(issuerPath))
	before := Count()
	Register(cross(cur), issuerCoin, "Test Coin v2", "TEST2", 4, "renamed")

	e := MustGet(issuerCoin)
	uassert.Equal(t, "TEST2", e.Symbol, "an issuer can always re-describe its own coin")
	uassert.Equal(t, 1, e.Revisions)
	uassert.Equal(t, before, Count(), "a rewrite is not a second entry")
	uassert.Equal(t, 1, len(ByIssuer(issuerPath)))
	uassert.Equal(t, 0, len(ByIssuer(otherPath)))
}

func TestBounds(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(issuerPath))
	uassert.AbortsContains(t, cur, "name is", func() {
		Register(cross(cur), issuerCoin, strings.Repeat("x", MaxName+1), "T", 0, "")
	})
	uassert.AbortsContains(t, cur, "symbol is", func() {
		Register(cross(cur), issuerCoin, "n", strings.Repeat("x", MaxSymbol+1), 0, "")
	})
	uassert.AbortsContains(t, cur, "doc is", func() {
		Register(cross(cur), issuerCoin, "n", "T", 0, strings.Repeat("x", MaxDoc+1))
	})
	uassert.AbortsContains(t, cur, "decimals is 19", func() {
		Register(cross(cur), issuerCoin, "n", "T", MaxDecimals+1, "")
	})
	uassert.AbortsContains(t, cur, "decimals is -1", func() {
		Register(cross(cur), issuerCoin, "n", "T", -1, "")
	})
}

func TestIssuerOfReadsTheDenom(cur realm, t *testing.T) {
	// The relation is in the string, so this answers for a denom nobody ever
	// registered, which is the case that matters: given a balance you did not
	// ask for, this is how you find the code that can take it away.
	uassert.Equal(t, "gno.land/r/nobody/here/v3", IssuerOf("/gno.land/r/nobody/here/v3:ghost"))
	uassert.Equal(t, issuerPath, IssuerOf(issuerCoin))

	uassert.PanicsContains(t, cur, "must start with /", func() { IssuerOf("ugnot") })
	uassert.PanicsContains(t, cur, "must contain :", func() { IssuerOf("/gno.land/r/a/v0") })
	uassert.PanicsContains(t, cur, "malformed", func() { IssuerOf("/gno.land/r/a/v0:") })
	uassert.PanicsContains(t, cur, "malformed", func() { IssuerOf("/:x") })
}

func TestUnregisteredReadsCleanly(cur realm, t *testing.T) {
	_, ok := Get("/gno.land/r/nobody/here/v3:ghost")
	uassert.False(t, ok)
	uassert.False(t, IsRegistered("/gno.land/r/nobody/here/v3:ghost"))
	uassert.PanicsContains(t, cur, "no entry for", func() { MustGet("/gno.land/r/x/y/v0:zz") })
}

func TestRender(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(otherPath))
	Register(cross(cur), otherCoin, "Other Coin", "OTHER", 0, "the second one")

	index := Render("")
	uassert.True(t, strings.Contains(index, "# nativereg"), index)
	uassert.True(t, strings.Contains(index, "OTHER"), "the index lists entries:\n"+index)

	one := Render(otherCoin)
	uassert.True(t, strings.Contains(one, "the second one"), one)
	uassert.True(t, strings.Contains(one, otherPath), one)

	byIssuer := Render(issuerPath)
	uassert.True(t, strings.Contains(byIssuer, "TEST2"), byIssuer)
	uassert.False(t, strings.Contains(byIssuer, "OTHER"), "one issuer's page shows only its own")

	// A Render never aborts on a path a reader typed, registered or not.
	uassert.True(t, strings.Contains(Render("/gno.land/r/x/y/v0:nope"), "Not registered"))
	uassert.True(t, strings.Contains(Render("ugnot"), "registered nothing"),
		"a non-denom path falls through to the issuer view rather than aborting")
	uassert.True(t, strings.Contains(Render("/garbage"), "not a realm denom"))
}

func TestRenderEscapesWhatAnIssuerWrote(cur realm, t *testing.T) {
	// An issuer's own name and doc are still caller-supplied text, and a realm
	// that can register can write a table-breaking pipe as easily as a name.
	const nasty = "gno.land/r/test/nasty"
	testing.SetRealm(testing.NewCodeRealm(nasty))
	Register(cross(cur), "/gno.land/r/test/nasty:nastycoin", "a|b", "x|y", 0, "")

	index := Render("")
	uassert.False(t, strings.Contains(index, "| a|b |"), "a raw pipe would open a column:\n"+index)
	uassert.True(t, strings.Contains(index, "a\\|b"), "it is escaped instead:\n"+index)
}
