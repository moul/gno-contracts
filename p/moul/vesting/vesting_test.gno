package vesting

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The real mainnet §132 term: 2026-09-12T15:00:00Z to 2028-09-12T15:00:00Z.
const (
	mainnetStart int64 = 1789225200
	mainnetEnd   int64 = 1852383600
	mainnetTerm        = mainnetEnd - mainnetStart // 63,158,400 seconds
)

func TestNewValidates(t *testing.T) {
	for _, tc := range []struct {
		name                    string
		original, start, end    int64
		typ                     Type
		wantErr                 error
	}{
		{"a real mainnet schedule", 106560000000, mainnetStart, mainnetEnd, Continuous, nil},
		{"no schedule at all", 0, 0, 0, Continuous, nil},
		{"zero original ignores the rest", 0, 99, 1, Continuous, nil},
		{"a cliff needs no start", 100, 0, mainnetEnd, Delayed, nil},
		{"negative original", -1, 0, 10, Continuous, ErrNegativeOriginal},
		{"end not positive", 100, 0, 0, Continuous, ErrEndNotPositive},
		{"negative start", 100, -1, 10, Continuous, ErrNegativeStart},
		{"start equal to end", 100, 10, 10, Continuous, ErrStartAfterEnd},
		{"start after end", 100, 11, 10, Continuous, ErrStartAfterEnd},
	} {
		_, err := New(tc.original, tc.start, tc.end, tc.typ)
		if tc.wantErr == nil {
			uassert.NoError(t, err, tc.name)
			continue
		}
		uassert.ErrorIs(t, err, tc.wantErr, tc.name)
	}
}

// TestVestedCurve pins the continuous curve at its boundaries and midpoint.
func TestVestedCurve(t *testing.T) {
	s, err := New(1000, 100, 200, Continuous)
	uassert.NoError(t, err)

	for _, tc := range []struct {
		now, want int64
	}{
		{0, 0},      // long before
		{100, 0},    // at the start
		{125, 250},  // a quarter in
		{150, 500},  // halfway
		{199, 990},  // one tick short
		{200, 1000}, // exactly at the end
		{1 << 40, 1000},
	} {
		uassert.Equal(t, tc.want, s.Vested(tc.now))
		uassert.Equal(t, 1000-tc.want, s.Locked(tc.now))
	}
}

// TestDelayedIsACliff: Start is ignored and nothing vests until End.
func TestDelayedIsACliff(t *testing.T) {
	s, err := New(1000, 0, 200, Delayed)
	uassert.NoError(t, err)

	uassert.Equal(t, int64(0), s.Vested(0))
	uassert.Equal(t, int64(0), s.Vested(199))
	uassert.Equal(t, int64(1000), s.Vested(200))
	uassert.Equal(t, int64(1000), s.Vested(1000))
	uassert.Equal(t, int64(1000), s.Locked(199))
	uassert.Equal(t, int64(0), s.Locked(200))
}

func TestZeroScheduleLocksNothing(t *testing.T) {
	var s Schedule
	uassert.True(t, s.IsZero())
	uassert.Equal(t, int64(0), s.Vested(12345))
	uassert.Equal(t, int64(0), s.Locked(12345))
	uassert.Equal(t, int64(999), s.Spendable(999, 12345))
	uassert.Equal(t, int64(1000), s.PermilleVested(12345))
}

// TestRoundsDown is the direction that matters: reporting one ugnot more than
// the chain will move turns a page into a lie a user acts on.
func TestRoundsDown(t *testing.T) {
	s, err := New(10, 0, 3, Continuous) // 10/3 per second, never exact
	uassert.NoError(t, err)

	uassert.Equal(t, int64(3), s.Vested(1)) // 3.33 -> 3
	uassert.Equal(t, int64(6), s.Vested(2)) // 6.66 -> 6
	uassert.Equal(t, int64(10), s.Vested(3))
}

// TestNoOverflowAtChainScale is the whole reason this package exists rather
// than reusing p/moul/x/daily/cliffvesting, which computes total*elapsed in
// plain int64. Over the mainnet term that wraps above 146,036 GNOT: the
// largest genesis grant is 318,720,000 GNOT, and the naive form returns a
// NEGATIVE vested amount for it.
func TestNoOverflowAtChainScale(t *testing.T) {
	const largestGrant int64 = 318720000000000 // 318,720,000 GNOT in ugnot

	s, err := New(largestGrant, mainnetStart, mainnetEnd, Continuous)
	uassert.NoError(t, err)

	// Exactly halfway through the term: the answer is half the grant, and the
	// naive int64 product would have wrapped long before here.
	half := s.Vested(mainnetStart + mainnetTerm/2)
	uassert.Equal(t, largestGrant/2, half)
	uassert.True(t, half > 0, "a wrapped product reports a negative amount")

	// Every point on the curve stays inside [0, Original], monotonically.
	prev := int64(0)
	for i := int64(0); i <= 16; i++ {
		got := s.Vested(mainnetStart + mainnetTerm*i/16)
		uassert.True(t, got >= prev, "vested went backwards")
		uassert.True(t, got >= 0 && got <= largestGrant, "vested left its bounds")
		prev = got
	}
	uassert.Equal(t, largestGrant, prev)
}

