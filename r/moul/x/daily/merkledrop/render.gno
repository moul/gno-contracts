package merkledrop

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/merkle/v0"
	"gno.land/p/nt/avl/v0"
)

// demoAllocations is the example drop seeded at deploy, so the realm renders
// working proofs instead of an empty page. A real drop calls SetDrop with a
// root computed off chain and stores no allocations at all.
var demoAllocations = []Allocation{
	{Address: "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5", Amount: 100},
	{Address: "g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj", Amount: 250},
	{Address: "g1manfred47kzduec920z88wfr64ylksmdcedlf5", Amount: 500},
	{Address: "g1sss9uxef4l6lwc0mxq8n5v0e4vqpml7c39cxq2", Amount: 750},
}

// seed installs the example drop. Also called by the example tests: realm
// globals persist for a whole test binary and examples run after every Test,
// so a pinned Render must start from a known state.
func seed() {
	demo = demoAllocations
	tree := demoTree()
	root = tree.Root()
	total = len(demo)
	closesAt = 0
	claimed, paid = avl.Tree{}, 0
}

func demoTree() *merkle.Tree {
	leaves := make([][]byte, len(demo))
	for i, a := range demo {
		leaves[i] = []byte(Leaf(i, a.Address, a.Amount))
	}
	return merkle.New(leaves)
}

// DemoProof returns the proof for one seeded allocation, so the drop can be
// exercised end to end without an off-chain generator. It is empty once a real
// drop replaces the seeded one.
func DemoProof(index int) string {
	if index < 0 || index >= len(demo) {
		return ""
	}
	p, err := demoTree().Proof(index)
	if err != nil {
		return ""
	}
	return p.Hex()
}

// Render serves the drop overview at "" and one allocation at "proof/<index>".
func Render(path string) string {
	path = strings.TrimSpace(path)
	if strings.HasPrefix(path, "proof/") {
		return renderProof(strings.TrimPrefix(path, "proof/"))
	}
	return renderIndex()
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# MerkleDrop v1\n\n")
	b.WriteString("A Merkle root gates an airdrop that pays real ugnot. Successor to\n")
	b.WriteString("[v0](/r/moul/x/daily/merkledrop/v0), which moved no coins and whose proof scheme was\n")
	b.WriteString("safe only by accident of encoding lengths.\n\n")

	b.WriteString("## Drop\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	if len(root) == 0 {
		b.WriteString("| Root | _none configured_ |\n")
	} else {
		b.WriteString("| Root | `" + Root() + "` |\n")
	}
	b.WriteString("| Allocations | " + strconv.Itoa(total) + " |\n")
	b.WriteString("| Closes at height | " + closesLabel() + " |\n")
	b.WriteString("| Claimed | " + strconv.Itoa(Claims()) + " |\n")
	b.WriteString("| Paid out | " + strconv.FormatInt(Paid(), 10) + " ugnot |\n")
	b.WriteString("| Funding address | `" + Address().String() + "` |\n\n")

	b.WriteString("## How it differs from v0\n\n")
	b.WriteString("1. **Domain separated leaves.** v0 hashed leaves bare and combined nodes\n")
	b.WriteString("   commutatively, so an inner-node hash was also a valid leaf hash. It was not\n")
	b.WriteString("   exploitable, but only because a v0 leaf preimage tops out at 61 bytes while an\n")
	b.WriteString("   inner preimage is always 64. v1 tags leaves `0x00` and inner nodes `0x01`.\n")
	b.WriteString("2. **Proofs bound to a position.** v0 folded a sibling list of any length. v1\n")
	b.WriteString("   carries index and total, rebuilds the tree shape, and caps the depth.\n")
	b.WriteString("3. **A settable root and a closing height.** v0's root was a `const`.\n")
	b.WriteString("4. **Real coins.** v0 kept a `uint64` ledger and moved nothing.\n\n")

	b.WriteString("## Leaf encoding\n\n")
	b.WriteString("Reproduce this off chain to rebuild the tree:\n\n")
	b.WriteString("```\n")
	b.WriteString("leaf = \"" + leafPrefix + "|<index>|<address>|<amount>\"\n")
	b.WriteString("tree = Tendermint simple tree, leaf 0x00, inner 0x01\n")
	b.WriteString("```\n\n")

	if len(demo) == 0 {
		b.WriteString("## Allocations\n\n")
		b.WriteString("A live drop commits only its root, so there is nothing to list here.\n")
		return b.String()
	}
	b.WriteString("## Example allocations\n\n")
	b.WriteString("Seeded at deploy so the drop can be exercised without a generator. A live drop\n")
	b.WriteString("commits only a root and stores none of this.\n\n")
	b.WriteString("| # | Address | Amount | Claimed |\n|---|---|---|---|\n")
	for i, a := range demo {
		b.WriteString("| [" + strconv.Itoa(i) + "](/r/moul/x/daily/merkledrop/v1:proof/" + strconv.Itoa(i) + ") | `" +
			a.Address.String() + "` | " + strconv.FormatInt(a.Amount, 10) + " | " + yesNo(HasClaimed(i)) + " |\n")
	}
	return b.String()
}

func renderProof(raw string) string {
	i, err := strconv.Atoi(raw)
	if err != nil || i < 0 || i >= len(demo) {
		return "# MerkleDrop v1\n\nNo allocation `" + raw + "`.\n"
	}
	a := demo[i]
	var b strings.Builder
	b.WriteString("# MerkleDrop v1: allocation " + strconv.Itoa(i) + "\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Index | " + strconv.Itoa(i) + " |\n")
	b.WriteString("| Total | " + strconv.Itoa(total) + " |\n")
	b.WriteString("| Address | `" + a.Address.String() + "` |\n")
	b.WriteString("| Amount | " + strconv.FormatInt(a.Amount, 10) + " ugnot |\n")
	b.WriteString("| Claimed | " + yesNo(HasClaimed(i)) + " |\n\n")
	b.WriteString("## Leaf\n\n")
	b.WriteString("```\n" + Leaf(i, a.Address, a.Amount) + "\n```\n\n")
	b.WriteString("## Proof\n\n")
	b.WriteString("```\n" + DemoProof(i) + "\n```\n\n")
	b.WriteString("Only `" + a.Address.String() + "` can spend it: the address is inside the leaf, so\n")
	b.WriteString("the proof verifies for no one else.\n")
	return b.String()
}

func closesLabel() string {
	if closesAt == 0 {
		return "never"
	}
	return strconv.FormatInt(closesAt, 10)
}

func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
