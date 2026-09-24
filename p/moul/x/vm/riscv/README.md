# p/moul/x/vm/riscv

RV32IM in gno: 48 instructions that `rustc`, `clang`, TinyGo and Zig already
emit. A guest here is not written in a new language and is not translated by
anything of mine. It arrives compiled by the real compiler and optimized by the
real optimizer, and this package is a decode loop.

Live demo: [`r/moul/x/vm/riscvdemo`](/r/moul/x/vm/riscvdemo/v0).

Second guest on [`vmkit`](../vmkit), which is the only way to find out whether
the host ABI was shaped around the first one. It was not: `riscv` implements
`vmkit.Machine` unchanged and shares the fuel meter, the snapshot codec and the
instance store with [`bf`](../bf).

```go
m, err := riscv.NewMachine(image, 0x1000)   // image is a flat .text blob
if err != nil { return err }
used, status := m.Step(host, 50_000)        // running, halted, trapped, out of fuel
snap := m.Snapshot()                        // resume in a later transaction
```

## Does it clear the bar

The design issue set a kill criterion before any code existed: **above roughly
15,000 gas per RV32I instruction the track is a curiosity, not a substrate**, on
the reasoning that a guest would then get about 200k instructions per block,
which is a token transfer and not a program anyone would write without thinking
about it.

Measured 2026-09-25 with `gno test -v` (`--- GAS:`), `gno` built from
`gnolang/gno` master. The figure is a slope from two loop sizes, 4,006 and
16,006 instructions, so the fixed per-test overhead cancels. The slope is
stable to a few gas between runs; the fixed term is not, which is why it is a
slope:

| rung | what changed | gas / instruction |
|---|---|---:|
| 0 | `decode.gno`'s helpers called per instruction | 33,992 |
| 1 | field extraction and the fetch inlined into the dispatch loop | 18,834 |
| 2 | predecode once at load, dispatch on a frequency-ordered opcode | **8,487** |

**It clears the bar with a 1.8x margin**, which works out to about **354,000
guest instructions per block**. The ladder is worth 4.0x end to end, and all of
it came from moving work off the per-instruction path rather than from doing
anything clever with the instruction set.

Reproduce with `gno test -v .` and read `TestBenchRV32I1000` and
`TestBenchRV32I4000`.

Be careful what that number is not. 354k instructions is a real program and a
small one: a sort, a parser, a state machine, a few thousand iterations of a
loop. It is not a signature verification, which is millions of instructions, and
the chain already has secp256k1 natively for that reason.

## A guest a compiler produced

The claim this package rests on is that a program arrives compiled by the real
compiler, so there is a test that does exactly that and nothing else is trusted
to stand in for it.

`riscv.GuestFNV()` is 49 instructions of freestanding C, built by **clang
19.1.7** for `riscv32im`, that reads the call input, hashes it with FNV-1a and
writes eight hex digits back. The source, the linker script and the exact build
command are in [`tools/riscv-guests/fnv`](../../../../tools/riscv-guests/fnv),
so the committed words can be rebuilt and diffed rather than believed.

```go
m, _ := riscv.NewMachine(riscv.GuestFNV(), riscv.DefaultEntry)
m.Step(host, vmkit.Unmetered)   // host.Input() = "gno.land" -> "fb7ffba0"
```

It is the only test here not written by the same person who wrote the emulator,
and it exercises what a hand-written program does not: a real function prologue
spilling `ra` and `s0` to a stack the host set up, `.bss` addressed at `0x40000`
far above a text segment the host refuses stores into, LLVM materializing the
2166136261 offset basis through a `lui`/`addi` pair, and `MUL` in an inner loop.
It also pauses and resumes correctly when sliced three instructions at a time,
which is the property a realm depends on and the one most likely to break on
code nobody wrote to be sliceable.

The memory layout is not incidental. W xor X means a guest whose writable data
shared a page with its code would trap on its first store, so the linker script
is part of the ABI and says so.

## What the GnoVM charges for, measured

The rungs above are not classic interpreter optimizations. They are answers to
how *this* host executes code, and `switchcost_test.gno` measures it directly,
200,000 iterations per figure:

| what | gas each |
|---|---:|
| one elementary operation, from the loop control | ~280 |
| a function call | 466 |
| a call through a table indexed by opcode | 727 |
| `switch`, hitting the **first** case | 292 |
| `switch`, hitting the **48th** case | 13,358 |
| **each case label scanned on the way** | **278** |
| `make([]byte, n)`, for any n | 655,224, flat |

Two of these decided the design:

1. **The GnoVM scans switch cases in source order.** Case 47 costs 45x case 0.
   So the internal opcodes in `predecode.gno` are ordered by how often compiled
   code executes them, and that ordering is load-bearing: sorting that list
   alphabetically would make the interpreter slower. It also means a flat
   48-case switch is only a win if the common instructions are near the top,
   and that a table of function values (727 gas, position independent) beats a
   switch for anything past the third case.
