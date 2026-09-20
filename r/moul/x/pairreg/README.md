# `gno.land/r/moul/x/pairreg/v0`

The registry every AMM pair instance announces itself to, and the unified
frontend over all of them. Third artifact of the instance-per-realm pattern; the
logic is in [`p/moul/x/pair/v0`](../../../../p/moul/x/pair/v0).

- **Registration is one line in an instance's `init`**, so a single `addpkg`
  both creates a pair and lists it.
- **The key is the caller's own package path**, taken from
  `cur.Previous().PkgPath()`, so an instance cannot claim a path that is not its
  own.
- **Entries hold a live `*pair.Pair`**, not an address, so `Render` shows every
  instance's real reserves from one `vm/qrender`. No indexer, no multicall.
- **Permissionless**, and spam is self funded: the registering transaction pays
  for the storage it adds.

## What it cannot tell you

Nothing on chain can read a package's source, so the registry cannot check that
an instance runs the shared template. Reserves shown in the index are **claimed**.
Several instances may exist for the same couple, on purpose: there is no
canonical pair and no factory to enforce one. Verify an instance by diffing its
source (`vm/qfile`) against freshly generated output before funding it.
