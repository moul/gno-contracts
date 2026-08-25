package timecapsule

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # ⏳ Time Capsule Guestbook
	//
	// Leave a message for the future. It stays sealed until its unlock block height, then anyone can read it — call `Leave(message, delayBlocks)`.
	//
	// 0 capsule(s) total · 0 unlocked · 0 still sealed.
	//
	// ## Unlocked messages
	//
	// _None yet. Be the first to leave one that will open later._
}
