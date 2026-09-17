# `gno.land/p/moul/x/plan9/ninep/v0`

**A Plan 9 shaped file abstraction for gno**: `File`, `Mutable`, `Qid`, `Stat`,
`Perm`, the 9P error set, and lexical path handling.

```go
import ninep "gno.land/p/moul/x/plan9/ninep/v0"

type File interface {
	Stat() Stat
	Walk(name string) (File, error)      // exactly one element
	Read(off, count int64) (string, error)
	ReadDir() ([]Stat, error)
}
```

This implements the *semantics* of
[9P2000](https://ericvh.github.io/9p-rfc/rfc9p2000.html), not its wire format.
There is no socket on a chain: the VM call is the transport. What survives the
translation is the part that made 9P useful, namely that every resource answers
the same four questions, so a client written today can browse a file server
deployed tomorrow.

**One interface, not two.** 9P reads a directory with the same `Tread` it uses
for a file, so splitting `File` from `Dir` would be less faithful, and a single
interface means no type assertion across a realm boundary.

**`File` is read-only, on purpose.** A crossing write method would mint the
*caller's* realm frame for the callee, which is the confused-deputy shape that
`r/gov/dao`'s `Executor` relies on deliberately and `p/nt/grc20`'s `Teller`
refuses deliberately. So mutation lives in a separate `Mutable`, which is only
safe on a tree your own realm owns. That is what makes it safe to hand a `File`
to a stranger's namespace.

Deliberate divergences, each one forced:

- **Data is a `string`, not `[]byte`.** Every consumer on this chain is text and
  `Render` returns a string.
- **`Mtime` is a block height.** It is the only clock every validating node
  agrees on.
- **There is no `open`/`clunk`.** Without a session there are no fids, so `Walk`
  returns the file itself and nothing has to be released.
- **`..` never reaches a server.** `Clean` resolves it lexically first, per
  [Lexical File Names in Plan 9](https://9p.io/sys/doc/lexnames.html), so `..`
  undoes the name you typed rather than the directory you landed in.
- **`MaxDepth` caps a walk at 32 elements.** Resolution can cost one cross-realm
  call per element, so depth is bounded rather than trusted.

Used by [`memfs`](../../memfs/v0) (a RAM server), [`synfs`](../../synfs/v0) (a
computed server), [`ns`](../../ns/v0) (namespaces) and
[`rc`](../../rc/v0) (the shell). Design and analysis:
[moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
