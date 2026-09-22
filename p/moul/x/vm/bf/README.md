# p/moul/x/vm/bf

A Brainfuck machine for gno.land, and the measuring stick the guest-VM work is
calibrated against.

The package ships two things that look alike and are not:

- **`Execute`**, the naive interpreter from 2023: a switch over the source
  bytes, a brace matcher that rescans the program on every loop edge. It is
  kept verbatim as rung 0 of the ladder below, because a baseline you have
  edited is not a baseline. It panics on `,` and on unbalanced brackets, and
  both bugs are pinned by tests so nobody "fixes" the reference.
- **`Compile` + `Machine`**, the real one: resolved jump targets, fused
  operator runs, loop idioms folded into single ops, and a fuel-metered step
  loop over a [`vmkit`](../vmkit) `Host`, so a program pauses when it runs out
  and resumes in a later transaction.

Live demo: [`r/moul/x/vm/bfdemo`](/r/moul/x/vm/bfdemo/v0).

```go
m, err := bf.Load("+++++[->++++++++++<]>++.")
if err != nil { return err }
used, status := m.Step(host, 1000)   // status: running, halted, trapped, out of fuel
snap := m.Snapshot()                 // resume later: NewMachine(prog).Restore(snap)
```

## The optimization ladder

Measured 2026-09-22 with `gno test -print-runtime-metrics`, `gno` built from
`gnolang/gno` master@877379432. Reproduce with:

```sh
gno test -print-runtime-metrics .
```

The program is `heavy` (`ladder_test.gno`): 408 source bytes, **121,201 guest
instructions**, no output, so it measures the dispatch loop and nothing else.

| rung | what changed | machine ops | cycles | cycles / guest op |
|---|---|---:|---:|---:|
| 0 | `Execute`, the original | 161,200 dispatches | 1.4G | 11,551 |
| 1 | compile to ops, resolve jump targets | 121,202 | 613.4M | 5,061 |
| 2 | fuse runs of `+` and `>` | 81,203 | 444.6M | 3,668 |
| 3 | fold loop idioms (`[-]`, `[->+<]`, `[>]`) | 1,203 | 10.0M | 83 |
| 5 | rung 3 with a fuel budget enforced | 1,203 | 11.0M | 91 |

From the 1x and 4x pairs, which cancel the fixed per-test overhead: rung 0 runs
at **11,003 cycles per guest instruction**, rung 3 at **79.5**. The ladder is
worth **138x**, and almost all of it is rung 3: folding a counted loop into the
multiply it performs is the only optimization here that changes the complexity
rather than the constant.

### Two denominators, and why it matters

A guest instruction is one operator the language executes, counted the way any
jump-table interpreter counts it: 121,201 for `heavy`. The naive interpreter
*dispatches* more often than that for the same program, because its `]` handler
scans back to the matching `[` and lands on it, so `[` is re-evaluated on every
iteration of every loop: 161,200, a factor of 1.33.

Rung 1 removes exactly that excess, so quoting cycles-per-*dispatch* would
credit rung 1 twice and make rung 0 look 33% better than it is. Both counts come
from an independent simulator, not from this package.

## The other axis: what the GnoVM charges for

The rungs above are the classic optimizations, fewer instructions for the same
program. On the GnoVM a second axis matters as much, and it is not in any
interpreter textbook: the same instruction stream, run by loops that differ from
each other by one line. `micro_test.gno` is that matrix.

Rung 1's stream, 121,202 ops:

| loop | cycles | allocs | vs. locals |
|---|---:|---:|---:|
| cursors as struct fields | 523.7M | 31.5M | +18% |
| cursors in locals | 442.4M | 31.5M | baseline |
| + `vmkit.Meter.Charge` per op | 821.3M | 110.1M | **+86%** |
| + inline fuel counter instead | 514.2M | 31.5M | +16% |
| + tape as a local slice | 492.1M | 31.6M | +11% |

Rung 3's stream, 1,203 ops, same ordering: 9.0M / 8.2M / 11.9M / 8.9M / 8.7M.

Three things follow, and the shipped `Machine.Step` does all three:

1. **A method call per guest instruction is the most expensive thing in the
   loop.** Charging fuel through `vmkit.Meter` costs 86% on top of the entire
   dispatch loop and more than triples the allocation count. `Meter` is the
   right type at the API boundary, where it is called once per slice. It is not
   a hot-path type, and no guest VM in the zoo should treat it as one. An inline
   counter does the same job for 16%.
2. **Reaching through a struct pointer for the program counter and the tape
   pointer costs 16%.** Hoist them into locals and write back once.
3. **The fixed-array tape is not the win the textbooks claim.** An array is
   supposed to remove a bounds check; here a slice is 4% *faster*, because a
   slice header can be copied into a local and an array cannot. It is the
   smallest effect on this page, and the classic ladder puts it above idiom
   recognition, which is worth 44x.

The pc range check is also hoisted out of the loop: every jump target is
produced by `Compile` and every restored pc is validated by `Restore`, so
checking per op buys nothing.

## Snapshots

A snapshot carries the tape only up to the highest cell the program has
reached, so hello world pauses in **43 bytes**, not 30,000. That is what makes
continuations cheaper than re-running, which is the kill criterion `vmkit` set
for them.

The program is *not* in the snapshot: a realm stores it once beside the
instance, not once per pause.

## Semantics

Tape of 30,000 wrapping byte cells, matching the original. `,` past the end of
input yields a zero cell, the most common of the three conventions the language
never settled. `Compile` rejects unbalanced brackets and sources above 64 KiB.

The idiom rewriter is deliberately conservative: it folds a loop only when the
body moves and adds, returns to where it started, and takes exactly one off the
current cell. A loop that adds one per iteration still terminates by wrapping
after 256 rounds, and is left as a real loop, because folding it would be a
different program.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/p/moul/x/vm/bf/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/p/moul/x/vm/bf/v0/deps.png)

> 🧪 **Highly experimental — potentially vibe-coded.** Not audited; may break, change, or be removed at any time. Do not use with anything of value. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
