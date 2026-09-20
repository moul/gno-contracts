# `gno.land/p/moul/x/plan9/rc/v0`

**A small shell over a Plan 9 [namespace](../../ns/v0)**: `ls`, `cat`, `stat`,
`ns`, `bind`, `mount`, `unmount`, `mkdir`, `rm`, `echo`, `cd`, `pwd`, `walk`,
`help`.

```go
import rc "gno.land/p/moul/x/plan9/rc/v0"

sh, fs := rc.NewMemShell("g1...", rc.ReadWrite, runtime.ChainHeight)
out, err := sh.Run("bind -ac /srv/dev /dev; echo hello > /tmp/greeting; ls -l /")
```

A namespace you cannot inspect is a namespace you cannot trust. Everything here
operates on an `ns.Ns` and returns text, so one realm's `Render` becomes a file
browser and one transaction becomes a shell command.

**The mode split is the security model.** A shell in `ReadOnly` mode refuses
every mutating command, which is what lets a realm expose it through `Render`,
where mutating anything would be a bug, while the same code backs a crossing
`Exec` that may write.

**On the first error the run stops and returns it.** A realm should let that
error panic, so a half-applied command line reverts with its transaction rather
than leaving a namespace nobody asked for.

Two commands exist to make a namespace legible rather than to do work:

- **`ns`** prints the mount table in `ns(1)` format.
- **`walk /bin/rc`** prints how each element resolves, with the union width per
  step. It is where a bind stops being magic: the width column says exactly
  where one took effect, and that a union is top level only.

Quoting follows rc: single quotes, with `''` inside a quoted string standing for
one literal quote. Commands are separated by `;` or newlines, and quoting is
respected when splitting them. `MaxCommands` (32) bounds one run.

**Live demo:** [`r/moul/x/plan9/ns`](../../../../../r/moul/x/plan9/ns/v0)
renders it. Design and analysis:
[moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
