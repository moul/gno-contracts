// Package framelab probes, at runtime, which realm frame pure-package code
// executes in when a realm forwards its own `cur` into it.
//
// The whole instance-per-realm ("factory") pattern rests on the answer: if a
// p/ helper acting on `cur` binds to the *importing realm's* identity, then a
// 20-line instance realm can hold state and funds while every line of logic
// lives in one shared pure package. If instead the frame shifts, the pattern
// is dead and each instance has to carry its own copy of the logic.
package framelab

import "gno.land/p/nt/grc20/v0"

// The leading `_ int` is mandatory, not cosmetic: gno rejects a function whose
// FIRST parameter is `realm` when it is declared in a pure package ("crossing
// function declared in non-realm package"). Same reason grc20's Teller methods
// are shaped `Transfer(_ int, rlm realm, ...)`. The name matters too: only the
// first realm argument of a real crossing function may be called `cur`.
//
// Who reports the frame identity as seen from inside pure-package code.
func Who(_ int, rlm realm) (pkgPath string, addr address, isCurrent bool) {
	return rlm.PkgPath(), rlm.Address(), rlm.IsCurrent()
}

// Pull performs the operation the pattern actually needs: a GRC20 pull done by
// pure-package code, under the importing realm's identity. It returns the
// address the teller bound to, which is the claim under test.
func Pull(_ int, rlm realm, tok *grc20.Token, from address, amount int64) address {
	self := rlm.Address()
	err := tok.RealmTeller(0, rlm).TransferFrom(0, rlm, from, self, amount)
	if err != nil {
		panic(err)
	}
	return self
}
