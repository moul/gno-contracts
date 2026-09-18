// Package grc20wrap builds derived GRC20 tokens on top of existing ones.
//
// Two shapes:
//
//   - Vault wraps ONE underlying token. It escrows underlying units at the
//     host realm's address and issues its own GRC20 against that escrow. A
//     Policy sets the exchange rate in both directions and may veto a move of
//     the wrapped token, which is where a wrapper stops being plumbing and
//     becomes a pattern: 1:1 custody, a denomination change, a
//     non-transferable receipt, a share in a growing pool.
//   - Basket wraps SEVERAL. One meta-token is minted against fixed parts of
//     every leg and splits back into them on redemption.
//
// Neither type holds chain state of its own beyond the GRC20 ledger it
// creates, so a realm keeps them wherever it likes.
//
// # How custody works
//
// Escrow lands at the HOST REALM's address. A vault moves it through
// grc20.RealmTeller, which binds eagerly to that address, so a vault can only
// ever spend what its own realm holds. Pulling a user's tokens in therefore
// takes the ordinary allowance route: the user approves the host realm's
// address on the underlying token, through that token realm's own entry
// point, and the vault draws on the allowance as itself.
//
// # Reverting, not returning
//
// Wrapping is two ledger writes on two different tokens, and gno has no
// rollback short of a panic: a returned error does not undo what already ran.
// Every method here therefore validates while nothing has moved and returns an
// error, then panics if a write fails after the point of no return. Aborting
// the transaction is the only atomicity available.
//
// # What a Policy can and cannot enforce
//
// A Policy veto binds end users, not realms. Moving the wrapped token through
// Vault.Move is the only path a signing account has, because MsgCall cannot
// build the realm argument grc20's tellers require. Another realm holding the
// wrapped token can always call grc20.RealmTeller on it and move its OWN
// balance. Soulbound means "no user can pass it on", not "it can never move".
//
// Live demo: gno.land/r/moul/x/grc20wrapdemo/v0.
package grc20wrap

import (
	"errors"
	"math/overflow"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
)

var (
	ErrNilToken       = errors.New("grc20wrap: nil underlying token")
	ErrInvalidAmount  = errors.New("grc20wrap: amount must be positive")
	ErrDust           = errors.New("grc20wrap: amount rounds to zero")
	ErrUnbacked       = errors.New("grc20wrap: payout exceeds this vault's escrow")
	ErrSoulbound      = errors.New("grc20wrap: soulbound, the wrapped token cannot change hands")
	ErrOverflow       = errors.New("grc20wrap: arithmetic overflow")
	ErrBadRatio       = errors.New("grc20wrap: ratio terms must be positive")
	ErrBadBPS         = errors.New("grc20wrap: basis points must be within 0..10000")
	ErrBadLegs        = errors.New("grc20wrap: a basket needs at least two legs, each with a positive part")
	ErrShortBalance   = errors.New("grc20wrap: insufficient balance on a leg")
	ErrShortAllowance = errors.New("grc20wrap: insufficient allowance on a leg")
)

// Vault escrows one underlying GRC20 and issues another against it.
//
// The escrow account is the host realm's own address, shared with every other
// vault that realm creates. Separation between them is the per-vault Held()
// counter, not separate accounts: a vault only ever releases what it recorded
// taking in, so the realm-wide invariant is sum(Held) <= Custody().
type Vault struct {
	under  *grc20.Token
	teller grc20.Teller // bound to home, eagerly, at construction
	home   address
	tok    *grc20.Token
	led    *grc20.PrivateLedger
	pol    Policy
	held   int64
}

// NewVault issues a new GRC20 backed by units of under.
//
// Call it from the realm that will own the vault, forwarding that realm's own
// cur: both the teller binding and the new token's origRealm are taken from it
// and cannot be forged afterwards. id disambiguates several tokens minted by
// the same realm - allocate it from one persistent seqid.ID.
//
// A nil pol means OneToOne.
func NewVault(under *grc20.Token, pol Policy, name, symbol string, decimals int, id seqid.ID, rlm realm) *Vault {
	if under == nil {
		panic(ErrNilToken)
	}
	if pol == nil {
		pol = OneToOne{}
	}
	tok, led := grc20.NewToken(name, symbol, decimals, id, rlm)
	return &Vault{
		under:  under,
		teller: under.RealmTeller(0, rlm),
		home:   rlm.Address(),
		tok:    tok,
		led:    led,
		pol:    pol,
	}
}

// Token is the wrapped token this vault issues. It is safe to hand out: a
// *grc20.Token carries metadata and read access, never the authority to debit
// anybody.
func (v *Vault) Token() *grc20.Token { return v.tok }

// Underlying is the token held in escrow.
func (v *Vault) Underlying() *grc20.Token { return v.under }

// Policy is this vault's personality.
func (v *Vault) Policy() Policy { return v.pol }

// Home is the escrow account: the host realm's address.
func (v *Vault) Home() address { return v.home }

// Held is the underlying escrowed for THIS vault, by its own accounting.
func (v *Vault) Held() int64 { return v.held }

// Supply is the wrapped token in circulation.
func (v *Vault) Supply() int64 { return v.tok.TotalSupply() }

