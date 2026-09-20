package pullpayment

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEmpty(t *testing.T) {
	l := New()
	uassert.True(t, l.IsEmpty())
	uassert.Equal(t, 0, l.Count())
	uassert.Equal(t, int64(0), l.TotalOwed())
	uassert.Equal(t, int64(0), l.Balance("nobody"))
	uassert.True(t, l.Consistent())
}

func TestCreditAccumulates(t *testing.T) {
	l := New()
	uassert.NoError(t, l.Credit("alice", 100))
	uassert.NoError(t, l.Credit("alice", 50))

	uassert.Equal(t, int64(150), l.Balance("alice"), "credits accumulate")
	uassert.Equal(t, 1, l.Count(), "the same payee is not counted twice")
	uassert.Equal(t, int64(150), l.TotalOwed())
	uassert.True(t, l.Consistent())
}

func TestCreditRejectsNonPositive(t *testing.T) {
	l := New()
	uassert.ErrorIs(t, l.Credit("alice", 0), ErrBadAmount)
	uassert.ErrorIs(t, l.Credit("alice", -1), ErrBadAmount)
	uassert.True(t, l.IsEmpty(), "a rejected credit changes nothing")
}

func TestWithdrawZeroesBalance(t *testing.T) {
	l := New()
	l.Credit("alice", 100)

	got, err := l.Withdraw("alice")
	uassert.NoError(t, err)
	uassert.Equal(t, int64(100), got)
	uassert.Equal(t, int64(0), l.Balance("alice"), "the balance is gone before the caller transfers")
	uassert.Equal(t, int64(0), l.TotalOwed())
	uassert.Equal(t, int64(100), l.TotalWithdrawn())
	uassert.True(t, l.Consistent())
}

// TestReentrantWithdrawGetsNothing is the security property the pattern exists
// for: the second entry finds the balance already zeroed.
func TestReentrantWithdrawGetsNothing(t *testing.T) {
	l := New()
	l.Credit("attacker", 1000)

	first, err := l.Withdraw("attacker")
	uassert.NoError(t, err)
	uassert.Equal(t, int64(1000), first)

	// Simulating the reentrant call the recipient would make from its handler,
	// BEFORE the outer caller has transferred anything.
	second, err := l.Withdraw("attacker")
	uassert.ErrorIs(t, err, ErrNothing, "a reentrant withdrawal must find nothing")
	uassert.Equal(t, int64(0), second)
	uassert.Equal(t, int64(1000), l.TotalWithdrawn(), "and must not be counted twice")
}

func TestWithdrawUnknownPayee(t *testing.T) {
	l := New()
	_, err := l.Withdraw("nobody")
	uassert.ErrorIs(t, err, ErrNothing)
}

func TestForfeit(t *testing.T) {
	l := New()
	l.Credit("alice", 100)
	l.Credit("bob", 40)

	dropped, err := l.Forfeit("alice")
	uassert.NoError(t, err)
	uassert.Equal(t, int64(100), dropped)
	uassert.Equal(t, int64(40), l.TotalOwed())
	uassert.Equal(t, int64(0), l.TotalWithdrawn(), "a forfeit is not a withdrawal")
	uassert.True(t, l.Consistent())

	_, err = l.Forfeit("alice")
	uassert.ErrorIs(t, err, ErrNothing)
}

func TestPayeesSorted(t *testing.T) {
	l := New()
	l.Credit("carol", 3)
	l.Credit("alice", 1)
	l.Credit("bob", 2)

	uassert.Equal(t, "alice,bob,carol", strings.Join(l.Payees(), ","))
}

func TestIterateSortedAndStops(t *testing.T) {
	l := New()
	l.Credit("b", 2)
	l.Credit("a", 1)

	var seen []string
	l.Iterate(func(p string, amt int64) bool {
		seen = append(seen, p+":"+strconv.FormatInt(amt, 10))
		return false
	})
	uassert.Equal(t, "a:1,b:2", strings.Join(seen, ","))

	n := 0
	l.Iterate(func(p string, amt int64) bool { n++; return true })
	uassert.Equal(t, 1, n)
}

func TestCreditMany(t *testing.T) {
	l := New()
	err := l.CreditMany([]string{"a", "b", "c"}, []int64{10, 20, 30})
	uassert.NoError(t, err)

	uassert.Equal(t, int64(10), l.Balance("a"))
	uassert.Equal(t, int64(30), l.Balance("c"))
	uassert.Equal(t, int64(60), l.TotalOwed())
	uassert.True(t, l.Consistent())
}

