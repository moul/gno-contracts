package countminsketchdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Count–Min Sketch
	//
	// Frequency estimates in fixed space, demoing the [`p/moul/x/daily/countminsketch`](/p/moul/x/daily/countminsketch/v1) library.
	//
	// ## The workload
	//
	// `195` events over `123` distinct keys: three heavy hitters and a long tail of one-offs.
	//
	// ## A generously sized sketch (1024 × 4)
	//
	// | key | true | estimate |
	// |---|---|---|
	// | `alice` | 40 | 40 |
	// | `bob` | 25 | 25 |
	// | `carol` | 10 | 10 |
	// | `user0` | 1 | 1 |
	// | `never-seen` | 0 | 0 |
	//
	// Exact here, and `never-seen` reads `0` — a **zero estimate is definitive**: that key was never added.
	//
	// ## A deliberately tiny one (8 × 2)
	//
	// Only `16` counters for `123` distinct keys, so collisions are guaranteed:
	//
	// | key | true | estimate | error |
	// |---|---|---|---|
	// | `alice` | 40 | 54 | +14 |
	// | `bob` | 25 | 39 | +14 |
	// | `carol` | 10 | 24 | +14 |
	// | `user0` | 1 | 16 | +15 |
	//
	// Every error is **positive**. That is the guarantee: the sketch may overcount, never undercount, so an estimate is an upper bound — "at most this often", never "exactly this often".
	//
	// ## Where the collisions are
	//
	// Row 0 of the tiny sketch, and the column each key lands in:
	//
	// | column | counter |
	// |---|---|
	// | 0 | 15 |
	// | 1 | 25 ← `carol` |
	// | 2 | 16 |
	// | 3 | 15 |
	// | 4 | 54 ← `alice` |
	// | 5 | 16 |
	// | 6 | 15 |
	// | 7 | 39 ← `bob` |
	//
	// Taking the **minimum** across rows is what limits the damage: an overestimate needs a collision in *every* row at once.
	//
	// ## Why bother
	//
	// | | exact map | sketch (1024 × 4) |
	// |---|---|---|
	// | storage | one entry per distinct key, unbounded | 4096 counters, fixed |
	// | answer | exact | upper bound |
	//
	// On chain the second row is the point: storage driven by user input is a liability, and a sketch sized once cannot be made to grow.
}