// TestTotalSupplyGrantDoesNotOverflow takes the ceiling to the whole supply,
// which is the largest schedule the chain could ever hold.
func TestTotalSupplyGrantDoesNotOverflow(t *testing.T) {
	const supply int64 = 1332999998328067 // total genesis allocation, ugnot

	s, err := New(supply, mainnetStart, mainnetEnd, Continuous)
	uassert.NoError(t, err)
	uassert.Equal(t, supply/2, s.Vested(mainnetStart+mainnetTerm/2))
	uassert.Equal(t, supply, s.Vested(mainnetEnd))
}

// TestSpendable is the number the page exists to show.
func TestSpendable(t *testing.T) {
	s, err := New(1000, 100, 200, Continuous)
	uassert.NoError(t, err)

	// Balance above the grant: the surplus is spendable from the start.
	uassert.Equal(t, int64(200), s.Spendable(1200, 100)) // 1200 - 1000 locked
	uassert.Equal(t, int64(700), s.Spendable(1200, 150)) // 1200 - 500 locked
	uassert.Equal(t, int64(1200), s.Spendable(1200, 200))

	// Spent down below what is still locked: nothing moves, and the answer is
	// zero rather than a negative number.
	uassert.Equal(t, int64(0), s.Spendable(400, 150))
	uassert.Equal(t, int64(0), s.Spendable(500, 150)) // exactly locked
	uassert.Equal(t, int64(1), s.Spendable(501, 150))

	uassert.Equal(t, int64(0), s.Spendable(0, 150))
	uassert.Equal(t, int64(0), s.Spendable(-5, 150))
}

// TestMoulsOwnAccount walks the real genesis row through the real schedule,
// as a regression on the arithmetic the page will print.
//
// Genesis row, from the allocation sheet that built mainnet:
//
//	g1manfred47kzduec920z88wfr64ylksmdcedlf5=111000000000ugnot;
//	  vesting=106560000000ugnot,1789225200,1852383600
func TestMoulsOwnAccount(t *testing.T) {
	const (
		genesisBalance int64 = 111000000000
		grant          int64 = 106560000000
	)
	s, err := New(grant, mainnetStart, mainnetEnd, Continuous)
	uassert.NoError(t, err)

	// At genesis: the 4% that never vested is immediately spendable.
	uassert.Equal(t, int64(0), s.Vested(mainnetStart))
	uassert.Equal(t, genesisBalance-grant, s.Spendable(genesisBalance, mainnetStart))
	uassert.Equal(t, int64(4440000000), s.Spendable(genesisBalance, mainnetStart))

	// Halfway: half the grant has vested.
	uassert.Equal(t, grant/2, s.Vested(mainnetStart+mainnetTerm/2))

	// At the end: everything moves, whatever the balance is by then.
	uassert.Equal(t, int64(0), s.Locked(mainnetEnd))
	uassert.Equal(t, genesisBalance, s.Spendable(genesisBalance, mainnetEnd))
}

func TestPermilleVested(t *testing.T) {
	s, err := New(1000, 100, 200, Continuous)
	uassert.NoError(t, err)

	uassert.Equal(t, int64(0), s.PermilleVested(100))
	uassert.Equal(t, int64(250), s.PermilleVested(125))
	uassert.Equal(t, int64(1000), s.PermilleVested(200))

	// Rounds down, like everything else here.
	s2, err := New(3, 0, 300, Continuous)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(333), s2.PermilleVested(100)) // 1/3 of 3 = 1 -> 333
}

func TestRemainingSeconds(t *testing.T) {
	s, err := New(1000, 100, 200, Continuous)
	uassert.NoError(t, err)

	uassert.Equal(t, int64(100), s.RemainingSeconds(100))
	uassert.Equal(t, int64(1), s.RemainingSeconds(199))
	uassert.Equal(t, int64(0), s.RemainingSeconds(200))
	uassert.Equal(t, int64(0), s.RemainingSeconds(10000))

	var zero Schedule
	uassert.Equal(t, int64(0), zero.RemainingSeconds(0))
}

func TestTypeString(t *testing.T) {
	uassert.Equal(t, "continuous", Continuous.String())
	uassert.Equal(t, "delayed", Delayed.String())
}
