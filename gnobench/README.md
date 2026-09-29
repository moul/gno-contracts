# gnobench

**What a gno construct costs, measured.** Not estimated, not reasoned about: run, recorded with
the machine and the gno revision that produced it, and regenerated into a report nobody edits
by hand.

```sh
make bench                 # measure the storage suite, merge into this machine's file
make report                # regenerate reports/ from whatever is on disk
make list                  # what suites, candidates and workloads exist
```

`GNOROOT` must point at a `gnolang/gno` checkout; it supplies the stdlibs. Nothing else is
required and nothing touches the network.

## What it measures

Every measurement is one generated gno filetest run through gnovm's own filetest runner, which
returns three things:

| axis | where it comes from | how far to trust it |
|---|---|---|
| **gas** | the VM's meter: CPU cycles, allocations, store reads and writes, in one figure | comparable between rows, **not** mainnet gas (the filetest meter is infinite and the test gas config is not the chain's) |
| **bytes** | `Store.RealmStorageDiffs()`, the net byte delta of persisted realm objects | real: at `storage_price` 100 ugnot/byte this **is** the deposit |
| **wall** | timed around the call | carries a fixed per-run type-check cost, so only large deltas mean anything |

## Warm and cold, which is the whole point

A benchmark that builds a container and then reads it **in the same run** measures nothing a
realm will ever experience. Every object it touches is already live in the VM's
per-transaction object cache.

So each workload declares a mode:

- **warm**: built and measured inside one run.
- **cold**: built during package initialisation, which the filetest runner commits and then
  reconstructs the machine from ("Clear store cache and reconstruct machine from committed
  info (mimicking on-chain behaviour)", `gnovm/pkg/test/filetest.go`). `main` then starts with
  an empty object cache and deserialises every object it touches, exactly as a transaction
  against a deployed realm does.

The difference is not a rounding error. A container held in **one** persisted object is O(1)
warm and **O(n) cold**, because the first touch loads all of it. The `tx_*` workloads measure
the realistic unit: one transaction, one operation, nothing cached.

## Why the numbers are comparable

1. **Baseline subtraction.** Every workload names a baseline whose body is an exact prefix of
   its own, so `tx_read` minus `tx_base` is one read and nothing else.
2. **Identical inputs.** Fixed-width keys, so lexicographic order equals numeric order; one
   deterministic Fisher-Yates over xorshift64, seeded the same for every candidate.
3. **Nothing incidental is persisted.** The key and permutation slices are function-local.
4. **Every scenario asserts its own postcondition.** An adapter that silently measures nothing
   panics instead of posting a great number.
5. **Repeats must agree.** Gas and bytes are deterministic; a row that moves between repeats is
   flagged, never averaged.

## Results are per machine, and they append

```
results/<suite>/<machine-id>.json
```

The machine id is OS, arch, CPU model and core count. Re-running on the same machine **updates
rows in place**; running on a different machine writes a **different file** and both are kept.
A scenario nobody has run yet is simply absent, so adding a candidate or a workload is additive.

Every row carries the date it was measured and the gno commit it was measured against. The
report computes its own warnings from that: rows measured against more than one gno revision,
rows over 30 days old, rows that did not reproduce, rows that failed.

`reports/<suite>.md` and `reports/<suite>.html` are **generated**. Never edit them; run
`make report`.

## Suites

| suite | what it asks |
|---|---|
| `storage` | where a realm should put its data: 19 key/value and positional containers |

A second suite is a new file, not a new tool: a `Suite` value with its candidates, its
workloads and its facets, registered from an `init`.

## Adding a candidate

One entry in `suite_storage.go`: the import, the declaration of the empty container, and the
op set its group's workloads call.

| group | ops |
|---|---|
| `kv` | `opSet` `opGet` `opDel` `opIter` `opRange` `opOffset` `opSize` |
| `list` | `opPush` `opAt` `opSetAt` `opDelAt` `opIter` `opCompact` `opSize` |

`Skip` names the workloads it cannot answer and why. `Values` restricts which value shapes it
takes. `Tags` are what the dashboard's filters are built from, as `facet:value` pairs, so a
reader can ask for "key order and supports range" and see only those.

Names are **import paths**, always. `avl` reads like a language feature; `p/nt/avl/v0` reads
like what it is, a package with a version and an author, that a realm chose and could choose
differently.

## Files

| file | what |
|---|---|
| `main.go` | the CLI: `run`, `report`, `list` |
| `run.go` | generation, execution, baseline subtraction |
| `template.go` | the single gno file every measurement is rendered into, and the warm/cold placement |
| `env.go` | machine and toolchain detection |
| `store.go` | the per-machine result files and the staleness warnings |
| `report.go` | the generated markdown |
| `html.go`, `page.go` | the generated dashboard |
| `suite.go` | the generic suite shape |
| `suite_storage.go`, `suite_storage_workloads.go` | the storage suite |
