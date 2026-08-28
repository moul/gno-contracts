# r/moul/x/daily — experimental, auto-generated dapps

This folder holds **experimental gno.land realms generated automatically by an
MCP-driven agent, with (almost) no human supervision.**

They exist to:

- exercise the **gno MCP server** and its tools (key management, faucet, `addpkg`,
  `render`, `eval`, …) end-to-end;
- stress the **daily-dapp** generation pipeline (random idea → Gno code → on-chain
  deploy → announce), including its dry-run/verify and self-funding machinery;
- produce a broad, varied corpus of real-world-ish Gno code as **content for our
  compilers, linters, formatters and other tooling** to chew on.

## What to expect

- These are **experiments, not products.** They are **not audited**, may be buggy,
  stylistically rough, or plain silly. Don't treat them as reference patterns and
  don't rely on them for anything.
- The `x/` segment stands for **exploration / experimental** — a deliberate sandbox
  kept separate from the real, curated `r/moul/*` contracts.
- Each realm was generated targeting the sapphire testnet (gno `0.9`, sapphire-era API:
  `chain`, `chain/runtime`, `chain/runtime/unsafe`, `gno.land/p/nt/avl/v0`, …) and
  most were deployed live under an agent-controlled address; the copies here are the
  source.

## Layout

Each realm lives at `r/moul/x/daily/<name>/v1/` (versioned to satisfy the repo's
`/vN` rule, even though these are throwaway experiments) with its `.gno` sources,
tests, a `gnomod.toml`, and a short per-package README that links back here.

---

_Maintained by moul. This README is the canonical explainer for the folder and can
be updated freely; the per-package disclaimers link here._
