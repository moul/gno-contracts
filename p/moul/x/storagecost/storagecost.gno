// Package storagecost answers one question: is it worth paying gas to delete
// on-chain state?
//
// On gno.land every byte of realm state locks GNOT, and the lock is refunded
// to whoever signs the transaction that frees the byte. Deleting state is
// therefore paid work, and whether a given deletion pays depends on two prices
// that move independently: the storage price, a chain parameter, and the gas
// price of the day. A contract cannot know the second one, so it cannot decide
// on its own behalf whether to compact, reindex or reap. It can only publish
// the size of the prize and let a caller do the arithmetic.
//
// This package is that arithmetic. It is pure integer maths with no chain
// imports, so a realm can call it inside a Render and an off-chain bot can
// reuse the identical formula.
//
// The single fact worth remembering is the ratio. One byte freed refunds 100
// ugnot, and at the lowest gas price mainnet has actually accepted one ugnot
// buys 1000 gas. So a byte is worth 100,000 gas, and any deletion costing less
// than that per byte pays for itself.
//
// Demo realm: gno.land/r/moul/x/reaper/v0.
package storagecost

import "gno.land/p/nt/ufmt/v0"

const (
	// DefaultStoragePrice is the ugnot locked per byte of realm state, the
	// default of the chain's vm:p:storage_price parameter. It is governance
	// settable, so read it from the chain rather than trusting this constant
	// when real money depends on the answer.
	DefaultStoragePrice int64 = 100

	// GasPerUgnotFloor is how much gas one ugnot buys at the lowest gas price
	// mainnet has been observed to accept, 0.001 ugnot per gas. It is a floor,
	// not a promise: the fee a node requires tracks gas_wanted, so asking for
	// more headroom raises the fee proportionally.
	GasPerUgnotFloor int64 = 1000

	// payloadOverheadNum/payloadOverheadDen approximate what a payload really
	// costs once the realm has wrapped it in an object. Measured at 1.85x: ten
	// 1,024-byte strings in a realm slice cost 18,984 bytes of state, 1,898
	// each. It is an estimate and nothing more. The authoritative number is
	// the chain's own, from the vm/qstorage query or a StorageDepositEvent.
	payloadOverheadNum int64 = 185
	payloadOverheadDen int64 = 100

	ugnotPerGNOT int64 = 1_000_000
)

// Refund is the deposit returned for freeing bytes at the given price per
// byte. Returns 0 for non-positive inputs rather than panicking, so a Render
// on a realm with no state still works.
func Refund(bytes, pricePerByte int64) int64 {
	if bytes <= 0 || pricePerByte <= 0 {
		return 0
	}
	return bytes * pricePerByte
}

// BreakEvenBytes is the fewest bytes whose refund covers a fee: the point
// where a cleanup stops costing money and starts making it. Below this many
// bytes the transaction is charity.
func BreakEvenBytes(feeUgnot, pricePerByte int64) int64 {
	if pricePerByte <= 0 {
		return 0
	}
	if feeUgnot <= 0 {
		return 0
	}
	// Round up: freeing exactly feeUgnot/pricePerByte bytes must cover the fee.
	return (feeUgnot + pricePerByte - 1) / pricePerByte
}

// GasFee is the fee a transaction asking for gasWanted must pay at a gas price
// of num/den ugnot per gas, rounded up.
//
// The fee tracks gas_wanted rather than gas_used, so unused headroom is paid
// for. Pass the ceiling you will actually put in the transaction, not what you
// expect to burn.
func GasFee(gasWanted, num, den int64) int64 {
	if gasWanted <= 0 || num <= 0 || den <= 0 {
		return 0
	}
	return (gasWanted*num + den - 1) / den
}

// FloorGasFee is GasFee at the lowest gas price mainnet has accepted.
func FloorGasFee(gasWanted int64) int64 {
	return GasFee(gasWanted, 1, GasPerUgnotFloor)
}

// EstimateBytes guesses the realm state a payload of this many bytes will
// occupy, applying the measured object overhead.
//
// It is for sizing a bounty in a Render, where being within a factor of two
// beats reporting the raw payload length. Never settle an accounting question
// with it.
func EstimateBytes(payloadBytes int64) int64 {
	if payloadBytes <= 0 {
		return 0
	}
	return payloadBytes * payloadOverheadNum / payloadOverheadDen
}

// Quote is a complete answer for one candidate cleanup.
type Quote struct {
	Bytes     int64 // bytes the cleanup would free
	Refund    int64 // ugnot returned for them
	Fee       int64 // ugnot the transaction will cost
	Net       int64 // Refund - Fee; negative means it costs more than it pays
	BreakEven int64 // bytes needed to cover Fee
}

// Worth reports whether the cleanup pays for itself.
func (q Quote) Worth() bool { return q.Net > 0 }

// String renders the quote as one line of markdown-safe text, for a Render.
func (q Quote) String() string {
	verdict := "not worth it yet"
	if q.Worth() {
		verdict = "worth " + FormatGNOT(q.Net)
	}
	return ufmt.Sprintf(
		"%d bytes, refunds %s against %s of gas, break-even %d bytes: %s",
		q.Bytes, FormatGNOT(q.Refund), FormatGNOT(q.Fee), q.BreakEven, verdict,
	)
}

// Evaluate prices one cleanup: freeing bytes in a transaction asking for
// gasWanted, at a storage price of pricePerByte and a gas price of num/den
// ugnot per gas.
func Evaluate(bytes, pricePerByte, gasWanted, num, den int64) Quote {
	fee := GasFee(gasWanted, num, den)
	refund := Refund(bytes, pricePerByte)
	return Quote{
		Bytes:     bytes,
		Refund:    refund,
		Fee:       fee,
		Net:       refund - fee,
		BreakEven: BreakEvenBytes(fee, pricePerByte),
	}
}

// EvaluateAtFloor is Evaluate at the default storage price and the floor gas
// price: the best case, and the one to quote when advertising a bounty.
func EvaluateAtFloor(bytes, gasWanted int64) Quote {
	return Evaluate(bytes, DefaultStoragePrice, gasWanted, 1, GasPerUgnotFloor)
}

// FormatGNOT renders ugnot as GNOT with six decimal places and trailing zeros
// trimmed, because a bounty shown in ugnot is unreadable and gno has no
// floats.
func FormatGNOT(amount int64) string {
	neg := amount < 0
	if neg {
		amount = -amount
	}
	whole := amount / ugnotPerGNOT
	frac := amount % ugnotPerGNOT

	out := ufmt.Sprintf("%d", whole)
	if frac != 0 {
		// Left-pad the fraction to six digits, then trim trailing zeros.
		digits := ufmt.Sprintf("%d", frac)
		for len(digits) < 6 {
			digits = "0" + digits
		}
		for len(digits) > 1 && digits[len(digits)-1] == '0' {
			digits = digits[:len(digits)-1]
		}
		out += "." + digits
	}
	if neg {
		out = "-" + out
	}
	return out + " GNOT"
}
