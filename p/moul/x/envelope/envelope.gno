// Package envelope reads and forwards the coins a transaction attached to a
// call: the `-send` field of a `MsgCall`, credited to the called realm's address
// before a line of its code runs.
//
// It exists because "payable" is not a keyword in gno, it is a runtime fact. The
// VM rejects a `MsgCall` that carried coins the callee never looked at
// (gno.land/pkg/sdk/vm/keeper.go, `if !send.IsZero() && !*OriginSendObserved`),
// and reading the envelope is what counts as looking. So every realm that
// accepts payment writes the same three things by hand: read the amount, abort
// with something the caller can act on when it is zero or the wrong denom, and
// forward or keep it. This package is those three things.
//
// # Native coins are push-only, which is why this matters
//
// A realm cannot pull a native coin. `banker.SendCoins` panics unless the
// `from` address is the banker's own realm address, so there is no allowance
// and no `TransferFrom` for a native denom. The envelope is the entire inbound
// path: either the holder signs a bank send, or they attach coins to a call and
// the callee reads them here.
//
// That is also why a GRC20 needs `Approve` and a native coin does not. The GRC20
// grants standing authority to a spender; the envelope grants authority over one
// message and expires with it.
//
// # Who may forward, which is not about depth
//
// [Forward] mints a `BankerTypeOriginSend` banker, and `NewBanker` accepts that
// type only when `rlm.Previous().IsUserCall()` holds. `Realm.IsUserCall` is
// literally `pkgPath == ""` (gnovm/stdlibs/chain/runtime/frame.gno), so the test
// is about WHO entered the realm, not about how deep inside it you are:
//
//   - `maketx call` straight into the realm: fine, and the realm may pass its
//     `cur` down through as many of its own helpers as it likes. Measured at
//     three nested calls, and through a function value and a closure.
//   - realm A calls realm B, and B tries to forward: refused. B's previous is a
//     code realm, so the envelope it was handed is not B's to route.
//   - `maketx run`: refused. The run package is a code realm
//     (`<domain>/e/<addr>/run`), so `IsUserCall` is false there too, and every
//     payable function is therefore unreachable from a run script.
//
// The reading helpers have none of these conditions: they go through
// `unsafe.OriginSend()`, a context read that works anywhere, including inside a
// `Render`.
//
package envelope

import (
	"chain"
	"chain/banker"
	"chain/runtime/unsafe"

	"gno.land/p/nt/ufmt/v0"
)

// Amount returns how much of denom this message's envelope carried, and zero
// when it carried none. Reading it is what makes the call payable.
func Amount(denom string) int64 {
	return unsafe.OriginSend().AmountOf(denom)
}

// All returns the whole envelope, every denom in it.
//
// A call can be paid in several denoms at once, which is a property of the bank
// rather than of any realm: a `Coins` set holds up to 256 of them. A realm that
// only wants one should use [Only].
func All() chain.Coins {
	return unsafe.OriginSend()
}

// IsEmpty reports whether nothing was attached to this call.
func IsEmpty() bool {
	return len(unsafe.OriginSend()) == 0
}

// Require returns [Amount] and aborts when it is zero, with a message naming the
// flag the caller left out.
//
// The message is the point. "insufficient funds" sends somebody to their wallet;
// naming the denom and the flag sends them to the fix.
func Require(denom string) int64 {
	amount := Amount(denom)
	if amount <= 0 {
		panic("this call must be paid: attach coins with -send <amount>" + denom)
	}
	return amount
}

// RequireAtLeast is [Require] with a floor, and names both numbers when the
// envelope falls short.
func RequireAtLeast(denom string, min int64) int64 {
	amount := Require(denom)
	if amount < min {
		panic(ufmt.Sprintf("this call costs at least %d%s, the envelope carried %d",
			min, denom, amount))
	}
	return amount
}

// RequireExactly is [Require] for a fixed price, and refuses an overpayment as
// well as an underpayment.
//
// Refusing to be overpaid is the unusual half, and it is deliberate: a realm
// that silently keeps the excess has invented a fee nobody agreed to, and a
// realm that refunds it has to move coins back out, which is a second failure
// mode. Aborting costs the caller one transaction and nothing else.
func RequireExactly(denom string, price int64) int64 {
	amount := Require(denom)
	if amount != price {
		panic(ufmt.Sprintf("this call costs exactly %d%s, the envelope carried %d",
			price, denom, amount))
	}
	return amount
}

// Only is [Require] plus a refusal of anything else in the envelope.
//
// Use it wherever the realm has no code that would ever move a second denom,
// because coins it does not handle are coins stranded at its address forever:
// they are not refunded, and only the realm's own code can ever send them on.
func Only(denom string) int64 {
	amount := Require(denom)
	for _, coin := range unsafe.OriginSend() {
		if coin.Denom != denom {
			panic(ufmt.Sprintf("this call takes %s only, the envelope also carried %d%s",
				denom, coin.Amount, coin.Denom))
		}
	}
	return amount
}

// Forward sends coins from the calling realm's address to `to`, bounded by this
// message's envelope.
//
// The banker it mints can spend the envelope and nothing else: not the realm's
// own balance, not a previous message's payment. That is what makes a routing
// function safe to write, and it is enforced by the VM rather than by the code
// here (`ctx.OriginSend.IsAllGTE(spent)`).
//
// It must be reached from a call a USER made into this realm; see the package
// doc for what that rules out.
//
// The leading `_ int` is not decoration: a non-realm package may not declare a
// crossing function, so a `p/` helper that needs a realm handle threads it as a
// later parameter. That is the same shape `p/nt/grc20`'s tellers use, and gno
// refuses the file outright without it ("crossing function (realm first
// argument) declared in non-realm package").
//
// This function has no test in this package either, for the same reason it has
// that signature: minting the banker calls `rlm.Previous()`, and a `p/` test has
// no realm frame to walk ("frame not found: cannot seek beyond origin caller
// override"). It is exercised from `r/moul/x/nativeify`'s tests instead.
func Forward(_ int, rlm realm, to address, coins chain.Coins) {
	banker.NewBanker(banker.BankerTypeOriginSend, rlm).SendCoins(rlm.Address(), to, coins)
}

// ForwardAll forwards everything the envelope carried of denom, and returns it.
// It aborts when the envelope carried none, like [Require].
func ForwardAll(_ int, rlm realm, to address, denom string) int64 {
	amount := Require(denom)
	Forward(0, rlm, to, chain.NewCoins(chain.NewCoin(denom, amount)))
	return amount
}

// BalanceOf returns what addr holds of denom right now, straight from the bank.
//
// It takes an address rather than a realm handle because it needs no authority
// at all: a readonly banker is constructible from anywhere, including a Render.
// Pass `cur.Address()` for the realm's own balance, envelope included.
func BalanceOf(addr address, denom string) int64 {
	return banker.NewReadonlyBanker().GetCoin(addr, denom)
}
