// untrusted-render: this realm stores no string of its own. The only two a
// caller supplies, a module path and its subpath, are written solely by the
// owner through Approve and charset-validated there (p/moul/pilot assertPlain),
// which is what lets Render interpolate them.
// Package pilot is moul's realm-driven account: it holds the funds and the
// identity, moul's key pilots it, and its powers arrive afterwards as
// separate realms that this one never imports.
//
// All behaviour is in gno.land/p/moul/pilot/v0; this realm is the instance.
// Demo of a power: r/moul/x/pilotdemo.
package pilot

import "gno.land/p/moul/pilot/v0"

// owner is pinned in the source rather than taken from whoever calls Claim
// first. A deploy lands in its own block and the claim is a second
// transaction, so an unpinned Claim is a race anyone on chain can win, and
// this account can never be redeployed to undo it.
const owner = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"

var acct *pilot.Pilot

// Claim arms the account. Once, and only by its owner.
func Claim(cur realm) {
	if acct != nil {
		panic("pilot: already claimed")
	}
	if cur.Previous().Address() != owner {
		panic("pilot: only " + owner + " can claim this account")
	}
	acct = pilot.New(0, cur)
}

// Approve authorises a package path to install itself later, under a named
// sub-identity, with a grant and a budget. The code need not exist yet.
func Approve(cur realm, path, subpath string, identity bool, budget int64) {
	grant := pilot.GrantPurse
	if identity {
		grant = pilot.GrantIdentity
	}
	must().Approve(0, cur, path, subpath, grant, budget)
}

// SetBudget changes what a module may still spend, including through a purse
// it already holds.
func SetBudget(cur realm, path string, budget int64) { must().SetBudget(0, cur, path, budget) }

// Revoke stops a module. It cannot take back a granted identity.
func Revoke(cur realm, path string) { must().Revoke(0, cur, path) }

// Fund moves coins from the main treasury into one module's sub-treasury.
func Fund(cur realm, path string, amount int64) { must().Fund(0, cur, path, amount) }

// Exec drives an installed module.
func Exec(cur realm, path, args string) string { return must().Exec(0, cur, path, args) }

// Handle is how a module realm reaches this account. Its two methods key on
// the caller's own pkgpath, which no realm can forge for another.
func Handle() *pilot.Account { return must().Handle() }

// Address is the main treasury.
func Address() address { return must().Address() }

// SubAddress is one module's treasury.
func SubAddress(path string) address { return must().SubAddress(path) }

func Render(path string) string {
	if acct == nil {
		return "# gno.land/r/moul/pilot\n\nUnclaimed.\n"
	}
	return acct.Render(path)
}

func must() *pilot.Pilot {
	if acct == nil {
		panic("pilot: unclaimed")
	}
	return acct
}
