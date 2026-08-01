package erc721

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # Gno NFT (GNFT)
	//
	// **Total supply:** 0
	//
	// _No tokens minted yet._
}
