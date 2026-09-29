// Package pilotdemo is a power for a realm-driven account: a payout module
// installed into gno.land/p/moul/pilot/v0 after the account was deployed.
//
// It shows both delegation modes side by side:
//
//   - Pay goes through the account's revocable [pilot.Purse]. Revoking the
//     module stops it on the next call, even though this realm still holds
//     the purse object.
//   - Act is only reachable under an identity grant: the account lends its
//     sub-identity, this realm acts as "<account>#<subpath>" toward another
//     realm, and spends the sub-treasury through a banker it mints. That
//     banker is KEPT on purpose, which is what makes an identity grant
//     permanent: revoking stops Exec, not this.
//
// Demo of gno.land/p/moul/pilot/v0. Account instance: r/moul/pilot.
package pilotdemo

import (
	"chain"
	"chain/banker"

	"gno.land/p/moul/pilot/v0"
	"gno.land/p/nt/ufmt/v0"

	account "gno.land/r/moul/pilot/v0"
)

type payout struct {
	purse *pilot.Purse
	kept  banker.Banker // minted from a lent identity, and retained
	sub   address
	dest  address
	paid  int64
}

func (m *payout) Name() string { return "payout" }

// Run is what the account calls. rlm is the account's sub-identity token
// under an identity grant, and its plain cur otherwise.
func (m *payout) Run(_ int, rlm realm, args string) string {
	if !rlm.IsCurrent() {
		panic("pilotdemo: stale realm value")
	}
	if rlm.Subpath() == "" {
		// purse-only grant: no identity to act under
		m.purse.Pay(m.dest, 100)
		m.paid += 100
		return ufmt.Sprintf("paid 100ugnot from the main treasury, %d left", m.purse.Left())
	}

	// identity grant: act as the account toward another realm...
	seen := Echo(cross(rlm))

	// ...and spend the sub-treasury it owns.
	m.sub = rlm.Address()
	m.kept = banker.NewBanker(banker.BankerTypeRealmSend, rlm)
	m.kept.SendCoins(m.sub, m.dest, chain.NewCoins(chain.NewCoin("ugnot", 100)))
	m.paid += 100
	return "acted as " + seen
}

var self = &payout{}

// Install wires this module into moul's account.
func Install(cur realm, dest address) {
	InstallInto(cur, account.Handle(), dest)
}

// InstallInto wires it into ANY account: a module is not bound to one
// instance. gno has no dynamic call, so the handle has to be passed as a
// value, which a `gnokey maketx run` script can do and a MsgCall cannot.
func InstallInto(cur realm, acct *pilot.Account, dest address) {
	self.dest = dest
	acct.Register(0, cur, self)
	self.purse = acct.PurseFor(0, cur)
}

// Echo reports who called it. A crossing call shifts the previous-realm
// stack even into the same realm, so this is what the module's borrowed
// identity looks like from the outside.
func Echo(cur realm) string { return cur.Previous().PkgPath() }

// Payout spends the sub-treasury with the retained banker, reaching the bank
// without re-entering the account. This is the demonstration that an
// identity grant cannot be revoked: it keeps working after Revoke.
func Payout(cur realm, to address, amount int64) {
	if self.kept == nil {
		panic("pilotdemo: no identity was ever granted")
	}
	self.kept.SendCoins(self.sub, to, chain.NewCoins(chain.NewCoin("ugnot", amount)))
}

// Paid is what this module has moved in total.
func Paid() int64 { return self.paid }

func Render(path string) string {
	if self.purse == nil {
		return "# pilotdemo\n\nNot installed.\n"
	}
	return ufmt.Sprintf("# pilotdemo\n\n| | |\n|---|---|\n| destination | %s |\n| purse left | %d ugnot |\n",
		self.dest.String(), self.purse.Left())
}
