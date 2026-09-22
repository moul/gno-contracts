package grc20wrap

import "gno.land/p/nt/ufmt/v0"

// Policy is a wrapper's personality. It sets the exchange rate in both
// directions and can veto a move of the wrapped token.
//
// Every method receives the vault, so a policy can price against live state -
// escrow, supply, custody - instead of a frozen constant. Embed OneToOne to
// write a policy that only overrides what it cares about.
type Policy interface {
	// WrapRate returns how many wrapped units `in` underlying units mint.
	// It is called BEFORE the escrow moves, so v.Held() excludes `in`.
	WrapRate(v *Vault, in int64) (int64, error)

	// UnwrapRate returns how many underlying units `in` wrapped units
	// release. It is called before the burn, so v.Supply() includes `in`.
	UnwrapRate(v *Vault, in int64) (int64, error)

	// CanMove vetoes a transfer of the wrapped token between two accounts.
	CanMove(v *Vault, from, to address, amount int64) error

	// Name labels the policy in a catalogue. Short, lowercase.
	Name() string
}

// OneToOne is the boring wrapper: one underlying unit in, one wrapped unit
// out, and no restriction on who may hold the result. Useful on its own as a
// pure custody receipt, and as the embedded base of every policy below.
type OneToOne struct{}

func (OneToOne) WrapRate(v *Vault, in int64) (int64, error) { return in, nil }

func (OneToOne) UnwrapRate(v *Vault, in int64) (int64, error) { return in, nil }

func (OneToOne) CanMove(v *Vault, from, to address, amount int64) error { return nil }

func (OneToOne) Name() string { return "1:1" }

// Ratio re-denominates: Num wrapped units per Den underlying units. Both terms
// must be positive.
//
// Ratio{Num: 1000, Den: 1} turns one underlying unit into a thousand wrapped
// ones, which is how you give a token three more decimals without touching the
// realm that issued it. The reverse direction divides, so a redemption that
// rounds to zero is refused (ErrDust) rather than silently burning value: with
// Num=1000, unwrapping 999 wrapped units returns nothing and is rejected.
type Ratio struct {
	OneToOne
	Num int64
	Den int64
}

func (r Ratio) WrapRate(v *Vault, in int64) (int64, error) {
	if r.Num <= 0 || r.Den <= 0 {
		return 0, ErrBadRatio
	}
	return mulDiv(in, r.Num, r.Den)
}

func (r Ratio) UnwrapRate(v *Vault, in int64) (int64, error) {
	if r.Num <= 0 || r.Den <= 0 {
		return 0, ErrBadRatio
	}
	return mulDiv(in, r.Den, r.Num)
}

func (r Ratio) Name() string { return ufmt.Sprintf("%d:%d", r.Num, r.Den) }

// Soulbound wraps another policy and refuses every transfer of the wrapped
// token. Rates are whatever Base says; a nil Base means OneToOne.
//
// The result is an account-bound receipt: anyone can wrap into it and anyone
// can unwrap back out, but the wrapped unit itself never changes hands. That
// makes it a membership badge, a proof of deposit, or a vote weight that
// cannot be rented - while the underlying stays fully liquid one step away.
//
// The veto binds signing users only; see the package doc.
type Soulbound struct {
	Base Policy
}

func (s Soulbound) base() Policy {
	if s.Base == nil {
		return OneToOne{}
	}
	return s.Base
}

func (s Soulbound) WrapRate(v *Vault, in int64) (int64, error) {
	return s.base().WrapRate(v, in)
}

func (s Soulbound) UnwrapRate(v *Vault, in int64) (int64, error) {
	return s.base().UnwrapRate(v, in)
}

func (s Soulbound) CanMove(v *Vault, from, to address, amount int64) error {
	return ErrSoulbound
}

func (s Soulbound) Name() string { return "soulbound/" + s.base().Name() }

// Pool prices in shares instead of units: the wrapped token is a claim on a
// fraction of the escrow rather than on a fixed amount.
//
//	wrap:   shares = in * supply / held      (1:1 while the pool is empty)
//	unwrap: units  = in * held  / supply
//
// Nothing changes until someone calls Vault.Donate, which adds escrow without
// minting shares. Every outstanding share is then worth more, permanently and
// for everyone at once. That is the whole yield-bearing-token pattern in two
// lines of arithmetic: a fee sink, a staking reward, an airdrop to holders, all
// the same operation.
//
// Two honest caveats:
//
//   - Division truncates, so a share is always worth marginally less than its
//     exact fraction. The remainder stays in the pool, which is the safe
//     direction: a vault can never promise more than it holds.
//   - A first depositor can wrap one unit, donate a large amount, and make
//     every later deposit smaller than one share round to zero in their favour
//     (the ERC-4626 inflation attack). Seed the pool at creation, or keep the
//     wrapped token's decimals well above the underlying's, before using this
//     anywhere real.
type Pool struct {
	OneToOne
}

func (Pool) WrapRate(v *Vault, in int64) (int64, error) {
	supply, held := v.Supply(), v.Held()
	if supply == 0 || held == 0 {
		return in, nil
	}
	return mulDiv(in, supply, held)
}

func (Pool) UnwrapRate(v *Vault, in int64) (int64, error) {
	supply := v.Supply()
	if supply == 0 {
		return 0, ErrDust
	}
	return mulDiv(in, v.Held(), supply)
}

func (Pool) Name() string { return "pool" }

// Fee takes a basis-point haircut in both directions on top of Base (nil means
// OneToOne). 100 BPS is 1%.
//
// The haircut is not paid to anyone: it stays escrowed. Over a plain base that
// only strands value, so Fee is meant to sit over Pool, where the stranded
// units raise what every remaining share redeems for. The wrapper then pays its
// holders out of its own turnover, and paying twice - in and out - costs more
// than holding.
type Fee struct {
	Base      Policy
	WrapBPS   int64
	UnwrapBPS int64
}

func (f Fee) base() Policy {
	if f.Base == nil {
		return OneToOne{}
	}
	return f.Base
}

// cut removes bps basis points from amount.
func cut(amount, bps int64) (int64, error) {
	if bps < 0 || bps > 10000 {
		return 0, ErrBadBPS
	}
	taken, err := mulDiv(amount, bps, 10000)
	if err != nil {
		return 0, err
	}
	return amount - taken, nil
}

func (f Fee) WrapRate(v *Vault, in int64) (int64, error) {
	out, err := f.base().WrapRate(v, in)
	if err != nil {
		return 0, err
	}
	return cut(out, f.WrapBPS)
}

func (f Fee) UnwrapRate(v *Vault, in int64) (int64, error) {
	out, err := f.base().UnwrapRate(v, in)
	if err != nil {
		return 0, err
	}
	return cut(out, f.UnwrapBPS)
}

func (f Fee) CanMove(v *Vault, from, to address, amount int64) error {
	return f.base().CanMove(v, from, to, amount)
}

func (f Fee) Name() string {
	return ufmt.Sprintf("fee(%d/%dbps)/%s", f.WrapBPS, f.UnwrapBPS, f.base().Name())
}
