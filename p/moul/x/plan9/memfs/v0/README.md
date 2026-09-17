# `gno.land/p/moul/x/plan9/memfs/v0`

**A RAM file server**: Plan 9's `ramfs`, in a realm's heap. The reference
implementation of [`ninep.File`](../../ninep/v0) and `ninep.Mutable`.

```go
import memfs "gno.land/p/moul/x/plan9/memfs/v0"

fs := memfs.New("g1...", runtime.ChainHeight())
fs.MkdirAll("/usr/glenda/bin", height)
fs.WriteFile("/tmp/greeting", "hello\n", height)
root := fs.Root()   // a ninep.File, mountable into any namespace
```

Children live in an `avl.Tree`, so a directory listing is ordered by name and
therefore identical on every validating node. A map would make `Render` a
consensus bug.

**`Mutable` is in-realm only.** A non-crossing method runs in the *caller's*
frame, so a foreign realm calling `Create` or `Write` here would be mutating
objects it does not own. The read half is safe from anywhere, which is exactly
what makes a memfs tree mountable into somebody else's namespace: they get
reads, and only its owner gets writes.

**The clock is a parameter, not an import.** Every mutation takes the block
height from the caller rather than reading chain state itself, so the same tree
runs in a plain unit test.

9P behaviours reproduced rather than approximated:

- A directory reports `Length` 0, as 9P does.
- `Qid.Version` increments on every write, so a client holding a qid can tell
  "same file, changed" from "different file" without reading it.
- Writing past the end extends the file with NUL bytes.
- `DMAPPEND` pins every write to the end, whatever offset was asked for.
- Removing a non-empty directory is refused.

Design and analysis:
[moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
