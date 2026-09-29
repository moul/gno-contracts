package pilotdemo

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	account "gno.land/r/moul/pilot/v0"
)

const modPath = "gno.land/r/moul/x/pilotdemo/v0"

var (
	owner   = testutils.TestAddress("owner")
	dest    = testutils.TestAddress("dest")
	claimed bool
)

// claim is safe to call from every test: realm state carries over between
// test functions, so the account is claimed exactly once per run.
func claim(cur realm) {
	if claimed {
		return
	}
	claimed = true
	account.Claim(cross(cur))
}

func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoin(addr, "ugnot")
}

func TestPurseGrantIsRevocable(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	claim(cur)

	treasury := account.Address()
	testing.IssueCoins(treasury, chain.NewCoins(chain.NewCoin("ugnot", 10_000)))

	testing.SetRealm(testing.NewUserRealm(owner))
	account.Approve(cross(cur), modPath, "payout", false, 250)

	// the module installs itself; the account reads its path from the runtime
	Install(cross(cur), dest)

	testing.SetRealm(testing.NewUserRealm(owner))
	uassert.Equal(t, "paid 100ugnot from the main treasury, 150 left",
		account.Exec(cross(cur), modPath, ""))
	uassert.Equal(t, int64(100), balance(dest))
	uassert.Equal(t, int64(9_900), balance(treasury))

	// the owner revokes. the module still holds the purse object.
	testing.SetRealm(testing.NewUserRealm(owner))
	account.Revoke(cross(cur), modPath)
	uassert.Equal(t, int64(0), self.purse.Left())

	// both doors are shut: through the account...
	testing.SetRealm(testing.NewUserRealm(owner))
	uassert.AbortsContains(t, cur, "revoked", func() {
		account.Exec(cross(cur), modPath, "")
	})
	// ...and through the retained purse, which is the one that matters.
	uassert.AbortsContains(t, cur, "revoked", func() {
		self.purse.Pay(dest, 10)
	})
	uassert.Equal(t, int64(100), balance(dest))
}

func TestIdentityGrantActsAsTheAccount(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	claim(cur)

	testing.SetRealm(testing.NewUserRealm(owner))
	account.Approve(cross(cur), modPath, "payout", true, 250)
	Install(cross(cur), dest)

	sub := account.SubAddress(modPath)
	testing.IssueCoins(account.Address(), chain.NewCoins(chain.NewCoin("ugnot", 10_000)))

	testing.SetRealm(testing.NewUserRealm(owner))
	account.Fund(cross(cur), modPath, 1_000)
	uassert.Equal(t, int64(1_000), balance(sub))

	testing.SetRealm(testing.NewUserRealm(owner))
	got := account.Exec(cross(cur), modPath, "")

	// the module acted as the ACCOUNT's sub-identity, not as itself
	uassert.Equal(t, "acted as gno.land/r/moul/pilot/v0#payout", got)
	uassert.Equal(t, int64(900), balance(sub))
	uassert.Equal(t, int64(100), balance(dest))
}

func TestIdentityGrantOutlivesRevoke(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	claim(cur)

	testing.SetRealm(testing.NewUserRealm(owner))
	account.Approve(cross(cur), modPath, "payout", true, 250)
	Install(cross(cur), dest)

	sub := account.SubAddress(modPath)
	testing.IssueCoins(account.Address(), chain.NewCoins(chain.NewCoin("ugnot", 10_000)))
	testing.SetRealm(testing.NewUserRealm(owner))
	account.Fund(cross(cur), modPath, 1_000)

	testing.SetRealm(testing.NewUserRealm(owner))
	account.Exec(cross(cur), modPath, "") // mints and keeps a banker on the sub-address
	uassert.Equal(t, int64(900), balance(sub))

	// revoke shuts the account door
	testing.SetRealm(testing.NewUserRealm(owner))
	account.Revoke(cross(cur), modPath)
	uassert.AbortsContains(t, cur, "revoked", func() {
		account.Exec(cross(cur), modPath, "")
	})

	// and the retained banker keeps spending anyway. This is the documented
	// cost of an identity grant: revoking is not taking it back.
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("anyone")))
	Payout(cross(cur), dest, 900)
	uassert.Equal(t, int64(0), balance(sub))
}

func TestRender(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	claim(cur)

	// a fresh approval is a fresh allowance, so this reads the same whatever
	// ran before it
	testing.SetRealm(testing.NewUserRealm(owner))
	account.Approve(cross(cur), modPath, "payout", false, 1_000)
	Install(cross(cur), dest)
	testing.IssueCoins(account.Address(), chain.NewCoins(chain.NewCoin("ugnot", 10_000)))

	testing.SetRealm(testing.NewUserRealm(owner))
	account.Exec(cross(cur), modPath, "")

	uassert.Equal(t, "# pilotdemo\n\n| | |\n|---|---|\n| destination | "+
		dest.String()+" |\n| purse left | 900 ugnot |\n", Render(""))
}
