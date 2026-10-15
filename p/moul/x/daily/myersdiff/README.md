# `gno.land/p/moul/x/daily/myersdiff/v0`

**The shortest edit script between two documents**, Myers' algorithm: `Lines`, `Slices`, `Budget`, `Hunks`, `Unified`, `UnifiedScript`, and `Script.Apply`.

```go
import "gno.land/p/moul/x/daily/myersdiff/v0"

s := myersdiff.Lines("a\nb\nc", "a\nx\nc")
s.Edits        // [ a] [-b] [+x] [ c]
s.Added()      // 1
s.Minimal      // true
s.Apply([]string{"a", "b", "c"})     // ["a", "x", "c"]

myersdiff.Unified(old, new, 2)       // @@ -1,4 +1,5 @@ and its lines
```

A realm that stores text and lets it be edited ends up holding two versions of it and no way to say what moved between them. Storing the diff instead of the second snapshot is the usual answer, and showing a reader what a proposal changes is the other. Both need the same thing first: which lines were added, which were removed, and in what order. Everything else is formatting.

**The search is bounded by a budget, not by the input size, deliberately.** Myers costs `O((n+m)*d)` where `d` is the number of differing lines, so two similar documents are cheap at any size and two unrelated ones are quadratic. On chain the caller picks both documents, so `d` is attacker-controlled and the input size alone bounds nothing useful. `DefaultBudget` caps the rounds at 256; past it the search gives up and returns a script that deletes everything and inserts everything, with `Minimal` set to false.

Three behaviours worth knowing before you use it:

- **A non-minimal script is still a correct script.** The budget changes how short the answer is, never whether it is right: `Apply` replays the fallback into the same document it replays the minimal one into. Check `Minimal` when you are about to store a diff as the canonical record of a change, and ignore it when you are rendering one for a human.
- **Reads are total, construction panics.** `Budget` panics above `MaxLines` (4,096 a side), and nothing else in the package panics at all: `Hunks` with a negative context, `Apply` on a mismatched document, a `Hunk` whose side is empty are all defined. Construction is a transaction, where aborting is the useful answer. Rendering is a page, and a realm cannot be redeployed on the same path, so a `Render` that panics is broken permanently.
- **A moved line is a delete and an insert, not a move.** Myers compares sequences and has no concept of identity, so reordering three lines costs the edits needed to explain the new order. A realm that wants move detection has to run it as a second pass over this script, pairing equal texts across the two sides.

`Hunks(s, context)` groups the script the way a review tool prints it, merging two changes into one hunk when their context would overlap. The `@@` header follows diff(1) exactly, including the convention a pure insertion needs: a side contributing no lines reports the line *before* the hunk and a length of zero, so `@@ -0,0 +1,2 @@` is what patch(1) expects to read back.

`Unified` emits the hunk bodies and nothing else. The `---` and `+++` file headers name files, which a realm does not have, so a caller that wants them adds them.

Line-oriented only. A word diff or a character diff is the same algorithm over a different sequence, and `Slices` is exported so a caller can supply one; the splitting and the rendering would be different and are not here.

Live demo: [`r/moul/x/daily/myersdiffdemo`](/r/moul/x/daily/myersdiffdemo/v0).
