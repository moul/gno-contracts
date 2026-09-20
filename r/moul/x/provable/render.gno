package provable

import (
	"strconv"
	"strings"
)

// Render serves the overview at "" and one entry with its proof at
// "entry/<index>".
//
// Output is a fixed size: the entry list is capped at renderEntries, so a full
// log still renders. The chain caps a query at maxGasQuery and a reader cannot
// raise it, so an unbounded Render is a permanently unreadable page.
func Render(path string) string {
	path = strings.TrimSpace(path)
	if strings.HasPrefix(path, "entry/") {
		return renderEntry(strings.TrimPrefix(path, "entry/"))
	}
	return renderIndex()
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# provable\n\n")
	b.WriteString("What gno.land can and cannot prove about itself, demonstrated rather than asserted.\n\n")

	b.WriteString("## The log\n\n")
	b.WriteString("An append-only Merkle mountain range. Appending costs O(log n) hashes and never rebuilds.\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Entries | " + strconv.Itoa(log.Size()) + " / " + strconv.Itoa(MaxEntries) + " |\n")
	b.WriteString("| Stored hashes | " + strconv.Itoa(log.Nodes()) + " |\n")
	b.WriteString("| Peaks | " + strconv.Itoa(len(log.PeakHashes())) + " |\n")
	b.WriteString("| Root | `" + rootOrDash() + "` |\n\n")

	b.WriteString("This root is also the Tendermint simple-tree root over the same entries, so any\n")
	b.WriteString("Tendermint verifier accepts it. `Verify` and `VerifyFixed` check the two proof\n")
	b.WriteString("encodings against it.\n\n")

	b.WriteString("## What the chain can prove\n\n")
	b.WriteString("`gno.land/pkg/gnoland/app.go` mounts exactly two stores. One is IAVL and merkleized,\n")
	b.WriteString("the other is a plain dbadapter whose `Commit` is documented as *\"Always returns a zero\n")
	b.WriteString("commitID, as dbadapter store doesn't merkleize\"*.\n\n")
	b.WriteString("| Data | Store | Provable against the app hash |\n|---|---|---|\n")
	b.WriteString("| Package source | iavl | yes |\n")
	b.WriteString("| Account balances | iavl | yes |\n")
	b.WriteString("| Escaped object hashes (cross-realm) | iavl | yes, the hash only |\n")
	b.WriteString("| Realm objects, types, realm metadata | base | **no** |\n")
	b.WriteString("| **This log** | base | **no** |\n\n")

	b.WriteString("## What that means here\n\n")
	b.WriteString("A proof from this realm says *this entry is consistent with the root this realm\n")
	b.WriteString("published*. It cannot say *this root is the chain's own*, for two independent reasons:\n\n")
	b.WriteString("1. Realm state is not merkleized, so there is no state proof to produce.\n")
	b.WriteString("2. `chain/runtime` exposes `ChainID`, `ChainDomain`, `ChainHeight` and `GetSessionInfo`\n")
	b.WriteString("   and nothing else. No app hash, no block hash, no header. A realm has no trusted\n")
	b.WriteString("   root to check anything against.\n\n")
	b.WriteString("Anything built on Merkle proofs in a gno realm is trust-minimised relative to a\n")
	b.WriteString("committed root, never trustless. Saying otherwise would be the interesting-sounding\n")
	b.WriteString("half of a true story.\n\n")

	b.WriteString("## Entries\n\n")
	if log.Size() == 0 {
		b.WriteString("_Empty. Call `Append(\"something\")`._\n")
		return b.String()
	}
	start := 0
	if len(entries) > renderEntries {
		start = len(entries) - renderEntries
		b.WriteString("Showing the last " + strconv.Itoa(renderEntries) + " of " + strconv.Itoa(len(entries)) + ".\n\n")
	}
	b.WriteString("| # | Entry |\n|---|---|\n")
	for i := start; i < len(entries); i++ {
		b.WriteString("| [" + strconv.Itoa(i) + "](/r/moul/x/provable/v0:entry/" + strconv.Itoa(i) + ") | " + entries[i] + " |\n")
	}
	return b.String()
}

func renderEntry(raw string) string {
	i, err := strconv.Atoi(raw)
	if err != nil || i < 0 || i >= len(entries) {
		return "# provable\n\nNo entry `" + raw + "`.\n"
	}
	path, before, after := ProofOf(i)
	var b strings.Builder
	b.WriteString("# provable: entry " + strconv.Itoa(i) + "\n\n")
	b.WriteString("```\n" + entries[i] + "\n```\n\n")
	b.WriteString("## Inclusion proof\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Index | " + strconv.Itoa(i) + " |\n")
	b.WriteString("| Total | " + strconv.Itoa(log.Size()) + " |\n")
	b.WriteString("| Path | `" + orDash(path) + "` |\n")
	b.WriteString("| Before | `" + orDash(before) + "` |\n")
	b.WriteString("| After | `" + orDash(after) + "` |\n")
	b.WriteString("| Root | `" + rootOrDash() + "` |\n\n")
	b.WriteString("Valid against that root only. The next `Append` moves it.\n")
	return b.String()
}

func rootOrDash() string { return orDash(Root()) }

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