2. **`make` does not charge for size.** A megabyte costs what four kilobytes
   costs. The flat 1 MiB address space is therefore free at load, and the thing
   to economize is per-word work, not bytes.

## The cost on the other side: predecode

Predecoding is **19,623 gas per word**, paid at load and again on every resume,
because the arrays are not in the snapshot: only the memory pages are.

That is 2.3x what executing an instruction costs, which is high enough to state
plainly rather than bury:

- **It pays for itself once a slice executes about 1.9 instructions per word of
  its text** (`19,623 / (18,834 - 8,487)`). Any loop clears that immediately.
  Straight-line code run once does not, and for that shape rung 1 is the faster
  interpreter.
- **A large binary pays it every transaction.** A 64 KiB text segment is 16,384
  words, so a resume costs about 321M gas, roughly 11% of a block, before the
  guest executes anything.

The fix is known and not done here: decode a word the first time it is reached
rather than all of them at load, keyed on a sentinel opcode. That costs one
comparison per instruction (~280 gas, about 3%) and charges only for code the
guest actually runs. Worth doing when a real binary shows up; not worth
guessing at now.

Merging the immediate decoder into the opcode switch already took predecode from
31,432 to 19,623 gas per word. The two were separate functions, and the second
one had a `case` clause listing 22 opcodes, every label of which was scanned.

## Semantics

**W xor X.** A store into the text segment traps. Predecoding is only sound if
the code cannot change under the arrays, and refusing is also what an ELF text
segment does, so self-modifying code is not a thing this VM has. `FENCE.I` is
therefore unnecessary and `FENCE` is a no-op, which is what it architecturally
is on a machine with one hart.

**`exit(1)` halts, it does not trap.** A program that returns non-zero said no;
it did not break. A chain that conflates "your code failed" with "the VM failed"
cannot tell a user which one happened.

**An unknown syscall traps** rather than returning zero, so a guest built
against a newer syscall table fails loudly on an older host instead of silently
reading a success it never got.

**The M extension's edge cases return values, they do not trap.** Division by
zero gives all ones, and `INT_MIN / -1` gives `INT_MIN`. The spec defines both
precisely, which is exactly what a chain needs: there is no host arithmetic
exception left to differ between nodes.

**No F, no D, no C, no A.** No floats means no rounding mode and nothing that
can differ between nodes. No compressed instructions means every instruction is
4 bytes and `(pc - base) >> 2` is the whole fetch. No atomics because there is
one hart.

**Misaligned is a trap, out of range is a trap.** RISC-V leaves an access
outside physical memory to the platform, and a chain has to pick the behaviour
that cannot differ between nodes. Refusing is deterministic; wrapping would let
a guest alias two addresses and get different answers from different memory
sizes.

## Snapshots

A 1 MiB address space that serialized in full on every pause would make
continuations cost more than re-running, which is the kill criterion `vmkit` set
for them. Memory is snapshotted by **dirty page**: a guest that has written two
pages pauses in about 8 KiB regardless of how much memory it was given, and
`TestSnapshotCarriesOnlyTouchedPages` asserts the proportionality rather than a
magic number.

The program is not written twice. It is in the memory pages already, marked
dirty by `WriteImage`, so a snapshot carries the text extent and re-derives the
predecode from the restored pages.

## The syscall table

Eight calls, in the RISC-V Linux register convention a compiler already knows:
`a7` selects, `a0`..`a3` carry arguments, `a0` receives the result. A no_std
guest needs three lines of inline assembly and no gno-specific runtime.

| a7 | call | maps to |
|---:|---|---|
| 93 | `exit(status)` | halts the machine |
| 64 | `write(fd, buf, len)` | `Host.Output` |
| 63 | `read(fd, buf, len)` | `Host.Input` |
| 90 | `height()` | block height |
| 91 | `now()` | block time, Unix seconds |
| 92 | `caller(buf, len)` | the calling address |
| 94 | `log(buf, len)` | `Host.Log` |
| 95 | `emit(type, typelen, body, bodylen)` | `Host.Emit` |

Deliberately small, and every one of them is something `vmkit.Host` already
offers. The Host is the audited surface; a syscall that reached past it would be
a second, unreviewed one. One call's buffer is capped at 64 KiB, because a guest
asking to write a gigabyte has found the host's allocator, not something to say.

## Tests

The assembler in `riscv_test.gno` is written from the spec independently of the
decoders in `decode.gno`, so a field in the wrong place fails unless both files
put it in the same wrong place. `decode_test.gno` round-trips all five immediate
formats at their sign boundaries, which is where this went wrong twice while it
was being written: a 12-bit immediate makes `addi x8, x0, 4000` load **-96**,
and a 13-bit B-type immediate makes a hand-written `-8` branch jump forward by
4,088.
