// Package vault demonstrates a minimal time-locked token vault built on top of
// the grc20 token package. Deposited tokens are held at the realm's own
// address; withdrawing them is a two-step process: Unvault marks an amount for
// withdrawal and starts a lock timer, then (once the lock elapses) Redeem moves
// the tokens back to the depositor.
package vault

import (
	"chain/runtime"
	"chain/runtime/unsafe"

	tokens "gno.land/p/demo/tokens/grc20"
)

// test1 receives the initial mint at construction.
var test1 = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

// lockDuration is the number of blocks that must pass between Unvault and
// Redeem.
const lockDuration = int64(100)

// Token and FooVault-equivalent state are exported for reading; privateLedger
// stays unexported (unrestricted mint/burn/transfer).
var (
	Token         *tokens.Token
	privateLedger *tokens.PrivateLedger
	vaultAddr     address // address holding all deposited tokens

	vaulted   = map[address]uint{}    // still-locked deposits per owner
	pending   = map[address]uint{}    // amount marked for withdrawal
	unlockAt  = map[address]int64{}    // block height at which pending unlocks
	recoverOf = map[address]address{}  // recovery address per depositor
)

func init(cur realm) {
	// generate the token and mint some tokens to test1.
	Token, privateLedger = tokens.NewToken("Foo Token", "FOO", 4, 0, cur)
	privateLedger.Mint(test1, 100000000)

	// the vault holds deposited tokens at the realm's own address.
	vaultAddr = cur.Address()
}

func MyBalance() int64 {
	return Token.BalanceOf(unsafe.OriginCaller())
}

// Deposit moves amount tokens from the caller into the vault, recording a
// recovery address for later use.
func Deposit(cur realm, amount uint, recoverAddress address) {
	caller := unsafe.OriginCaller()
	if err := privateLedger.Transfer(caller, vaultAddr, int64(amount)); err != nil {
		panic(err)
	}
	vaulted[caller] += amount
	recoverOf[caller] = recoverAddress
}

// Recover sends target's still-locked deposit to its recorded recovery address.
func Recover(cur realm, target address) {
	amount := vaulted[target]
	if amount == 0 {
		return
	}
	dest := recoverOf[target]
	if err := privateLedger.Transfer(vaultAddr, dest, int64(amount)); err != nil {
		panic(err)
	}
	vaulted[target] = 0
}

// Unvault marks amount of the caller's deposit for withdrawal and starts the
// lock timer.
func Unvault(cur realm, amount uint) {
	caller := unsafe.OriginCaller()
	if vaulted[caller] < amount {
		panic("insufficient vaulted balance")
	}
	vaulted[caller] -= amount
	pending[caller] += amount
	unlockAt[caller] = runtime.ChainHeight() + lockDuration
}

// Redeem transfers amount of the caller's matured pending withdrawal back to
// the caller.
func Redeem(cur realm, amount uint) {
	caller := unsafe.OriginCaller()
	if pending[caller] < amount {
		panic("insufficient pending balance")
	}
	if runtime.ChainHeight() < unlockAt[caller] {
		panic("still locked")
	}
	if err := privateLedger.Transfer(vaultAddr, caller, int64(amount)); err != nil {
		panic(err)
	}
	pending[caller] -= amount
}