// Custody is the underlying actually sitting at the escrow account. It covers
// every vault the host realm created over the same underlying, plus anything
// sent there by mistake, so Custody >= Held is necessary for solvency and
// sufficient only when this is the realm's single vault over that token.
func (v *Vault) Custody() int64 { return v.under.BalanceOf(v.home) }

// Solvent reports whether the escrow account still covers what this vault
// recorded taking in. False means the host realm moved the underlying behind
// the vault's back.
func (v *Vault) Solvent() bool { return v.Custody() >= v.held }

// Wrap escrows amount units of the underlying from `from` and mints the
// wrapped token to `from`, returning how much was minted.
//
// `from` must already have granted v.Home() an allowance of at least amount on
// the underlying token, set through that token realm's own entry point.
func (v *Vault) Wrap(_ int, rlm realm, from address, amount int64) (int64, error) {
	if amount <= 0 {
		return 0, ErrInvalidAmount
	}
	out, err := v.pol.WrapRate(v, amount)
	if err != nil {
		return 0, err
	}
	if out <= 0 {
		return 0, ErrDust
	}
	// Last point at which nothing has moved.
	if err := v.teller.TransferFrom(0, rlm, from, v.home, amount); err != nil {
		return 0, err
	}
	held, ok := overflow.Add64(v.held, amount)
	if !ok {
		panic(ErrOverflow)
	}
	v.held = held
	if err := v.led.Mint(from, out); err != nil {
		// The escrow already moved; only aborting the tx can undo it.
		panic(err)
	}
	return out, nil
}

// Unwrap burns amount wrapped units held by `from` and releases the underlying
// back to it, returning how much was released.
func (v *Vault) Unwrap(_ int, rlm realm, from address, amount int64) (int64, error) {
	if amount <= 0 {
		return 0, ErrInvalidAmount
	}
	out, err := v.pol.UnwrapRate(v, amount)
	if err != nil {
		return 0, err
	}
	if out <= 0 {
		return 0, ErrDust
	}
	if out > v.held {
		return 0, ErrUnbacked
	}
	// Burn first: it is the step that can legitimately fail on a short
	// balance, and it fails before anything has moved.
	if err := v.led.Burn(from, amount); err != nil {
		return 0, err
	}
	v.held -= out
	if err := v.teller.Transfer(0, rlm, from, out); err != nil {
		// The burn already happened; only aborting the tx can undo it.
		panic(err)
	}
	return out, nil
}

// Donate escrows amount units of the underlying without minting anything.
//
// Under a pool policy this is how the wrapper gets interesting: the donation
// raises what every outstanding wrapped unit redeems for, so anyone can make
// every holder richer and nobody can take it back out except by holding.
// `from` must have approved v.Home() on the underlying, as for Wrap.
func (v *Vault) Donate(_ int, rlm realm, from address, amount int64) error {
	if amount <= 0 {
		return ErrInvalidAmount
	}
	if err := v.teller.TransferFrom(0, rlm, from, v.home, amount); err != nil {
		return err
	}
	held, ok := overflow.Add64(v.held, amount)
	if !ok {
		panic(ErrOverflow)
	}
	v.held = held
	return nil
}

// Move transfers wrapped units after the policy has had its say. It is the
// only path a signing user has to move the wrapped token; see the package doc
// for what that does and does not guarantee.
func (v *Vault) Move(from, to address, amount int64) error {
	if amount <= 0 {
		return ErrInvalidAmount
	}
	if err := v.pol.CanMove(v, from, to, amount); err != nil {
		return err
	}
	return v.led.Transfer(from, to, amount)
}

// Allow sets `spender`'s allowance over `owner`'s wrapped balance.
//
// The policy is deliberately not consulted: an allowance moves nothing. It is
// checked when the allowance is spent, in MoveFrom, so a policy that starts
// vetoing later still binds allowances granted before.
func (v *Vault) Allow(owner, spender address, amount int64) error {
	return v.led.Approve(owner, spender, amount)
}

// MoveFrom spends `spender`'s allowance over `owner`'s wrapped balance, after
// the policy has had its say.
func (v *Vault) MoveFrom(spender, owner, to address, amount int64) error {
	if amount <= 0 {
		return ErrInvalidAmount
	}
	if err := v.pol.CanMove(v, owner, to, amount); err != nil {
		return err
	}
	return v.led.TransferFrom(owner, spender, to, amount)
}

// Summary renders the vault as a markdown block.
func (v *Vault) Summary() string {
	s := ufmt.Sprintf("**%s** (%s) - %s wrapper over %s\n\n",
		v.tok.GetName(), v.tok.GetSymbol(), v.pol.Name(), v.under.GetSymbol())
	s += ufmt.Sprintf("- wrapped supply: %d\n", v.Supply())
	s += ufmt.Sprintf("- escrowed underlying: %d\n", v.held)
	s += ufmt.Sprintf("- realm custody: %d\n", v.Custody())
	if v.Solvent() {
		s += "- solvent: yes\n"
	} else {
		s += "- solvent: **NO**\n"
	}
	return s
}

// mulDiv returns a*b/c, rejecting an overflowing product and a zero divisor.
// The division truncates toward zero, which always rounds in the vault's
// favour rather than the holder's.
func mulDiv(a, b, c int64) (int64, error) {
	if c <= 0 {
		return 0, ErrBadRatio
	}
	p, ok := overflow.Mul64(a, b)
	if !ok {
		return 0, ErrOverflow
	}
	return p / c, nil
}
