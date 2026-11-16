package hyperloglogdemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand typed:
// every estimate and every error figure in it is computed by the library under
// test, so a change in the estimator shows up here as a diff rather than as
// prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # HyperLogLog
	//
	// How many DISTINCT elements a stream contained, out of a fixed kilobyte that never grows, demoing the [`p/moul/x/daily/hyperloglog`](/p/moul/x/daily/hyperloglog/v0) library.
	//
	// Counting unique callers with a set costs one stored object per caller, and nobody in the realm decides how many callers there will be. This costs 1,024 bytes at ten elements and 1,024 bytes at ten million.
	//
	// ## Three sketches, three questions
	//
	// | question | structure | what it cannot do |
	// | --- | --- | --- |
	// | have I seen this one? | [bloom filter](/r/moul/x/daily/bloomfilter) | tell you how many there were |
	// | how often did this one arrive? | [count-min sketch](/p/moul/x/daily/countminsketch/v0) | tell you how many were different |
	// | how many different ones were there? | **this one** | tell you whether it has seen YOU |
	//
	// The third is the one most easily misread. A sketch that has counted a million elements holds none of them: only the longest run of leading zeros each register was ever shown. That is why it fits in a kilobyte, and why nothing can be taken back out.
	//
	// ## How close it gets
	//
	// Every row below is a fresh sketch at the default precision: 10, so 1024 registers and a standard error of 3.25%.
	//
	// | true count | estimate | off by | error | registers used | estimator |
	// | --- | --- | --- | --- | --- | --- |
	// | 1 | 1 | 0 | +0.00% | 1 of 1024 | linear counting |
	// | 10 | 10 | 0 | +0.00% | 10 of 1024 | linear counting |
	// | 100 | 100 | 0 | +0.00% | 95 of 1024 | linear counting |
	// | 1000 | 1029 | +29 | +2.90% | 649 of 1024 | harmonic mean |
	// | 5000 | 5059 | +59 | +1.18% | 1021 of 1024 | harmonic mean |
	//
	// Two estimators, and the switch between them is where naive implementations go wrong. While most registers are still empty the answer comes from counting the empty ones, which is exact until two elements collide. Once they are mostly full the harmonic mean of the registers takes over, and the answer becomes an estimate with a published error bar rather than a number.
	//
	// ## What the kilobyte buys
	//
	// | precision | registers | bytes | standard error |
	// | --- | --- | --- | --- |
	// | `4` | 16 | 16 | 26.00% |
	// | `8` | 256 | 256 | 6.50% |
	// | `10` (default) | 1024 | 1024 | 3.25% |
	// | `12` | 4096 | 4096 | 1.63% |
	// | `14` | 16384 | 16384 | 0.81% |
	// | `16` | 65536 | 65536 | 0.41% |
	//
	// The error does not depend on the cardinality, only on the register count, which is the counter-intuitive part: the same kilobyte is about as wrong at a thousand elements as at a billion. Halving the error costs four times the space, so the useful range is narrow and the default sits in the middle of it.
	//
	// ## Merging two shards
	//
	// The operation no exact counter can offer without shipping its elements. The two shards below overlap by 500, so a sum would answer 2,000 and the union is 1,500.
	//
	// | sketch | elements added | distinct | estimate | error |
	// | --- | --- | --- | --- | --- |
	// | left shard | 1000 | 1000 | 988 | -1.20% |
	// | right shard | 1000 | 1000 | 1015 | +1.50% |
	// | **merged** | 2000 | 1500 | 1512 | +0.80% |
	//
	// A merge is a register-wise maximum, so an element present in both shards has no way to be counted twice. That also makes it idempotent: replaying the same merge changes nothing, which matters when the shards are days of history and somebody re-runs a job.
	//
	// ## What it will not do
	//
	// | limit | behaviour | why |
	// | --- | --- | --- |
	// | membership | not answerable | no element is stored, only zero-run lengths |
	// | removal | not supported | a register is a maximum, and a maximum cannot be undone |
	// | exactness | only in the small range | past a few thousand it is an estimate with an error bar |
	// | the error bar | one standard deviation | about a third of sketches land outside it |
	// | precision | `4` to `16` | below is noise, above buys a fraction of a percent for 64 KiB |
	//
	// A realm that needs the elements back needs a set and the bill that comes with one. This is for the case where the number was the whole question: unique callers this week, distinct voters, how many addresses touched a pool.
}
