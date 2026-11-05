# ascii85

Shows what ascii85 costs against base64 and hex, the zero-group shortcut that
makes it not a fixed ratio, and the overflowing groups the library refuses
where Go's standard library wraps them.

Demo of the [`p/moul/x/daily/ascii85`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/ascii85)
library - the encoder, the decoder and every refusal come from the package;
this realm holds no codec logic of its own. Stateless and read-only, so
`Render` is fully deterministic.

```
/r/moul/x/daily/ascii85demo/v0           → the cost, the shortcut, the refusals
/r/moul/x/daily/ascii85demo/v0:gno.land  → encode that text, bare and framed
```

The refusal table is the page worth reading. `s8W-"`, `uuuuu` and `s8W-#` are
made only of alphabet characters and each names a group of 2^32 or more, which
no four bytes can produce. Go's `encoding/ascii85` accepts all three and wraps
them in a `uint32`, so the first decodes to the same four zero bytes as the
one-character shortcut `z`. Here each is refused, while `s8W-!` one below the
limit still decodes to four `0xFF` bytes: the check is a boundary, not a
blanket refusal of large groups.

The per-input page escapes through
[`p/moul/md`](https://github.com/moul/gno-contracts/tree/main/p/moul/md)
rather than hand-placed backticks, and that is not boilerplate here. The
backtick is character 96, inside the `!` to `u` range ascii85 encodes into, so
an encoded value can carry one and close a code span the realm opened:
`Encode("i")` is `` B` ``. A test pins that case.

Built for gno 0.9.
