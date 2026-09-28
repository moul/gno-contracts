package storagecost

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRefund(t *testing.T) {
	tests := []struct {
		name  string
		bytes int64
		price int64
		want  int64
	}{
		{"one byte at the default price", 1, DefaultStoragePrice, 100},
		{"the measured reap", 17835, DefaultStoragePrice, 1783500},
		{"the measured compact", 830, DefaultStoragePrice, 83000},
		{"zero bytes", 0, DefaultStoragePrice, 0},
		{"negative bytes are not a credit", -100, DefaultStoragePrice, 0},
		{"a free chain refunds nothing", 1000, 0, 0},
		{"a ten-fold price rise", 1000, 1000, 1000000},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			uassert.Equal(t, tt.want, Refund(tt.bytes, tt.price))
		})
	}
}

func TestBreakEvenBytes(t *testing.T) {
	tests := []struct {
		name string
		fee  int64
		want int64
	}{
		// A 2.6M gas call at the floor costs 2,600 ugnot, so 26 bytes.
		{"the canonical 2.6M gas call", 2600, 26},
		{"rounds up, never down", 101, 2},
		{"exactly one byte", 100, 1},
		{"a fee below one byte still needs a byte", 1, 1},
		{"no fee, no threshold", 0, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := BreakEvenBytes(tt.fee, DefaultStoragePrice)
			uassert.Equal(t, tt.want, got)
			// The definition: this many bytes covers the fee, one fewer does not.
			if tt.want > 0 {
				uassert.True(t, Refund(got, DefaultStoragePrice) >= tt.fee)
				uassert.False(t, Refund(got-1, DefaultStoragePrice) >= tt.fee)
			}
		})
	}
	uassert.Equal(t, int64(0), BreakEvenBytes(1000, 0))
}

func TestGasFee(t *testing.T) {
	// The floor mainnet has actually accepted: 1 ugnot per 1000 gas.
	uassert.Equal(t, int64(5000), FloorGasFee(5_000_000))
	uassert.Equal(t, int64(2500), FloorGasFee(2_500_000))
	// Rounds up, so a fee is never short.
	uassert.Equal(t, int64(1), FloorGasFee(1))
	uassert.Equal(t, int64(0), FloorGasFee(0))
	// The harness price used in the measurements, 1.2 ugnot per gas.
	uassert.Equal(t, int64(6_000_000), GasFee(5_000_000, 12, 10))
	uassert.Equal(t, int64(0), GasFee(5_000_000, 0, 10))
	uassert.Equal(t, int64(0), GasFee(5_000_000, 1, 0))
}

func TestEvaluateReproducesTheMeasuredReap(t *testing.T) {
	// The measured run: 17,835 bytes freed by a call that used 4,120,876 gas,
	// so gas_wanted 5,000,000 at the floor. Net +1,778,500 ugnot.
	q := EvaluateAtFloor(17835, 5_000_000)
	uassert.Equal(t, int64(1783500), q.Refund)
	uassert.Equal(t, int64(5000), q.Fee)
	uassert.Equal(t, int64(1778500), q.Net)
	uassert.Equal(t, int64(50), q.BreakEven)
	uassert.True(t, q.Worth())
}

func TestEvaluateReproducesTheMeasuredCompact(t *testing.T) {
	q := EvaluateAtFloor(830, 2_500_000)
	uassert.Equal(t, int64(83000), q.Refund)
	uassert.Equal(t, int64(2500), q.Fee)
	uassert.Equal(t, int64(80500), q.Net)
	uassert.True(t, q.Worth())
}

func TestEvaluateAtTheHarnessPriceIsALoss(t *testing.T) {
	// The same reap priced at 1.2 ugnot/gas, 1200x the floor, loses money.
	// This is why the gas price cannot be baked into a contract.
	q := Evaluate(17835, DefaultStoragePrice, 5_000_000, 12, 10)
	uassert.Equal(t, int64(6_000_000), q.Fee)
	uassert.False(t, q.Worth())
	uassert.True(t, q.Net < 0)
}

