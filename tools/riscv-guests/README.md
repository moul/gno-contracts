# riscv-guests

Guest programs and the conformance corpus for
[`p/moul/x/vm/riscv`](../../p/moul/x/vm/riscv), built by real compilers. Nothing
here is gno, nothing here is published, and nothing here is built by CI.

| | what | toolchain |
|---|---|---|
| [`fnv`](./fnv) | an FNV-1a hash, shipped as `riscv.GuestFNV` | clang |
| [`ledger`](./ledger) | a token in `#![no_std]` Rust, shipped as `riscv.GuestLedger` | rustc |
| [`conformance`](./conformance) | the official rv32ui and rv32um suites | clang |

It exists for one reason: the package ships a compiled image, and a compiled
image you cannot rebuild is a magic number. The source, the linker script and
the exact flags live here so `riscv.GuestFNV` can be reproduced and diffed
rather than trusted.

## Building

The toolchain is LLVM, because it cross compiles to RISC-V with no cross GCC to
build first. Anything from clang 17 on will do; the committed words were built
with **clang 19.1.7**.

```sh
cd fnv && make words        # prints the image as the gno source holds it
```

On a machine with nix and no clang:

```sh
nix-shell -p clang lld llvm --run 'NIX_HARDENING_ENABLE= make -C fnv words'
```

`NIX_HARDENING_ENABLE=` is not optional there. The nix cc-wrapper injects
`-fzero-call-used-regs=used-gpr`, which clang refuses for a riscv32 target, and
the build fails before it starts.

## The memory layout, and why it is in the linker script

The host makes the text segment read-only, because it predecodes it and the
arrays would otherwise be free to disagree with memory. So a guest whose
writable data shared a page with its code would trap on its first store.

`link.ld` puts `.text` and `.rodata` at `0x1000`, the host's conventional entry
point, and `.bss` at `0x40000`, far above it. The flat image is `.text` only:
everything in `.bss` starts at zero because the host zeroes the whole address
space, which is why these guests have no initialized data. The stack is set up
by the host at the top of memory and grows down.

## Each directory pins its own linker script, on purpose

The addresses in a linker script are **baked into the compiled image**: `.bss`
at `0x40000` becomes a `lui` immediate in the instruction stream. A shared
script edited for one guest would silently invalidate every image built against
the old one, and everything would still compile. So they are deliberately not
shared, and the reproducibility check is what catches the drift: it caught
exactly this once, when a committed image had been generated before a script
change and no test noticed, because both addresses were valid memory.

## Adding a guest

Copy `fnv/`, keep the linker script, and remember that there is no libc: no
`memcpy`, no `memset`, no floating point. `-fno-builtin` is what stops a C
compiler from quietly calling a libc function you did not link. Rust brings its
own: link `core` and `compiler_builtins` from the installed target, and use
`--gc-sections` or the image is 250 KB instead of 8 KB.
