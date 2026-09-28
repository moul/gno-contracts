// Package nativereg is the metadata a native coin does not have.
//
// A realm-issued coin is a string and a balance. `/gno.land/r/moul/x/moultest/v0:moultest`
// is the entire object: no name, no symbol, no decimals, no icon, no link to
// whoever issues it. The bank knows the number and nothing else, so a wallet or
// an explorer showing you a balance has only that path to print.
//
// This realm is where a denom says what it is. It is the mirror image of
// `r/nt/grc20reg`, and the two solve opposite problems: a GRC20 is an object
// that carries its own name and is hard to FIND, so the registry maps a key to
// the object; a native denom is trivial to find and carries no name, so the
// registry maps the denom to what it means.
//
// # Registration is proved, not claimed
//
// A denom embeds the package path of the realm allowed to issue it, verbatim:
// `"/" + pkgPath + ":" + baseName` (`chain.CoinDenom`). So the issuer is
// readable from the denom, and [Register] simply requires the caller to be it.
// A realm registers its own coins and nobody else's, with no allowlist, no
// owner and no signature scheme.
//
// A user account cannot register anything, not even a denom it holds all of:
// there is no package path in a user call to compare against. That is the
// intended shape, since the thing being described is the issuance, not the
// holding.
//
// # What is a hint and what is a fact
//
// `Denom` and `Issuer` are facts: the chain enforces the relation between them.
// Everything else is whatever the issuing realm chose to say, and `Decimals` in
// particular is a DISPLAY hint with nothing behind it. The bank has no notion of
// divisibility; a coin wrapped out of a 6-decimal GRC20 is still counted in
// whole units by every balance query. Rendering 1000000 as 1.000000 is a
// convention between this realm and whoever reads it.
//
// So trusting an entry means trusting the realm that wrote it, exactly as much
// as holding its coin already means trusting it not to call `RemoveCoin` on you.
package nativereg

import (
	"chain/runtime"
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Entry is what one denom says about itself.
type Entry struct {
	// Denom is the full chain denom, the key of this registry.
	Denom string
	// Issuer is the package path embedded in Denom: the only realm that can
	// issue, remove or re-describe this coin.
	Issuer string
	// Name, Symbol and Decimals are display metadata, chosen by the issuer.
	// Decimals is a hint; see the package doc.
	Name     string
	Symbol   string
	Decimals int
	// Doc is one line about what the coin is for.
	Doc string
	// Height is when the entry was last written.
	Height int64
	// Revisions counts how many times the issuer has rewritten it.
	Revisions int
}

const (
	// MaxName, MaxSymbol and MaxDoc bound what an issuer can store here. The
	// registry pays the storage for every byte a caller hands it, so the
	// limits are the realm's own cost control, not a style rule.
	MaxName   = 40
	MaxSymbol = 12
	MaxDoc    = 200
	// MaxDecimals matches the GRC20 ceiling, which is where a wrapped coin's
	// hint comes from in practice.
	MaxDecimals = 18
)

var (
	byDenom = avl.NewTree() // denom -> *Entry
	denoms  []string        // registration order, for a stable Render
)

// Register records or rewrites what a denom means. The caller must be the realm
// the denom names, which is the entire authorization.
//
// Calling it again overwrites the entry and bumps [Entry.Revisions]. An issuer
// can always re-describe its own coin, and can never describe anybody else's.
func Register(cur realm, denom, name, symbol string, decimals int, doc string) {
	issuer := issuerOf(denom)
	prev := cur.Previous()
	if prev.PkgPath() == "" {
		panic("only the issuing realm can register a denom; a user account has no package path to prove")
	}
	if prev.PkgPath() != issuer {
		panic(ufmt.Sprintf("%s is issued by %s, not by %s", denom, issuer, prev.PkgPath()))
	}
	assertLen("name", name, MaxName)
	assertLen("symbol", symbol, MaxSymbol)
	assertLen("doc", doc, MaxDoc)
	if decimals < 0 || decimals > MaxDecimals {
		panic(ufmt.Sprintf("decimals is %d, must be 0 to %d", decimals, MaxDecimals))
	}

	e := &Entry{
		Denom:    denom,
		Issuer:   issuer,
		Name:     name,
		Symbol:   symbol,
		Decimals: decimals,
		Doc:      doc,
		Height:   runtime.ChainHeight(),
	}
	if old := byDenom.Get(denom); old != nil {
		e.Revisions = old.(*Entry).Revisions + 1
	} else {
		denoms = append(denoms, denom)
	}
	byDenom.Set(denom, e)
}

// Get returns the entry for a denom, and whether it has one.
func Get(denom string) (Entry, bool) {
	v := byDenom.Get(denom)
	if v == nil {
		return Entry{}, false
	}
	return *v.(*Entry), true
}

// MustGet is [Get] for a caller that treats an unregistered denom as a bug.
func MustGet(denom string) Entry {
	e, ok := Get(denom)
	if !ok {
		panic("no entry for " + denom)
	}
	return e
}

// IsRegistered reports whether a denom has said anything about itself.
func IsRegistered(denom string) bool {
	return byDenom.Get(denom) != nil
}

// List returns every entry, in registration order.
func List() []Entry {
	out := make([]Entry, 0, len(denoms))
	for _, d := range denoms {
		out = append(out, MustGet(d))
	}
	return out
}

// ByIssuer returns every entry issued by one realm, in registration order.
func ByIssuer(pkgPath string) []Entry {
	out := []Entry{}
	for _, d := range denoms {
		if e := MustGet(d); e.Issuer == pkgPath {
			out = append(out, e)
		}
	}
	return out
}

// Count returns how many denoms are registered.
func Count() int { return byDenom.Size() }

// IssuerOf returns the package path embedded in a denom, without consulting the
// registry: the relation is in the string itself. It aborts on anything that is
// not a realm denom, which includes `ugnot`.
//
// It is exported because it is useful to anybody handling a denom, registered or
// not: given a balance, this is how you find the code that can take it away.
func IssuerOf(denom string) string { return issuerOf(denom) }

func issuerOf(denom string) string {
	if !strings.HasPrefix(denom, "/") {
		panic("not a realm denom (it must start with /): " + denom)
	}
	i := strings.LastIndex(denom, ":")
	if i < 0 {
		panic("not a realm denom (it must contain :): " + denom)
	}
	issuer := denom[1:i]
	if issuer == "" || denom[i+1:] == "" {
		panic("malformed denom: " + denom)
	}
	return issuer
}

func assertLen(what, s string, max int) {
	if len(s) > max {
		panic(ufmt.Sprintf("%s is %d bytes, max %d", what, len(s), max))
	}
}