// TestCreditManyIsAllOrNothing pins that a bad entry applies none of the split.
func TestCreditManyIsAllOrNothing(t *testing.T) {
	l := New()
	l.Credit("existing", 5)

	err := l.CreditMany([]string{"a", "b"}, []int64{10, -1})
	uassert.ErrorIs(t, err, ErrBadAmount)

	uassert.Equal(t, int64(0), l.Balance("a"), "the valid entry must not be applied either")
	uassert.Equal(t, int64(5), l.TotalOwed(), "the ledger is untouched")
	uassert.Equal(t, 1, l.Count())
	uassert.True(t, l.Consistent())
}

func TestCreditManyMismatchedLengths(t *testing.T) {
	l := New()
	uassert.ErrorIs(t, l.CreditMany([]string{"a"}, []int64{1, 2}), ErrBadAmount)
	uassert.True(t, l.IsEmpty())
}

func TestCreditManyAccumulates(t *testing.T) {
	l := New()
	l.Credit("a", 5)
	uassert.NoError(t, l.CreditMany([]string{"a", "b"}, []int64{10, 1}))
	uassert.Equal(t, int64(15), l.Balance("a"), "adds to the existing balance")
	uassert.Equal(t, int64(16), l.TotalOwed())
}

func TestOverflowGuard(t *testing.T) {
	l := New()
	uassert.NoError(t, l.Credit("whale", maxInt64))
	uassert.ErrorIs(t, l.Credit("whale", 1), ErrOverflow)
	uassert.ErrorIs(t, l.Credit("other", 1), ErrOverflow, "the total would overflow too")
	uassert.Equal(t, maxInt64, l.TotalOwed(), "a refused credit changes nothing")
	uassert.True(t, l.Consistent())
}

func TestCreditManyOverflowGuard(t *testing.T) {
	l := New()
	l.Credit("a", maxInt64-5)
	uassert.ErrorIs(t, l.CreditMany([]string{"b", "c"}, []int64{10, 10}), ErrOverflow)
	uassert.Equal(t, int64(0), l.Balance("b"), "nothing applied")
}

func TestMaxPayees(t *testing.T) {
	l := New()
	for i := 0; i < MaxPayees; i++ {
		uassert.NoError(t, l.Credit("p"+strconv.Itoa(i), 1))
	}
	uassert.Equal(t, MaxPayees, l.Count())

	uassert.ErrorIs(t, l.Credit("overflow", 1), ErrFull, "a full ledger refuses a new payee")
	uassert.NoError(t, l.Credit("p0", 1), "existing payees can still be credited")
	uassert.Equal(t, int64(2), l.Balance("p0"))
}

func TestCreditManyRespectsCapacity(t *testing.T) {
	l := New()
	for i := 0; i < MaxPayees-1; i++ {
		l.Credit("p"+strconv.Itoa(i), 1)
	}
	uassert.ErrorIs(t, l.CreditMany([]string{"x", "y"}, []int64{1, 1}), ErrFull,
		"the batch would exceed capacity, so none of it applies")
	uassert.Equal(t, int64(0), l.Balance("x"))
}

// TestFullLifecycle walks a realistic split-then-claim sequence.
func TestFullLifecycle(t *testing.T) {
	l := New()
	uassert.NoError(t, l.CreditMany([]string{"alice", "bob", "carol"}, []int64{500, 300, 200}))
	uassert.Equal(t, int64(1000), l.TotalOwed(), "the realm must hold 1000 in reserve")

	got, _ := l.Withdraw("bob")
	uassert.Equal(t, int64(300), got)
	uassert.Equal(t, int64(700), l.TotalOwed(), "reserve drops by exactly what was paid")

	l.Credit("alice", 100)
	got, _ = l.Withdraw("alice")
	uassert.Equal(t, int64(600), got, "a later credit is included in one withdrawal")

	uassert.Equal(t, int64(200), l.TotalOwed())
	uassert.Equal(t, int64(900), l.TotalWithdrawn())
	uassert.Equal(t, "carol", strings.Join(l.Payees(), ","))
	uassert.True(t, l.Consistent())
}
