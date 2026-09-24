# fnv

Reads the call input, hashes it with FNV-1a, writes eight hex digits back.
Three syscalls, one loop, 196 bytes of text.

The hash is not the point. The point is that clang chose the registers, the
stack frame, the instruction selection and the loop shape, and the emulator on
the other side was never told what it was going to be handed. The multiply in
the inner loop is why this is `rv32im` and not `rv32i`.

Shipped as `riscv.GuestFNV`. Rebuild with `make words` and diff against
`p/moul/x/vm/riscv/guests.gno`.
