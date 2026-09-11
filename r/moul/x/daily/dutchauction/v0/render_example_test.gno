package dutchauction

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Dutch Auction
	//
	// A price that only ever falls. List an item high; it decays block by block toward a floor; the first `Buy` call wins it at whatever the price is at that instant. Real ugnot, escrowed by the chain and paid straight to the seller — overpayment is refunded automatically.
	//
	// - **Total listed:** 0
	// - **Total sold:** 0
	// - **Total volume:** 0 ugnot
	// - **Current height:** 123
	//
	// _No auctions yet — call `List` to open one._
}
