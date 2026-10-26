package varint

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Append takes and returns a byte slice rather than a string, so packing a
// sequence reuses one buffer instead of copying the whole prefix per value.
// A string accumulator makes PutUvarints quadratic in the encoded size, which
// on chain is gas a caller pays to produce a result they already had.
func TestAppendReusesOneBuffer(t *testing.T) {
	buf := make([]byte, 0, 32)
	buf = AppendUvarint(buf, 300)
	buf = AppendVarint(buf, -1)
	buf = AppendUvarint(buf, 16384)
	uassert.Equal(t, "ac020180 8001"[0:0]+hex(string(buf)), "ac0201808001")

	// The same bytes the one-shot helpers produce, so the two cannot diverge.
	uassert.Equal(t, PutUvarint(300)+PutVarint(-1)+PutUvarint(16384), string(buf))
}

func TestSequenceHelpersMatchAppend(t *testing.T) {
	xs := []uint64{0, 1, 127, 128, 300, maxUint64}
	buf := []byte{}
	for _, x := range xs {
		buf = AppendUvarint(buf, x)
	}
	uassert.Equal(t, string(buf), PutUvarints(xs))

	ys := []int64{0, -1, 1, minInt64, maxInt64}
	sbuf := []byte{}
	for _, y := range ys {
		sbuf = AppendVarint(sbuf, y)
	}
	uassert.Equal(t, string(sbuf), PutVarints(ys))
}
