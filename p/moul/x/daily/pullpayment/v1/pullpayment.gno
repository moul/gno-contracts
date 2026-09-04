// Package pullpayment is the escrow ledger behind the pull-payment pattern, as
// a pure, reusable package.
//
// The pattern is the classic Solidity answer to reentrancy: never push value to
// an address, credit it and let the recipient withdraw. A push sends control to
// the recipient in the middle of your state transition, and a malicious
// recipient re-enters before you have finished updating. Pull inverts that —
// the recipient calls in, and their own withdrawal is the only state being
// touched.
//
// This package is the BOOKKEEPING half only: who is owed what, and the
// checks-effects-interactions ordering that makes a withdrawal safe. It moves
// no coins. The realm that holds the funds performs the transfer AFTER calling
// Withdraw, which is exactly the ordering the pattern demands — the balance is
// already zeroed when the transfer happens, so a reentrant call finds nothing
// left to take.
//
// Iteration is over sorted addresses, never a built-in map range: gno map
// iteration order is unspecified and a Render built from one can differ between
// nodes, which is a consensus bug rather than a cosmetic one.
//
// A live demo of this package is at
// [r/moul/x/daily/pullpaymentdemo](/r/moul/x/daily/pullpaymentdemo/v1).
package pullpayment

import (
	"errors"
	"sort"
)

// MaxPayees bounds the ledger so gas stays predictable.
const MaxPayees = 4096

var (
	ErrBadAmount = errors.New("pullpayment: amount must be positive")
	ErrFull      = errors.New("pullpayment: too many payees")
	ErrNothing   = errors.New("pullpayment: nothing to withdraw")
	ErrOverflow  = errors.New("pullpayment: credit would overflow")
)

const maxInt64 = int64(9223372036854775807)

// Ledger records what each address is owed.
type Ledger struct {
	owed      map[string]int64
	total     int64
	withdrawn int64
}

// New returns an empty Ledger.
func New() *Ledger { return &Ledger{owed: map[string]int64{}} }

// Credit records that payee is owed amount more. Amounts accumulate: crediting
// twice owes the sum.
func (l *Ledger) Credit(payee string, amount int64) error {
	if amount <= 0 {
		return ErrBadAmount
	}
	cur, seen := l.owed[payee]
	if !seen && len(l.owed) >= MaxPayees {
		return ErrFull
	}
	if cur > maxInt64-amount || l.total > maxInt64-amount {
		return ErrOverflow
	}
	l.owed[payee] = cur + amount
	l.total += amount
	return nil
}

// Balance returns what payee is currently owed; zero when nothing.
func (l *Ledger) Balance(payee string) int64 { return l.owed[payee] }

// Withdraw zeroes payee's balance and returns what was owed.
//
// The caller transfers the returned amount AFTER this call. That ordering is
// the point of the pattern: the credit is already gone from the ledger when
// control passes to the recipient, so a reentrant Withdraw returns ErrNothing.
func (l *Ledger) Withdraw(payee string) (int64, error) {
	amount, ok := l.owed[payee]
	if !ok || amount == 0 {
		return 0, ErrNothing
	}
	delete(l.owed, payee) // effects before interactions
	l.total -= amount
	l.withdrawn += amount
	return amount, nil
}

// Forfeit drops a payee's credit without paying it, returning what was dropped.
func (l *Ledger) Forfeit(payee string) (int64, error) {
	amount, ok := l.owed[payee]
	if !ok || amount == 0 {
		return 0, ErrNothing
	}
	delete(l.owed, payee)
	l.total -= amount
	return amount, nil
}

// TotalOwed returns the sum of every outstanding balance — what the holding
// realm must keep in reserve.
func (l *Ledger) TotalOwed() int64 { return l.total }

// TotalWithdrawn returns the lifetime sum of successful withdrawals.
func (l *Ledger) TotalWithdrawn() int64 { return l.withdrawn }

// Payees returns every address with an outstanding balance, sorted.
func (l *Ledger) Payees() []string {
	out := make([]string, 0, len(l.owed))
	for p := range l.owed {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// Count returns how many payees are owed something.
func (l *Ledger) Count() int { return len(l.owed) }

// IsEmpty reports whether nothing is owed to anyone.
func (l *Ledger) IsEmpty() bool { return len(l.owed) == 0 }

// Iterate calls fn for each payee in sorted order. Returning true stops.
func (l *Ledger) Iterate(fn func(payee string, amount int64) bool) {
	for _, p := range l.Payees() {
		if fn(p, l.owed[p]) {
			return
		}
	}
}

// CreditMany credits several payees, applying nothing unless every entry is
// valid — a partial split would leave the ledger disagreeing with the funds.
func (l *Ledger) CreditMany(payees []string, amounts []int64) error {
	if len(payees) != len(amounts) {
		return ErrBadAmount
	}
	// Validate first.
	for _, a := range amounts {
		if a <= 0 {
			return ErrBadAmount
		}
	}
	probe := len(l.owed)
	for _, p := range payees {
		if _, seen := l.owed[p]; !seen {
			probe++
		}
	}
	if probe > MaxPayees {
		return ErrFull
	}
	var sum int64
	for _, a := range amounts {
		if sum > maxInt64-a {
			return ErrOverflow
		}
		sum += a
	}
	if l.total > maxInt64-sum {
		return ErrOverflow
	}
	// Then apply.
	for i, p := range payees {
		l.owed[p] += amounts[i]
	}
	l.total += sum
	return nil
}

// Consistent reports whether TotalOwed equals the sum of the balances. Always
// true through the public API; exported so callers can assert the invariant.
func (l *Ledger) Consistent() bool {
	var sum int64
	for _, a := range l.owed {
		sum += a
	}
	return sum == l.total
}
