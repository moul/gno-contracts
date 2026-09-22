package provable

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	seed()
	print(Render(""))
	// Output:
	// # provable
	//
	// What gno.land can and cannot prove about itself, demonstrated rather than asserted.
	//
	// ## The log
	//
	// An append-only Merkle mountain range. Appending costs O(log n) hashes and never rebuilds.
	//
	// | Field | Value |
	// |---|---|
	// | Entries | 3 / 512 |
	// | Stored hashes | 4 |
	// | Peaks | 2 |
	// | Root | `c9d22dd237c668944fde619edb56cc1bee0e988b03ac08694f6d3aba440c0776` |
	//
	// This root is also the Tendermint simple-tree root over the same entries, so any
	// Tendermint verifier accepts it. `Verify` and `VerifyFixed` check the two proof
	// encodings against it.
	//
	// ## What the chain can prove
	//
	// `gno.land/pkg/gnoland/app.go` mounts exactly two stores. One is IAVL and merkleized,
	// the other is a plain dbadapter whose `Commit` is documented as *"Always returns a zero
	// commitID, as dbadapter store doesn't merkleize"*.
	//
	// | Data | Store | Provable against the app hash |
	// |---|---|---|
	// | Package source | iavl | yes |
	// | Account balances | iavl | yes |
	// | Escaped object hashes (cross-realm) | iavl | yes, the hash only |
	// | Realm objects, types, realm metadata | base | **no** |
	// | **This log** | base | **no** |
	//
	// ## What that means here
	//
	// A proof from this realm says *this entry is consistent with the root this realm
	// published*. It cannot say *this root is the chain's own*, for two independent reasons:
	//
	// 1. Realm state is not merkleized, so there is no state proof to produce.
	// 2. `chain/runtime` exposes `ChainID`, `ChainDomain`, `ChainHeight` and `GetSessionInfo`
	//    and nothing else. No app hash, no block hash, no header. A realm has no trusted
	//    root to check anything against.
	//
	// Anything built on Merkle proofs in a gno realm is trust-minimised relative to a
	// committed root, never trustless. Saying otherwise would be the interesting-sounding
	// half of a true story.
	//
	// ## Entries
	//
	// | # | Entry |
	// |---|---|
	// | [0](/r/moul/x/provable/v0:entry/0) | genesis of this log |
	// | [1](/r/moul/x/provable/v0:entry/1) | a second commitment |
	// | [2](/r/moul/x/provable/v0:entry/2) | a third commitment |
}

// ExampleRenderEntry pins the per-entry page, including a live proof.
func ExampleRenderEntry() {
	seed()
	print(Render("entry/1"))
	// Output:
	// # provable: entry 1
	//
	// ```
	// a second commitment
	// ```
	//
	// ## Inclusion proof
	//
	// | Field | Value |
	// |---|---|
	// | Index | 1 |
	// | Total | 3 |
	// | Path | `8f88aaa49b43fc28f266ea6b4f18d865933cad3584b59f162b8ce55edd8263fc` |
	// | Before | `-` |
	// | After | `495f0f3042890e970ad8344ae78ff490806c2b8403282d518e8112044bc43827` |
	// | Root | `c9d22dd237c668944fde619edb56cc1bee0e988b03ac08694f6d3aba440c0776` |
	//
	// Valid against that root only. The next `Append` moves it.
}

// ExampleRenderMissingEntry pins the not-found page.
func ExampleRenderMissingEntry() {
	seed()
	print(Render("entry/99"))
	// Output:
	// # provable
	//
	// No entry `99`.
}
