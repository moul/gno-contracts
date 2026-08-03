package englishauction

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # English Auction
	//
	// Ascending-bid auctions. Start one, outbid others, and End it after its block deadline to award the item to the top bidder.
	//
	// _No auctions yet. Call `Start` to open one._
}
