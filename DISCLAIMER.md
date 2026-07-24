# Disclaimer

The contracts in this repository (`moul/gno-contracts`) are **personal, experimental
work** by moul. Read this before using any of them.

## No warranty

Everything here is provided **"as is", without warranty of any kind**, express or
implied. There is **no guarantee** of correctness, fitness for any purpose,
availability, or backwards compatibility. Use at your own risk.

## Not audited

These packages and realms have **not undergone any security audit**. They may
contain bugs, economic flaws, or vulnerabilities. **Do not** rely on them to
custody funds or secure anything of value unless you have independently reviewed
and tested the exact version you intend to use.

## Versioning, not immutability

Contracts are versioned (`.../v1`, `/v2`, …) so callers can pin a specific
revision. A published on-chain instance is immutable, but this **source
repository may change**: contracts can be revised, re-versioned, or removed. The
version you read here is not necessarily what is deployed on any given chain —
check the on-chain source.

## Experimental packages (`/x/`)

Any package under an **`/x/`** path segment is **highly experimental** and may be
**partially or fully AI-assisted ("vibe-coded")**. These are sketches,
challenges, or explorations: expect rough edges, missing tests, breaking changes,
and outright removal without notice. **They are not intended for production use
or for handling real value.**

## Relationship to gnolang/gno

Some packages originated in the [`gnolang/gno`](https://github.com/gnolang/gno)
monorepo under `examples/gno.land/{p,r}/moul/*` and are deployed there **without**
a `/vN` suffix (genesis/older chains). The versioned copies here are moul's
staging home for them; the canonical upstream copy, when one exists, is linked
from each package's README.

## Not advice

Nothing here is financial, legal, or security advice.

---

For the repository overview, tooling, and catalog, see the
[README](https://github.com/moul/gno-contracts).
