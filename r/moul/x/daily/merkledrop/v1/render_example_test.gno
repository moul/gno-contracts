package merkledrop

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	seed()
	print(Render(""))
	// Output:
	// # MerkleDrop v1
	//
	// A Merkle root gates an airdrop that pays real ugnot. Successor to
	// [v0](/r/moul/x/daily/merkledrop/v0), which moved no coins and whose proof scheme was
	// safe only by accident of encoding lengths.
	//
	// ## Drop
	//
	// | Field | Value |
	// |---|---|
	// | Root | `6964baa99da23b9d8c76774c6f1122b250040e29c1d75823dda15c043dc65755` |
	// | Allocations | 4 |
	// | Closes at height | never |
	// | Claimed | 0 |
	// | Paid out | 0 ugnot |
	// | Funding address | `g1jvh5ukk07dvd57fxefcp5aa29xaydxmxs7myyp` |
	//
	// ## How it differs from v0
	//
	// 1. **Domain separated leaves.** v0 hashed leaves bare and combined nodes
	//    commutatively, so an inner-node hash was also a valid leaf hash. It was not
	//    exploitable, but only because a v0 leaf preimage tops out at 61 bytes while an
	//    inner preimage is always 64. v1 tags leaves `0x00` and inner nodes `0x01`.
	// 2. **Proofs bound to a position.** v0 folded a sibling list of any length. v1
	//    carries index and total, rebuilds the tree shape, and caps the depth.
	// 3. **A settable root and a closing height.** v0's root was a `const`.
	// 4. **Real coins.** v0 kept a `uint64` ledger and moved nothing.
	//
	// ## Leaf encoding
	//
	// Reproduce this off chain to rebuild the tree:
	//
	// ```
	// leaf = "gno.land/r/moul/x/daily/merkledrop/v1|<index>|<address>|<amount>"
	// tree = Tendermint simple tree, leaf 0x00, inner 0x01
	// ```
	//
	// ## Example allocations
	//
	// Seeded at deploy so the drop can be exercised without a generator. A live drop
	// commits only a root and stores none of this.
	//
	// | # | Address | Amount | Claimed |
	// |---|---|---|---|
	// | [0](/r/moul/x/daily/merkledrop/v1:proof/0) | `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5` | 100 | no |
	// | [1](/r/moul/x/daily/merkledrop/v1:proof/1) | `g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj` | 250 | no |
	// | [2](/r/moul/x/daily/merkledrop/v1:proof/2) | `g1manfred47kzduec920z88wfr64ylksmdcedlf5` | 500 | no |
	// | [3](/r/moul/x/daily/merkledrop/v1:proof/3) | `g1sss9uxef4l6lwc0mxq8n5v0e4vqpml7c39cxq2` | 750 | no |
}

// ExampleRenderProof pins one allocation page, including its live proof.
func ExampleRenderProof() {
	seed()
	print(Render("proof/2"))
	// Output:
	// # MerkleDrop v1: allocation 2
	//
	// | Field | Value |
	// |---|---|
	// | Index | 2 |
	// | Total | 4 |
	// | Address | `g1manfred47kzduec920z88wfr64ylksmdcedlf5` |
	// | Amount | 500 ugnot |
	// | Claimed | no |
	//
	// ## Leaf
	//
	// ```
	// gno.land/r/moul/x/daily/merkledrop/v1|2|g1manfred47kzduec920z88wfr64ylksmdcedlf5|500
	// ```
	//
	// ## Proof
	//
	// ```
	// 337bb23c66f621db38e704fc2d64d27d5fa6308a333fd9d2d69c6ccd9390c056,b498260d909eee2a1b8a88524d5e4d08128aa7d8ca433468379db031976958e1
	// ```
	//
	// Only `g1manfred47kzduec920z88wfr64ylksmdcedlf5` can spend it: the address is inside the leaf, so
	// the proof verifies for no one else.
}

// ExampleRenderMissingProof pins the not-found page.
func ExampleRenderMissingProof() {
	seed()
	print(Render("proof/99"))
	// Output:
	// # MerkleDrop v1
	//
	// No allocation `99`.
}
