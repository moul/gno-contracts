package bidimapdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Bidirectional Map
	//
	// Unique in both directions, demoing the [`p/moul/x/daily/bidimap`](/p/moul/x/daily/bidimap/v1) library.
	//
	// ## Roles
	//
	// | person | role |
	// |---|---|
	// | `alice` | `admin` |
	// | `bob` | `auditor` |
	// | `carol` | `treasurer` |
	//
	// ## Both directions are O(1)
	//
	// - `Get("bob")` → `auditor`
	// - `GetKey("treasurer")` → `carol` — the reverse index, not a scan
	//
	// ## Displacing a binding
	//
	// Both sides are unique, so giving `alice` the `auditor` role cannot simply be written — `bob` already holds it, and `alice` already holds `admin`. `Put` **replaces**, and reports what it displaced:
	//
	// | displaced key | displaced value |
	// |---|---|
	// | `alice` | `admin` |
	// | `bob` | `auditor` |
	//
	// | person | role |
	// |---|---|
	// | `alice` | `auditor` |
	// | `carol` | `treasurer` |
	//
	// `bob` is now unassigned and the `admin` role is vacant — one call, both indexes still agreeing.
	//
	// ## Refusing instead
	//
	// `PutUnique` makes the other choice: it declines rather than displace.
	//
	// - `PutUnique("dave", "auditor")` → `false` — the role is taken
	// - `PutUnique("dave", "secretary")` → `true` — both sides free
	//
	// | person | role |
	// |---|---|
	// | `alice` | `auditor` |
	// | `carol` | `treasurer` |
	// | `dave` | `secretary` |
	//
	// > Keys come back **sorted**, never in map order: gno map iteration order is unspecified, and a page built from one can differ between nodes — a consensus bug, not a cosmetic one.
}
