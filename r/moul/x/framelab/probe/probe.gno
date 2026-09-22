// Realm probe is shaped exactly like a generated instance realm: it owns the
// state, and every exported function is a one-line re-export that forwards
// `cur` into the shared pure package.
package probe

import (
	"gno.land/p/moul/x/framelab/v0"
	"gno.land/p/nt/grc20/v0"
)

var (
	Token  *grc20.Token
	ledger *grc20.PrivateLedger
)

func init(cur realm) {
	Token, ledger = grc20.NewToken("Probe", "PRB", 6, 0, cur)
}

// Run is the instance-realm shape under test.
func Run(cur realm, from address, amount int64) address {
	return framelab.Pull(0, cur, Token, from, amount)
}

// Frame reports what pure-package code sees as its own realm identity.
func Frame(cur realm) (string, address, bool) { return framelab.Who(0, cur) }
