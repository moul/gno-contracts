# ledger

A token in `#![no_std]` Rust: mint, send, burn, applied from a script on the
call input, balances written back.

```
mint alice 100          alice 70
mint bob 50       ->    bob 80
send alice bob 30
```

A refusal names the line and exits non-zero, which the host reports as
**halted** rather than trapped, because the program said no and the VM did not
break:

```
mint a 1
send a b 9        ->    line 2: insufficient balance
```

Shipped as `riscv.GuestLedger`. Rebuild with `make words check` and diff against
`p/moul/x/vm/riscv/guests.gno`.

## It links real `core` and `compiler_builtins`, and that is the point

This guest calls neither directly, and both arrive anyway:

- a bounds check reaches `core::panicking::panic_bounds_check`,
- and `__udivdi3`, because the balances are 64-bit and **RV32 has no 64-bit
  divide instruction**, so Rust's software division routine runs on the
  emulator.

So the emulator is not only running compiler output, it is running the standard
library's own hand-tuned arithmetic. `--gc-sections` is what keeps that from
costing 250 KB; without it the whole of `core` is linked and the image is 30x
larger than the realm would accept.

## Why this directory pins its own linker script

The addresses in `link.ld` are baked into the compiled image: `.bss` at
`0x40000` becomes a `lui` immediate in the instruction stream. A shared script
edited for one guest would silently invalidate every committed image built
against the old one, and the corpus would still compile. So each guest pins its
own, and `make check` asserts the one property a flat image cannot be wrong
about: `_start` is the first byte.

`.eh_frame` is discarded rather than ignored. It sorts before `.text` and would
otherwise be the first thing the host executed.
