package multisetdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Multiset
	//
	// A bag that counts duplicates, demoing the [`p/moul/x/daily/multiset`](/p/moul/x/daily/multiset/v1) library.
	//
	// ## Word frequencies
	//
	// > the quick brown fox jumps over the lazy dog the fox barks and the dog barks
	//
	// `16` words, `10` distinct.
	//
	// ## `MostCommon(5)`
	//
	// | rank | word | count |
	// |---|---|---|
	// | 1 | `the` | 4 |
	// | 2 | `barks` | 2 |
	// | 3 | `dog` | 2 |
	// | 4 | `fox` | 2 |
	// | 5 | `and` | 1 |
	//
	// Note the ties. `barks`, `dog` and `fox` all occur twice and are ranked **alphabetically** — the order is count descending, then element ascending. That second key is not decoration: without it the ranking would fall back on map iteration order, which gno leaves unspecified, and two nodes could render different tables.
	//
	// ## Algebra
	//
	// With `A = {x:3, y:1}` and `B = {x:2, z:1}`:
	//
	// | op | meaning | result |
	// |---|---|---|
	// | `Union` | max of each count | `{x:3, y:1, z:1}` |
	// | `Intersect` | min, common only | `{x:2}` |
	// | `Sum` | counts added | `{x:5, y:1, z:1}` |
	//
	// ## Removal
	//
	// Starting from `{a:3}`:
	//
	// - after `Remove("a")` → `{a:2}`
	// - after `RemoveN("a", 100)` → `{}` — over-removing clears the element instead of going negative
}
