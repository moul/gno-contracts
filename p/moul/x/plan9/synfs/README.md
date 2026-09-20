# `gno.land/p/moul/x/plan9/synfs/v0`

**A synthetic, read-only file server whose contents are computed at read time.**
This is the package that makes the rest of the suite adoptable.

```go
import synfs "gno.land/p/moul/x/plan9/synfs/v0"

t := synfs.New("dev", "sys", func() int64 { return runtime.ChainHeight() })
t.Root().
	Add("sysname", func() string { return runtime.ChainID() }).
	Add("height", func() string { return strconv.FormatInt(runtime.ChainHeight(), 10) })
```

In Plan 9 a device is not storage, it is code behind a name: reading `/dev/time`
runs a function. A realm that wants to publish its state as a browsable tree
does the same thing here, in a few lines, and gets `ls`, `cat`, `stat` and
mountability for free.

**Read-only by construction.** The tree implements `ninep.File` and not
`ninep.Mutable`, so every method is free of side effects and the tree is safe to
hand to a namespace owned by somebody else. That is the property the whole
cross-realm mount story rests on.

Two details worth knowing:

- **A synthetic file pins `Qid.Version` at 0 forever.** Its contents can change
  on every block, so a version would be a lie; a client that needs change
  detection should read the file.
- **`AddRange` serves the 9P read window itself**, for a file with no natural
  end. `/dev/zero` uses it: an unbounded read returns nothing rather than an
  endless value, which is what stops `cat /dev/zero` from being a denial of
  service.

**Live demo:** [`r/moul/x/plan9/dev`](../../../../../r/moul/x/plan9/dev/v0)
publishes the chain itself as a device tree. Design and analysis:
[moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
