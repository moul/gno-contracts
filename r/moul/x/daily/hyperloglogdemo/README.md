# `gno.land/r/moul/x/daily/hyperloglogdemo/v0`

**A gnoweb page for the cardinality estimator in [`p/moul/x/daily/hyperloglog`](/p/moul/x/daily/hyperloglog/v0)**: how close a kilobyte of registers gets to the true count, what that kilobyte buys at each precision, and the merge that counts a union without shipping either side's elements.

```go
import "gno.land/r/moul/x/daily/hyperloglogdemo/v0"

hyperloglogdemo.Render("")   // → the whole page, from generated inputs
```

The library's own tests prove the estimate lands inside its error bar. They cannot show what that error bar feels like, which is the thing most worth seeing: at a hundred elements the answer is exact, at a thousand it is 29 out, and the footprint never moved.

**Every figure on the page is computed, never written down.** The element sets are generated at the top of the realm from fixed prefixes and nothing else feeds them, so `ExampleRender` pins the output byte for byte: change the estimator and the diff lands in the test rather than in the prose.

Three things the page is built to show:

- **The estimator switches, and the table says which one answered.** The first three rows are still in the small range, where counting the empty registers is exact; the last two are past it, where the harmonic mean takes over. A demo that only showed large cardinalities would make the structure look worse than it is, and one that only showed small ones would make it look like a counter.
- **The merge example overlaps by half.** Two shards of a thousand, sharing five hundred, so a sum would answer 2,000 and the union is 1,500. Overlapping is the only arrangement in which a union is distinguishable from a sum.
- **The space table is the actual argument.** Halving the error costs four times the registers, which is why the useful range is narrow and the default sits in the middle of it.

No estimation logic of its own, no chain state, no caller input: stateless and deterministic, which is what makes it pinnable.
