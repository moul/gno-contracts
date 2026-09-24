# riscv-guests

Guest programs for [`p/moul/x/vm/riscv`](../../p/moul/x/vm/riscv), compiled by a
real compiler. Nothing here is gno, nothing here is published, and nothing here
is built by CI.

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

## Adding a guest

Copy `fnv/`, keep the linker script, and remember that there is no libc: no
`memcpy`, no `memset`, no floating point. `-fno-builtin` is what stops the
compiler from quietly calling a libc function you did not link.
