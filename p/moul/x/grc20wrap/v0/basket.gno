package grc20wrap

import (
	"math/overflow"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
)

// leg is one component of a Basket.
type leg struct {
	tok    *grc20.Token
	teller grc20.Teller
	per    int64 // units escrowed per meta unit
	held   int64 // units escrowed so far
}

// Basket issues ONE meta-token over several underlying GRC20s at fixed
// proportions. Minting a meta unit escrows every leg's `per` amount; redeeming
// hands all of them back.
//
// A two-leg basket is the interesting one: it makes a pair tradable, quotable
// and transferable as a single object, without a price oracle, an AMM or any
// notion of what the legs are worth. The basket never values anything - it only
// ever swaps a fixed bundle for a receipt and back, so it cannot be arbitraged
// or drained. What it CAN do is let the market price the bundle, which is
// exactly how an index token works.
//
// Proportions are fixed at creation. Rebalancing would mean revaluing the legs,
// which needs a price, which is a different contract.
type Basket struct {
	legs []*leg
	home address
	tok  *grc20.Token
	led  *grc20.PrivateLedger
}

// NewBasket issues a meta-token over tokens[i], escrowing parts[i] units of
// each per meta unit.
//
// Both slices must be the same length, hold at least two entries, name no token
// twice, and every part must be positive. As with NewVault, pass the owning
// realm's own cur: escrow lands at that realm's address.
func NewBasket(tokens []*grc20.Token, parts []int64, name, symbol string, decimals int, id seqid.ID, rlm realm) *Basket {
	if len(tokens) < 2 || len(tokens) != len(parts) {
		panic(ErrBadLegs)
	}
	legs := make([]*leg, 0, len(tokens))
	for i, t := range tokens {
		if t == nil {
			panic(ErrNilToken)
		}
		if parts[i] <= 0 {
			panic(ErrBadLegs)
		}
		for _, seen := range legs {
			if seen.tok.ID() == t.ID() {
				panic(ErrBadLegs)
			}
		}
		legs = append(legs, &leg{
			tok:    t,
			teller: t.RealmTeller(0, rlm),
			per:    parts[i],
		})
	}
	tok, led := grc20.NewToken(name, symbol, decimals, id, rlm)
	return &Basket{
		legs: legs,
		home: rlm.Address(),
		tok:  tok,
		led:  led,
	}
}

// Token is the meta-token this basket issues.
func (b *Basket) Token() *grc20.Token { return b.tok }

// Home is the escrow account: the host realm's address.
func (b *Basket) Home() address { return b.home }

// Legs is the number of components.
func (b *Basket) Legs() int { return len(b.legs) }

// Leg returns the i-th component: its token, the units escrowed per meta unit,
// and the units escrowed so far.
func (b *Basket) Leg(i int) (*grc20.Token, int64, int64) {
	l := b.legs[i]
	return l.tok, l.per, l.held
}

// Solvent reports whether every leg's escrow account still covers what the
// basket recorded taking in.
func (b *Basket) Solvent() bool {
	for _, l := range b.legs {
		if l.tok.BalanceOf(b.home) < l.held {
			return false
		}
	}
	return true
}

// Fuse escrows per*units of every leg from `from` and mints `units` of the meta
// token to it.
//
// `from` must have approved b.Home() on EVERY leg first. The whole basket is
// priced and checked before the first transfer, so a caller short on leg two
// gets an error with leg one untouched.
func (b *Basket) Fuse(_ int, rlm realm, from address, units int64) error {
	if units <= 0 {
		return ErrInvalidAmount
	}
	need := make([]int64, len(b.legs))
	for i, l := range b.legs {
		n, ok := overflow.Mul64(l.per, units)
		if !ok {
			return ErrOverflow
		}
		if l.tok.BalanceOf(from) < n {
			return ErrShortBalance
		}
		if l.tok.Allowance(from, b.home) < n {
			return ErrShortAllowance
		}
		need[i] = n
	}
	// Past here every leg was checked, so a failure is an invariant
	// violation and the transaction must not stand.
	for i, l := range b.legs {
		if err := l.teller.TransferFrom(0, rlm, from, b.home, need[i]); err != nil {
			panic(err)
		}
		l.held += need[i]
	}
	if err := b.led.Mint(from, units); err != nil {
		panic(err)
	}
	return nil
}

// Defuse burns `units` of the meta token held by `to` and returns every leg's
// share of the escrow to it.
func (b *Basket) Defuse(_ int, rlm realm, to address, units int64) error {
	if units <= 0 {
		return ErrInvalidAmount
	}
	give := make([]int64, len(b.legs))
	for i, l := range b.legs {
		n, ok := overflow.Mul64(l.per, units)
		if !ok {
			return ErrOverflow
		}
		if n > l.held {
			return ErrUnbacked
		}
		give[i] = n
	}
	if err := b.led.Burn(to, units); err != nil {
		return err
	}
	for i, l := range b.legs {
		l.held -= give[i]
		if err := l.teller.Transfer(0, rlm, to, give[i]); err != nil {
			panic(err)
		}
	}
	return nil
}

// Move transfers meta units between two accounts.
func (b *Basket) Move(from, to address, amount int64) error {
	if amount <= 0 {
		return ErrInvalidAmount
	}
	return b.led.Transfer(from, to, amount)
}

// Allow sets `spender`'s allowance over `owner`'s meta balance.
func (b *Basket) Allow(owner, spender address, amount int64) error {
	return b.led.Approve(owner, spender, amount)
}

// MoveFrom spends `spender`'s allowance over `owner`'s meta balance.
func (b *Basket) MoveFrom(spender, owner, to address, amount int64) error {
	if amount <= 0 {
		return ErrInvalidAmount
	}
	return b.led.TransferFrom(owner, spender, to, amount)
}

// Summary renders the basket as a markdown block.
func (b *Basket) Summary() string {
	s := ufmt.Sprintf("**%s** (%s) - meta-token over %d legs\n\n",
		b.tok.GetName(), b.tok.GetSymbol(), len(b.legs))
	s += ufmt.Sprintf("- meta supply: %d\n", b.tok.TotalSupply())
	for _, l := range b.legs {
		s += ufmt.Sprintf("- leg %s: %d per unit, %d escrowed\n",
			l.tok.GetSymbol(), l.per, l.held)
	}
	if b.Solvent() {
		s += "- solvent: yes\n"
	} else {
		s += "- solvent: **NO**\n"
	}
	return s
}
