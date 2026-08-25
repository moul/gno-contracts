package merkledrop

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # MerkleDrop
	//
	// A fixed Merkle root gates a one-per-address airdrop. Prove your allocation with `Claim(amount, proof)`.
	//
	// ## Root
	//
	// `0d00b73577019dc92924f0ae001d3e1839d51fb358adda2ad1510c39eb82b13f`
	//
	// ## Stats
	//
	// - Distinct claimers: 0
	// - Total claimed: 0
	//
	// ## Claimers
	//
	// _No claims yet._
}
