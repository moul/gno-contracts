# conformance

The official RISC-V conformance suite, built for a hart with no CSRs.

`p/moul/x/vm/riscv/conformance_test.gno` embeds 50 cases from
[riscv-tests](https://github.com/riscv-software-src/riscv-tests): all 42
`rv32ui` and all 8 `rv32um`. This directory is how they were built and how to
rebuild them.

```sh
make clone          # fetch riscv-tests into /tmp/riscv-tests
make gen            # build every case and print the gno source
```

On a machine with nix and no clang, and remembering `NIX_HARDENING_ENABLE=`
(see [../README.md](../README.md)):

```sh
nix-shell -p clang lld llvm --run 'NIX_HARDENING_ENABLE= make gen'
```

## The replacement environment, and what it does not change

The suite ships environments under `env/`. The one these tests normally use,
`env/p`, sets up `mtvec`, delegates exceptions, and enters the test through
`mret`. None of that exists on this hart: there are no CSRs and one privilege
level.

`riscv_test.h` here is a replacement that keeps the parts of the contract the
tests actually rely on, the `_start` symbol and `TESTNUM` in `gp`, and drops the
machine-mode ceremony. **The exit convention is the suite's own and is
untouched**: `env/p` already spells pass and fail as `li a7, 93; ecall`, which
is this host's exit syscall. So a test reports through the same registers it
always did, `a0 == 0` for pass and `(testnum << 1) | 1` for failure, and the gno
harness reads them out of the halted machine.

That matters for what the result means. The assertions in every case are the
suite's, compiled from the suite's source by clang. What was replaced is how a
test starts and how it hands its verdict back, not what it checks.

`link.ld` puts `.text` at `0x1000` and `.data` at `0x40000`, because the text
segment is read only here and several cases store into their data.

## One case is skipped, on purpose

`rv32ui-fence_i`. `FENCE.I` exists to make writes to the instruction stream
visible, and this machine predecodes its text and refuses stores into it, so
there is no instruction stream to make visible. Self-modifying code is not
unimplemented here, it is excluded by design. The skip is declared in the gno
test rather than left out of the corpus, so it shows up as a skip and not as an
absence.
