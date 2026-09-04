package heapdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Binary Heap
	//
	// A priority queue, demoing the [`p/moul/x/daily/heap`](/p/moul/x/daily/heap/v1) library.
	//
	// ## The workload
	//
	// | job | priority |
	// |---|---|
	// | send email | 5 |
	// | pay invoice | 1 |
	// | backup db | 3 |
	// | rotate keys | 1 |
	// | clear cache | 9 |
	//
	// ## Min-heap — lowest priority first
	//
	// | # | job | priority |
	// |---|---|---|
	// | 1 | pay invoice | 1 |
	// | 2 | rotate keys | 1 |
	// | 3 | backup db | 3 |
	// | 4 | send email | 5 |
	// | 5 | clear cache | 9 |
	//
	// ## Max-heap — highest priority first
	//
	// | # | job | priority |
	// |---|---|---|
	// | 1 | clear cache | 9 |
	// | 2 | send email | 5 |
	// | 3 | backup db | 3 |
	// | 4 | pay invoice | 1 |
	// | 5 | rotate keys | 1 |
	//
	// ## Ties
	//
	// `pay invoice` and `rotate keys` share priority 1. Both heaps pop them **oldest-first**: the tiebreak is insertion order and does *not* invert with the heap kind.
	//
	// > Without a total order, two nodes could pop equal-priority items in different sequences and render different pages — a consensus bug, not a cosmetic one.
}
