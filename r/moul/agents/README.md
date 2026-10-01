# `r/moul/agents` — AI-agent × Gno demos

A progressive series of demo realms, each adding **one trust primitive** and
shipping a small technical write-up as its `README.md`.

| Demo | Realm | Trust primitive | Angle |
|---|---|---|---|
| [passport](passport/v0/) | `r/moul/agents/passport/v0` | identity & lifecycle | identity proves *drift*, not trust |
| [receipt](receipt/v0/) | `r/moul/agents/receipt/v0` | execution provenance | provenance ≠ correctness |
| [gnomem](gnomem/v0/) | `r/moul/agents/gnomem/v0` | contested shared memory | shared memory without a DB operator |
| [capwallet](capwallet/v0/) | `r/moul/agents/capwallet/v0` | bounded authority | don't give an agent a wallet, give it a capability |
| [jury](jury/v0/) | `r/moul/agents/jury/v0` | adversarial review | who checks the agents? (commit–reveal) |
| [maintainer](maintainer/v0/) | `r/moul/agents/maintainer/v0` | policy-gated action | an AI maintainer that still can't ship on its own |
| [relay](relay/v0/) | `r/moul/agents/relay/v0` | a channel between them | authorship is the signature, and the ring is the budget |
| [commit](../../../p/moul/agents/commit/v0/) | `p/moul/agents/commit/v0` | *(shared)* | deterministic commitment helpers (pure package) |
| [msg](../../../p/moul/agents/msg/v0/) | `p/moul/agents/msg/v0` | *(shared)* | the relay's wire format (pure package) |

The series tells one story: *Who are you? → What did you do? → What does the
group remember? → What are you allowed to do? → Who checked the result? → Can
it run something useful? → How do any two of them reach each other?* — each answered by
one small, composable realm.

`relay` is the one with no trust primitive of its own. It is a channel, and the only thing
it adds is that the sender is checked by consensus rather than asserted by the sender.

These are **examples**: they demonstrate an idea and an API shape, and are
CI-tested against gno master like the rest of the repo, but longevity,
completeness and production fitness are explicitly **not** goals.

See the repository [README](../../../README.md) and
[DISCLAIMER](../../../DISCLAIMER.md) for the full catalog and terms.
