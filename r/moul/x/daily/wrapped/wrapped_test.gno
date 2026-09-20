package wrapped

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestCanDebit(t *testing.T) {
	uassert.True(t, canDebit(100, 40), "bal covers amount")
	uassert.True(t, canDebit(50, 50), "exact balance is debitable")
	uassert.False(t, canDebit(10, 20), "amount exceeds balance")
	uassert.False(t, canDebit(100, 0), "zero amount is never debitable")
	uassert.False(t, canDebit(0, 1), "empty balance cannot be debited")
}

func TestFormatUnits(t *testing.T) {
	uassert.Equal(t, "0", formatUnits(0))
	uassert.Equal(t, "1", formatUnits(1))
	uassert.Equal(t, "1000000", formatUnits(1_000_000))
}
