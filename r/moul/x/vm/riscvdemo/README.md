# r/moul/x/vm/riscvdemo

Demo of [`p/moul/x/vm/riscv`](/p/moul/x/vm/riscv/v0), the RV32IM hart, and
[`p/moul/x/vm/vmkit`](/p/moul/x/vm/vmkit/v0), the host ABI. This realm holds no
logic of its own: it stores images, builds a `vmkit.Host`, and renders.

What it exists to show is two things realm code cannot do for itself.

**The guest was not written for gno.** The programs on the front page are flat
`.text` images, the bytes a cross compiler emits for
`riscv32im-unknown-none-elf`. `Upload` takes hex, so anything you can build with
`clang`, `rustc`, TinyGo or Zig and strip to its text segment goes in unchanged.

The "Compiled by clang" sample is exactly that and is not a mock up: a
freestanding C program, built by clang for `riscv32im`, shipped as the bytes
LLVM emitted. The page shows its C because a disassembly would bury the only
interesting fact, which is that nobody wrote the machine code. Source and build
command: `tools/riscv-guests/fnv`.

**A program pauses instead of failing.** It runs until its fuel slice is spent,
then stops with a snapshot the realm keeps, and the next caller pays for the
next slice. The "Heavy loop" sample is 200,006 instructions and takes three
transactions at the default slice, which is the whole point.

```
UploadSample("heavy", "", 0)   -> id
Step(id, 80000)                -> "running"
Step(id, 80000)                -> "running"
Step(id, 80000)                -> "halted"
```

## Reading the instance page

A guest that writes nothing has still computed something, so the instance page
restores the snapshot and shows the register file under its ABI names. That is
the only place the state is legible: the hart itself does not survive the
transaction, only its snapshot does.

## What a slice costs

An RV32IM instruction costs about **8,500 gas**, measured rather than estimated,
so a block buys roughly **350,000 guest instructions**. Loading the image costs
about **19,600 gas per instruction word** and is paid again on every resume,
which is why `MaxImage` is 8 KiB and not a megabyte. The measurements and how
they were taken are in the [library README](/p/moul/x/vm/riscv/v0).

## What this realm does not grant

`Send` always returns `vmkit.ErrNotGranted`. No instance here is funded, so a
guest that tries to move coins is refused, and that is the capability rule
working rather than a missing feature. Guest key-value storage is scoped to the
instance being stepped by construction: the tree belongs to the instance, so one
program cannot reach another's even though both live in this realm.
