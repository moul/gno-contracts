package eightball

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # 🎱 Magic 8-Ball
	//
	// > ⚠️ Experimental, auto-generated with no human supervision (MCP test corpus). Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).
	//
	// Ask a yes/no question — the block height decides your fate.
	//
	// **Questions asked:** 0
	//
	// _No questions yet. Call `Ask("will it rain tomorrow?")`._
}
