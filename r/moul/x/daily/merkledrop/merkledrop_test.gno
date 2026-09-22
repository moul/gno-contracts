package merkledrop

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// recipients + proofs generated off-chain with the exact leaf/node scheme in
// merkledrop.gno, over the same four allocations, resolving to merkleRoot.
type alloc struct {
	addr   address
	amount uint64
	proof  string
}

var fixtures = []alloc{
	{
		address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"), 100,
		"dd57b89301cc6f1aa5593eb0881cefefcf2ef85ce7629dab61ad0528c301bce9,7c1352bec23bc53d2b573373623cff31174a738de9a257906866c9b598d01253",
	},
	{
		address("g1sss9uxef4l6lwc0mxq8n5v0e4vqpml7c39cxq2"), 250,
		"0df511d09bf004329ac648f5d029d192cedb7bac0aa04105be45ae9e3f727160,7c1352bec23bc53d2b573373623cff31174a738de9a257906866c9b598d01253",
	},
	{
		address("g1manfred47kzduec920z88wfr64ylksmdcedar8"), 500,
		"d71269d6916f8f2b80ea94d9fa949d2469f7d8160422c9512162ca6432de8aad,8f128549b4eb5751c7cd8e0ddfb7c5533266f4b5d5ec81b7a5b00dc23671e87e",
	},
	{
		address("g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj"), 750,
		"7f9354d47613efae448a8f78f8aacb973532c91d7eaf4195bf2ba86f22b27c45,8f128549b4eb5751c7cd8e0ddfb7c5533266f4b5d5ec81b7a5b00dc23671e87e",
	},
}

func TestVerifyValidProofs(t *testing.T) {
	for _, f := range fixtures {
		uassert.True(t, Verify(f.addr, f.amount, f.proof),
			"expected valid proof for "+f.addr.String())
	}
}

func TestVerifyRejectsWrongAmount(t *testing.T) {
	f := fixtures[0]
	uassert.False(t, Verify(f.addr, f.amount+1, f.proof),
		"tampered amount must not verify")
}

func TestVerifyRejectsWrongAddress(t *testing.T) {
	f := fixtures[0]
	other := fixtures[1].addr
	uassert.False(t, Verify(other, f.amount, f.proof),
		"proof bound to a different address must not verify")
}

func TestVerifyRejectsEmptyProof(t *testing.T) {
	f := fixtures[0]
	uassert.False(t, Verify(f.addr, f.amount, ""),
		"empty proof cannot reach a multi-leaf root")
}

func TestParseProofRoundTrips(t *testing.T) {
	nodes := parseProof(fixtures[0].proof)
	uassert.Equal(t, 2, len(nodes))
	uassert.Equal(t, 32, len(nodes[0]))
	uassert.Equal(t, 32, len(nodes[1]))
}

func TestParseProofEmpty(t *testing.T) {
	uassert.Equal(t, 0, len(parseProof("")))
	uassert.Equal(t, 0, len(parseProof("  ")))
}

func TestHashPairCommutative(t *testing.T) {
	a := leaf(fixtures[0].addr, fixtures[0].amount)
	b := leaf(fixtures[1].addr, fixtures[1].amount)
	left := hashPair(a, b)
	right := hashPair(b, a)
	uassert.Equal(t, len(left), len(right))
	for i := range left {
		uassert.Equal(t, left[i], right[i])
	}
}
