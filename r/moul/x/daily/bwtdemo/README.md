# `gno.land/r/moul/x/daily/bwtdemo/v0`

**A gnoweb demo of [`p/moul/x/daily/bwt`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/bwt)**:
the rotation matrix the Burrows-Wheeler transform is read off, the walk back,
and what the clustering is worth on four inputs.

Render it at [`/r/moul/x/daily/bwtdemo/v0`](https://gno.land/r/moul/x/daily/bwtdemo/v0),
or append text to transform your own:

```
/r/moul/x/daily/bwtdemo/v0:banana bandana
```

No transform logic of its own, and no state. Every figure on the page is
computed from the fixed strings at the top of the source, never from chain
state, which is what lets `ExampleRender` pin the whole page.

**The fourth sample is there to fail.** `mississippi` repeats letters but no
substring long enough to group, so the transform does not reduce its run count
by one. A demo that only showed the inputs where an algorithm wins is an
advertisement, and the library exports `Runs` precisely so a caller can check
instead of assuming.

**Everything a caller sends is escaped twice over.** The input is echoed, and
so is the transformed string, which is a permutation of the caller's own bytes
and therefore carries every backtick and pipe they sent. Table cells go through
`ui.Cell` rather than a code span: a code span escapes nothing markdown tables
care about, so a pipe inside one opens a new column and shifts every value
after it. `ExampleRender_escapesCallerInput` pins that, and reverting the
escape turns it red.
