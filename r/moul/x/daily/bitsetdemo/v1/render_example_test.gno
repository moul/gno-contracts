package bitsetdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # BitSet
	//
	// A dense bit vector, demoing the [`p/moul/x/daily/bitset`](/p/moul/x/daily/bitset/v1) library.
	//
	// ## Primes under 100
	//
	// **25** set bits in 100 bits of capacity:
	//
	// `2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97`
	//
	// ## Set algebra
	//
	// | set | bits |
	// |---|---|
	// | a | `1 2 3 5 8` |
	// | b | `2 4 6 8 10` |
	// | a ∪ b | `1 2 3 4 5 6 8 10` |
	// | a ∩ b | `2 8` |
	// | a \ b | `1 3 5` |
	// | a △ b | `1 3 4 5 6 10` |
}
