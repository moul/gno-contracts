package intervalsetdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Interval set
	//
	// Half-open ranges kept sorted, disjoint and coalesced, demoing the [`p/moul/x/daily/intervalset`](/p/moul/x/daily/intervalset/v0) library.
	//
	// A realm collecting booked slots, written in the order the bookings arrived. Watch the **spans** column: it tracks the shape of the data, not the number of writes.
	//
	// | # | write | spans | covered | the set |
	// | --- | --- | --- | --- | --- |
	// | 1 | `Add(100, 150)` | 1 | 50 | `[100,150)` |
	// | 2 | `Add(300, 400)` | 2 | 150 | `[100,150) [300,400)` |
	// | 3 | `Add(140, 210)` | 2 | 210 | `[100,210) [300,400)` |
	// | 4 | `Add(210, 260)` | 2 | 260 | `[100,260) [300,400)` |
	// | 5 | `Add(260, 300)` | 1 | 300 | `[100,400)` |
	// | 6 | `Add(500, 520)` | 2 | 320 | `[100,400) [500,520)` |
	// | 7 | `Add(505, 515)` | 2 | 320 | `[100,400) [500,520)` |
	// | 8 | `Remove(180, 200)` | 3 | 300 | `[100,180) [200,400) [500,520)` |
	// | 9 | `Add(180, 200)` | 2 | 320 | `[100,400) [500,520)` |
	//
	// Nine writes, two spans. A slice of pairs appended to on every write would hold nine, forever, and this is on chain: storage is paid for once and kept for good.
	//
	// Row 4 is the one worth staring at. `[210,260)` does not overlap `[100,210)`, it only touches it, and they still merge. Row 7 is the opposite case: `[505,515)` is already inside `[500,520)`, so it is not a write at all. Row 8 cancels from the middle, which is the only operation here that can raise the span count.
	//
	// ## Half-open, and why it matters here
	//
	// A span is `[Lo, Hi)`: `Lo` is covered and `Hi` is not. That is exactly what lets two touching ranges merge without overlapping, and it is the detail callers get wrong.
	//
	// | query | answer | why |
	// | --- | --- | --- |
	// | `Contains(99)` | no | outside every span |
	// | `Contains(100)` | yes | `Lo` of a span, and `Lo` is covered |
	// | `Contains(209)` | yes | inside `[100,400)` |
	// | `Contains(210)` | yes | inside `[100,400)` |
	// | `Contains(400)` | no | `Hi` of a span, and `Hi` is not |
	// | `Contains(505)` | yes | inside `[500,520)` |
	//
	// ## Asking about a range, not a point
	//
	// | query | answer | meaning |
	// | --- | --- | --- |
	// | `Covers(120, 180)` | yes | entirely inside one span |
	// | `Covers(380, 420)` | no | runs off the end of its span |
	// | `Covers(100, 400)` | yes | exactly the span: `400` is excluded from both |
	// | `Overlaps(380, 420)` | yes | shares `380..399` with the set |
	// | `Overlaps(400, 500)` | no | exactly the gap between the two spans |
	//
	// `Covers` and `Overlaps` are the two questions a realm actually asks (may this booking go ahead, does it clash with anything), and they are different questions. Both are `O(log n)` by binary search over the spans, so a `Render` can call them freely.
	//
	// ## What the obvious implementation gets wrong
	//
	// |  | a slice of pairs | this |
	// | --- | --- | --- |
	// | storage after the script above | 9 entries | 2 spans |
	// | growth | with every write, forever | with the shape of the data |
	// | is this point covered | `O(n)` scan, slower on every write | `O(log n)` |
	// | total covered length | double-counts every overlap | `320`, counted once |
	//
	// The last row is the one that costs money: a realm billing for covered time against an uncoalesced list charges twice for every overlap, and nothing about the list looks wrong.
}
