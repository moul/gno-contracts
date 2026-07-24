package escrow

import (
	"chain"
	"chain/runtime/unsafe"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// State constants for a deal's lifecycle.
const (
	StateOpen     = "Open"
	StateSettled  = "Settled"
	StateCanceled = "Canceled"
)

// Deal is a 2-party escrow record. Accounting only: no funds move,
// this tracks agreement and mutual confirmation between two parties.
type Deal struct {
	ID           int
	Creator      address
	Counterparty address
	Terms        string
	State        string
	CreatorOK    bool
	CounterOK    bool
}

var (
	deals  = avl.NewTree() // id (string) -> *Deal
	nextID int
)

var (
	errNotFound   = errors.New("escrow: deal not found")
	errNotParty   = errors.New("escrow: caller is not a party to this deal")
	errNotOpen    = errors.New("escrow: deal is not open")
	errNotCreator = errors.New("escrow: only the creator can cancel")
	errBadAddr    = errors.New("escrow: invalid counterparty address")
	errSelfDeal   = errors.New("escrow: counterparty must differ from creator")
)

// Create opens a new escrow deal between the caller (creator) and the
// given counterparty, governed by a free-form terms string. Returns the
// new deal id. Panics on invalid input (cross-realm abort).
func Create(cur realm, counterparty address, terms string) int {
	if !counterparty.IsValid() {
		panic(errBadAddr)
	}
	creator := unsafe.PreviousRealm().Address()
	if counterparty == creator {
		panic(errSelfDeal)
	}

	id := nextID
	nextID++

	d := &Deal{
		ID:           id,
		Creator:      creator,
		Counterparty: counterparty,
		Terms:        terms,
		State:        StateOpen,
	}
	deals.Set(strconv.Itoa(id), d)

	chain.Emit("Created", "id", strconv.Itoa(id),
		"creator", creator.String(), "counterparty", counterparty.String())
	return id
}

// Confirm records confirmation by whichever party is calling. Once both
// parties have confirmed, the deal transitions to Settled.
func Confirm(cur realm, id int) {
	d := mustGet(id)
	if d.State != StateOpen {
		panic(errNotOpen)
	}
	caller := unsafe.PreviousRealm().Address()

	switch caller {
	case d.Creator:
		d.CreatorOK = true
	case d.Counterparty:
		d.CounterOK = true
	default:
		panic(errNotParty)
	}

	chain.Emit("Confirmed", "id", strconv.Itoa(id), "party", caller.String())

	if d.CreatorOK && d.CounterOK {
		d.State = StateSettled
		chain.Emit("Settled", "id", strconv.Itoa(id))
	}
}

// Cancel voids an open deal. Only the creator may cancel, and only
// before the deal has settled.
func Cancel(cur realm, id int) {
	d := mustGet(id)
	if d.State != StateOpen {
		panic(errNotOpen)
	}
	caller := unsafe.PreviousRealm().Address()
	if caller != d.Creator {
		panic(errNotCreator)
	}
	d.State = StateCanceled
	chain.Emit("Canceled", "id", strconv.Itoa(id))
}

func mustGet(id int) *Deal {
	v, ok := deals.Get(strconv.Itoa(id))
	if !ok {
		panic(errNotFound)
	}
	return v.(*Deal)
}

// Render lists all escrow deals with their parties, terms, and state.
// When path is a numeric id, renders just that deal.
func Render(path string) string {
	path = strings.TrimSpace(strings.Trim(path, "/"))
	if path != "" {
		if id, err := strconv.Atoi(path); err == nil {
			v, ok := deals.Get(strconv.Itoa(id))
			if !ok {
				return "# Escrow\n\nDeal `" + path + "` not found.\n"
			}
			return renderOne(v.(*Deal))
		}
	}

	var b strings.Builder
	b.WriteString("# Escrow\n\n")
	b.WriteString("2-party escrow deals (accounting only — no funds move).\n\n")

	if deals.Size() == 0 {
		b.WriteString("_No deals yet._\n")
		return b.String()
	}

	b.WriteString("| ID | Creator | Counterparty | State | Confirmations | Terms |\n")
	b.WriteString("|----|---------|--------------|-------|---------------|-------|\n")
	deals.Iterate("", "", func(_ string, v interface{}) bool {
		d := v.(*Deal)
		b.WriteString("| " + strconv.Itoa(d.ID) +
			" | " + short(d.Creator) +
			" | " + short(d.Counterparty) +
			" | " + d.State +
			" | " + confs(d) +
			" | " + escapePipe(d.Terms) + " |\n")
		return false
	})
	return b.String()
}

func renderOne(d *Deal) string {
	var b strings.Builder
	b.WriteString("# Escrow Deal #" + strconv.Itoa(d.ID) + "\n\n")
	b.WriteString("- **State:** " + d.State + "\n")
	b.WriteString("- **Creator:** " + d.Creator.String() + " (" + yn(d.CreatorOK) + ")\n")
	b.WriteString("- **Counterparty:** " + d.Counterparty.String() + " (" + yn(d.CounterOK) + ")\n")
	b.WriteString("- **Terms:** " + d.Terms + "\n")
	return b.String()
}

func confs(d *Deal) string {
	n := 0
	if d.CreatorOK {
		n++
	}
	if d.CounterOK {
		n++
	}
	return strconv.Itoa(n) + "/2"
}

func yn(b bool) string {
	if b {
		return "confirmed"
	}
	return "pending"
}

func short(a address) string {
	s := a.String()
	if len(s) <= 12 {
		return s
	}
	return s[:8] + "…" + s[len(s)-4:]
}

func escapePipe(s string) string {
	return strings.ReplaceAll(s, "|", "\\|")
}
