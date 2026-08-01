package erc1155

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # ERC-1155 Multi-Token
	//
	// A single realm holding many fungible token ids. Balances are keyed by `(owner, id)`.
	//
	// ## Balances
	//
	// _No balances yet. Call `Mint` to create tokens._
	//
	// ## Supply per ID
	//
	// _No tokens minted._
}
