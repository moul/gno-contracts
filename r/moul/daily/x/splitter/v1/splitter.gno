// Package splitter is a share-based payment splitter for gno.land.
//
// It is an accounting-only port of the Solidity PaymentSplitter pattern:
// no real coins move. A group is registered with a list of payees and a
// matching list of integer shares. Income recorded against a group is
// pooled, and each payee is owed a slice of that pool proportional to
// their shares: owed = pool * share / totalShares.
package splitter

import (
	"errors"
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// payee is a single share holder inside a group.
type payee struct {
	addr   address
	shares int
}

// group is one payment-splitting arrangement.
type group struct {
	id          int
	owner       address
	payees      []payee
	totalShares int
	pool        int // total income recorded, in abstract units
}

var (
	groups   avl.Tree // id (zero-padded string) -> *group
	nextID   int
	errEmpty = errors.New("splitter: no payees")
)

// Register creates a new group from comma-separated payees and shares.
// payees:  "g1abc...,g1def..."  (addresses)
// shares:  "3,1"                (positive integers, same count as payees)
// Returns the new group id. Panics on malformed input.
func Register(cur realm, payees string, shares string) int {
	caller := unsafe.PreviousRealm().Address()

	addrParts := splitTrim(payees)
	shareParts := splitTrim(shares)

	if len(addrParts) == 0 {
		panic(errEmpty)
	}
	if len(addrParts) != len(shareParts) {
		panic("splitter: payees and shares count mismatch")
	}

	g := &group{
		id:    nextID,
		owner: caller,
	}
	for i := range addrParts {
		if addrParts[i] == "" {
			panic("splitter: empty payee address")
		}
		s, err := strconv.Atoi(shareParts[i])
		if err != nil {
			panic("splitter: bad share value: " + shareParts[i])
		}
		if s <= 0 {
			panic("splitter: share must be positive")
		}
		g.payees = append(g.payees, payee{
			addr:   address(addrParts[i]),
			shares: s,
		})
		g.totalShares += s
	}

	groups.Set(key(g.id), g)
	nextID++

	chain.Emit(
		"GroupRegistered",
		"id", strconv.Itoa(g.id),
		"payees", strconv.Itoa(len(g.payees)),
		"totalShares", strconv.Itoa(g.totalShares),
	)
	return g.id
}

// RecordIncome adds amount to the pool of group id. amount must be positive.
func RecordIncome(cur realm, id int, amount int) {
	if amount <= 0 {
		panic("splitter: amount must be positive")
	}
	v, ok := groups.Get(key(id))
	if !ok {
		panic("splitter: unknown group id: " + strconv.Itoa(id))
	}
	g := v.(*group)
	g.pool += amount
	groups.Set(key(id), g)

	chain.Emit(
		"IncomeRecorded",
		"id", strconv.Itoa(id),
		"amount", strconv.Itoa(amount),
		"pool", strconv.Itoa(g.pool),
	)
}

// owed returns the amount owed to a payee: pool * shares / totalShares.
func (g *group) owed(p payee) int {
	if g.totalShares == 0 {
		return 0
	}
	return g.pool * p.shares / g.totalShares
}

// Render shows all groups, their payees, shares, and computed owed amounts.
func Render(path string) string {
	if groups.Size() == 0 {
		return "# Payment Splitter\n\n_No groups registered yet._\n"
	}

	var b strings.Builder
	b.WriteString("# Payment Splitter\n\n")
	b.WriteString("Share-based accounting. `owed = pool * share / totalShares`.\n\n")

	groups.Iterate("", "", func(k string, v interface{}) bool {
		g := v.(*group)
		b.WriteString("## Group #" + strconv.Itoa(g.id) + "\n\n")
		b.WriteString("- Owner: `" + g.owner.String() + "`\n")
		b.WriteString("- Pool: " + strconv.Itoa(g.pool) + "\n")
		b.WriteString("- Total shares: " + strconv.Itoa(g.totalShares) + "\n\n")

		b.WriteString("| Payee | Shares | Owed |\n")
		b.WriteString("|---|---:|---:|\n")
		distributed := 0
		for _, p := range g.payees {
			o := g.owed(p)
			distributed += o
			b.WriteString("| `" + p.addr.String() + "` | " +
				strconv.Itoa(p.shares) + " | " + strconv.Itoa(o) + " |\n")
		}
		remainder := g.pool - distributed
		if remainder > 0 {
			b.WriteString("| _remainder (rounding)_ | | " +
				strconv.Itoa(remainder) + " |\n")
		}
		b.WriteString("\n")
		return false
	})

	return b.String()
}

// splitTrim splits on commas and trims whitespace around each element.
func splitTrim(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		out = append(out, strings.TrimSpace(p))
	}
	return out
}

// key produces a zero-padded, lexicographically-sortable avl key for an id,
// so Render iterates groups in ascending numeric order.
func key(id int) string {
	s := strconv.Itoa(id)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}
