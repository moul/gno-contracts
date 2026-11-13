package hashringdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Consistent hashing
	//
	// Keys on a circle instead of `hash(key) % n`, demoing the [`p/moul/x/daily/hashring`](/p/moul/x/daily/hashring/v0) library.
	//
	// ## The ring
	//
	// `4` nodes, `64` virtual points each, `256` points on the circle. An even split of `2000` keys would be `500` apiece.
	//
	// | node | points | keys | share |
	// | --- | --- | --- | --- |
	// | `alpha` | 64 | 455 | 22.7% |
	// | `beta` | 64 | 435 | 21.7% |
	// | `gamma` | 64 | 517 | 25.8% |
	// | `delta` | 64 | 593 | 29.6% |
	//
	// With one point per node instead of `64`, this same workload puts 95% of the keys on `delta` and 5 of them on `alpha`. Four random cuts of a circle are nothing like an even split; interleaving `64` arcs per node is what fixes it.
	//
	// ## Where a few keys land
	//
	// The owner, then the next two nodes clockwise, which is the preference list a replicated store would write the copies to.
	//
	// | key | position | owner | replicas |
	// | --- | --- | --- | --- |
	// | `key-0` | `d5ead6fdd3d16630` | `delta` | `beta`, `alpha` |
	// | `key-1` | `be2974546978e373` | `delta` | `alpha`, `beta` |
	// | `key-2` | `7c36b0a9dedde119` | `beta` | `alpha`, `gamma` |
	// | `key-7` | `78ed7d2bf2a8c4af` | `alpha` | `delta`, `beta` |
	// | `key-42` | `a0334cf4c66799ae` | `beta` | `alpha`, `delta` |
	//
	// ## What it costs to lose a node
	//
	// Taking `gamma` out and placing the same `2000` keys again.
	//
	// | strategy | keys moved | share | unavoidable |
	// | --- | --- | --- | --- |
	// | consistent hashing | 517 | 25.8% | 517 |
	// | `hash(key) % n` | 1463 | 73.1% | 517 |
	//
	// That is the whole argument. The ring moves the keys that have to move and not one more, because their owner is a position on a circle and the circle did not change. A modulo shard moves almost everything, because the modulus moved under every key at once: nothing was wrong with where `key-1` lived, only with how many nodes there are.
	//
	// ## On chain
	//
	// The ring is a value, not realm state. This page builds one per call and throws it away, and a realm that wanted to keep one would store the membership, a handful of strings, and rebuild. Persisting `256` sorted points to avoid a few hundred hashes is the wrong trade when storage is the thing you are charged for.
	//
	// > Place your own key: append it to the path, for instance [`/hello`](/r/moul/x/daily/hashringdemo/v0:/hello).
}

// ExampleRender_key pins the per-key page, which is the one path that renders
// something the caller typed.
func ExampleRender_key() {
	print(Render("/hello"))
	// Output:
	// # Consistent hashing
	//
	// Keys on a circle instead of `hash(key) % n`, demoing the [`p/moul/x/daily/hashring`](/p/moul/x/daily/hashring/v0) library.
	//
	// ## `hello`
	//
	// | position | owner | then |
	// | --- | --- | --- |
	// | `2cf24dba5fb0a30e` | `gamma` | `alpha`, `beta`, `delta` |
	//
	// The position is SHA-256 of the key, first eight bytes. The owner is the first virtual point at or clockwise of it, and the rest of the row is the walk onwards, skipping points that belong to a node already named.
	//
	// Without `gamma` this key would belong to `alpha`, and every key that did not live on `gamma` would stay exactly where it is.
	//
	// > [Back to the ring](/r/moul/x/daily/hashringdemo/v0).
}
