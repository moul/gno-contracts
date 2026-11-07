# `gno.land/r/moul/x/daily/lzwdemo/v0`

A gnoweb demo of [`p/moul/x/daily/lzw`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/lzw),
the Lempel-Ziv-Welch coder. Four things, on one page:

- **`mississippi`, code by code**, with what each code means and which entry
  the *decoder* adds on that step. The decoder's table runs one entry behind
  the encoder's, and the column is there to make that visible rather than to
  be taken on trust.
- **The case that breaks a naive decoder**: `aaaaa`, where code 256 arrives one
  step before the table holds it.
- **What repetition is worth**, including the two inputs where LZW loses. Nine
  bit codes standing in for eight bit bytes cost an eighth more until something
  repeats.
- **Where the code width grows**, measured on 768 low-redundancy bytes rather
  than asserted.

```
/r/moul/x/daily/lzwdemo/v0
/r/moul/x/daily/lzwdemo/v0:mississippi
```

A path argument is compressed and its stream shown, widths included.

It contains **no codec logic of its own**: every figure, including the
per-code widths, comes back from the library's `Steps`, so there is nothing
here that can drift away from the decoder. Stateless, so `Render` is
deterministic and an example test pins the whole page.

Built for gno 0.9.