func TestQuoteString(t *testing.T) {
	worth := EvaluateAtFloor(17835, 5_000_000)
	uassert.Equal(t,
		"17835 bytes, refunds 1.7835 GNOT against 0.005 GNOT of gas, break-even 50 bytes: worth 1.7785 GNOT",
		worth.String())

	loss := Evaluate(10, DefaultStoragePrice, 5_000_000, 12, 10)
	uassert.Equal(t,
		"10 bytes, refunds 0.001 GNOT against 6 GNOT of gas, break-even 60000 bytes: not worth it yet",
		loss.String())
}

func TestFormatGNOT(t *testing.T) {
	tests := []struct {
		amount int64
		want   string
	}{
		{0, "0 GNOT"},
		{1, "0.000001 GNOT"},
		{100, "0.0001 GNOT"},
		{1_000_000, "1 GNOT"},
		{1_500_000, "1.5 GNOT"},
		{1_783_500, "1.7835 GNOT"},
		{978_743_800, "978.7438 GNOT"},
		{-2_100, "-0.0021 GNOT"},
		{1_000_001, "1.000001 GNOT"},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, FormatGNOT(tt.amount))
	}
}

func TestEstimateBytes(t *testing.T) {
	// Measured: a 1,024-byte payload occupied 1,898 bytes of realm state.
	uassert.Equal(t, int64(1894), EstimateBytes(1024))
	uassert.Equal(t, int64(0), EstimateBytes(0))
	uassert.Equal(t, int64(0), EstimateBytes(-5))
	// Monotonic, which is all a bounty estimate really needs.
	uassert.True(t, EstimateBytes(2048) > EstimateBytes(1024))
}

// TestFormatGNOTIsTotal pins what v0 could not do. v0 negated in int64, so at
// math.MinInt64 both halves kept a sign and it returned
// "--9223372036854.-775808 GNOT". Delegating to kit/num is the fix; this
// asserts the contract rather than the delegation.
func TestFormatGNOTIsTotal(t *testing.T) {
	const minInt64 = -9223372036854775808
	uassert.Equal(t, "-9223372036854.775808 GNOT", FormatGNOT(minInt64))
	uassert.Equal(t, "-1.5 GNOT", FormatGNOT(-1500000))
	uassert.Equal(t, "-0.000001 GNOT", FormatGNOT(-1))
	uassert.Equal(t, "1.5 GNOT", FormatGNOT(1500000))
	uassert.Equal(t, "0 GNOT", FormatGNOT(0))
}

func TestEstimateNodes(t *testing.T) {
	cases := []struct {
		name  string
		nodes int64
		want  int64
	}{
		{"none", 0, 0},
		{"negative is not an error", -5, 0},
		// The mainnet measurement this constant comes from: compacting a
		// drained 8-node board returned 6,848 bytes.
		{"the mainnet sample", 8, 6848},
		// And the local harness, which agreed to the byte.
		{"the local harness sample", 31, 26536},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, EstimateNodes(tc.nodes), tc.name)
	}
}

// TestEstimateNodesBeatsEstimateBytesOnTheCaseThatBurnedUs pins the reason
// EstimateNodes exists, not just what it computes.
//
// A realm advertised a bounty by running the payload length of five small
// entries through EstimateBytes and got 481 bytes. Reaping and compacting them
// actually returned 11,972. The payload path cannot see either the per-entry
// floor or the container, and no existing test could catch that because they
// all fed EstimateBytes the 1,024-byte payloads its ratio was measured on.
func TestEstimateNodesBeatsEstimateBytesOnTheCaseThatBurnedUs(t *testing.T) {
	const payload = 8 + 231 + 7 + 5 + 9 // the five note bodies, 260 bytes
	const reallyFreed = 11972

	guess := EstimateBytes(payload)
	uassert.True(t, guess*20 < reallyFreed,
		"EstimateBytes is still supposed to be the bad one here")

	// The container half is the part that is countable, and counting it gets
	// most of the way there on its own: 8 nodes were the larger share.
	counted := EstimateNodes(8)
	uassert.True(t, counted > guess*10,
		"counting nodes should dominate guessing from payload")
	uassert.True(t, counted <= reallyFreed,
		"counting nodes must never over-advertise")
}
