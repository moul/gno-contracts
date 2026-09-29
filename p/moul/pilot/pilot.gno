// Package pilot is a realm-driven account: one realm holds the funds and the
// identity, a key pilots it, and its powers are separate realms installed
// afterwards without ever redeploying it. The gno answer to a Gnosis Safe
// with modules.
//
// An account realm keeps a *Pilot private and hands modules a narrow
// [Account] handle. Everything privileged stays on *Pilot, which is never
// returned, so a module can only reach the two methods it needs.
//
// Two ways to delegate, and they differ in exactly one property:
//
//   - A [Purse] is revocable. Every method on it re-enters the declaring
//     package and re-checks the live roster and budget, so Revoke and
//     SetBudget take effect immediately, even on a purse a module retained.
//   - A sub-identity token (rlm.Sub) is permanent. It lets the module act as
//     "<account>#<subpath>" toward any other realm, which a purse cannot do,
//     but the module can mint a banker from it and keep it forever. Removing
//     the module does not take that back; only emptying the sub-address does.
//     Grant one only to code you have read.
//
// Live instance: r/moul/pilot. Demo module: r/moul/x/pilotdemo.
package pilot

import (
	"chain"
	"chain/banker"
	"errors"
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Module is implemented by a module realm and installed into an account.
// The account never imports it: it learns the module only as this interface.
//
// Run is threaded (the leading int keeps it out of crossing-function
// territory, which a /p/ package may not declare). rlm is whatever the
// account chose to delegate: its own sub-identity token for a trusted
// module, or a zero value when the module was installed purse-only.
type Module interface {
	Name() string
	Run(_ int, rlm realm, args string) string
}

// Grant says what a module was given.
type Grant uint8

const (
	// GrantPurse is funds only, revocable at any time.
	GrantPurse Grant = iota
	// GrantIdentity also lends the account's sub-identity. Permanent.
	GrantIdentity
)

func (g Grant) String() string {
	if g == GrantIdentity {
		return "identity"
	}
	return "purse"
}

var (
	ErrNotOwner     = errors.New("pilot: not the owner")
	ErrNotApproved  = errors.New("pilot: path not approved")
	ErrNotInstalled = errors.New("pilot: module not installed")
	ErrRevoked      = errors.New("pilot: module revoked")
	ErrOverBudget   = errors.New("pilot: over budget")
	ErrStaleRealm   = errors.New("pilot: stale realm value")
	ErrBadName      = errors.New("pilot: a path and a subpath are [a-zA-Z0-9._/-] and not empty")
)

type slot struct {
	mod     Module
	subpath string
	grant   Grant
	budget  int64
	spent   int64
	runs    int64
	live    bool
}

// Pilot is the account. The realm that constructs it owns it and must not
// hand it out; hand out [Pilot.Handle] instead.
type Pilot struct {
	owner   address
	host    string        // the account realm's own pkgpath
	vault   banker.Banker // over host's address, minted once at New
	slots   *avl.Tree     // module pkgpath -> *slot
	handle  *Account
}

// Account is the module-facing half: two methods, both keyed on the calling
// realm's OWN pkgpath, which a realm cannot forge for another.
type Account struct {
	p *Pilot
}

// New builds an account owned by the caller of the crossing function that
// reaches it. Call it once, from the account realm, passing that realm's cur.
func New(_ int, rlm realm) *Pilot {
	assertCurrent(0, rlm)
	p := &Pilot{
		owner: rlm.Previous().Address(),
		host:  rlm.PkgPath(),
		vault: banker.NewBanker(banker.BankerTypeRealmSend, rlm),
		slots: avl.NewTree(),
	}
	p.handle = &Account{p: p}
	return p
}

// assertPlain is why Render can interpolate a path without escaping it: the
// only two strings a caller ever puts in the roster are checked here, at write
// time, against the charset a package path and a subpath are built from.
func assertPlain(s string) {
	if s == "" {
		panic(ErrBadName)
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case c == '.', c == '/', c == '-', c == '_':
		default:
			panic(ErrBadName)
		}
	}
}

func assertCurrent(_ int, rlm realm) {
	if !rlm.IsCurrent() {
		panic(ErrStaleRealm)
	}
}

// AssertOwner panics unless the user behind rlm owns the account. Only the
// account realm may call this: rlm must be its own live cur, so that
// rlm.Previous() is the signer and not some intermediary's caller.
func (p *Pilot) AssertOwner(_ int, rlm realm) {
	assertCurrent(0, rlm)
	if rlm.PkgPath() != p.host {
		panic(ErrNotOwner)
	}
	if rlm.Previous().Address() != p.owner {
		panic(ErrNotOwner)
	}
}

// Handle is what an account realm exposes to modules.
func (p *Pilot) Handle() *Account { return p.handle }

func (p *Pilot) Owner() address { return p.owner }
func (p *Pilot) Host() string   { return p.host }

// Address is the account's main treasury.
func (p *Pilot) Address() address { return chain.PackageAddress(p.host) }

// SubAddress is one module's own treasury, derivable off-chain by anyone.
func (p *Pilot) SubAddress(path string) address {
	s := p.mustSlot(path)
	return chain.DerivePkgSubAddr(p.host, s.subpath)
}

func (p *Pilot) mustSlot(path string) *slot {
	s, ok := p.slots.Get(path).(*slot)
	if !ok {
		panic(ErrNotInstalled)
	}
	return s
}

// Approve authorises a package path to install itself later. The code does
// not have to exist yet, which is the whole point: the account is deployed
// once and learns new powers afterwards.
func (p *Pilot) Approve(_ int, rlm realm, path, subpath string, grant Grant, budget int64) {
	p.AssertOwner(0, rlm)
	assertPlain(path)
	assertPlain(subpath)
	if old, ok := p.slots.Get(path).(*slot); ok {
		old.subpath = subpath
		old.grant = grant
		old.budget = budget
		old.spent = 0 // a new approval is a new allowance
		return
	}
	p.slots.Set(path, &slot{subpath: subpath, grant: grant, budget: budget})
}

// SetBudget is the live knob. It applies to a purse a module already holds.
func (p *Pilot) SetBudget(_ int, rlm realm, path string, budget int64) {
	p.AssertOwner(0, rlm)
	p.mustSlot(path).budget = budget
}

// Revoke stops a module. It takes back its purse immediately; it does NOT
// take back a sub-identity that was granted, nor any banker minted from one.
func (p *Pilot) Revoke(_ int, rlm realm, path string) {
	p.AssertOwner(0, rlm)
	p.mustSlot(path).live = false
}

// Fund moves coins from the account's main treasury into a module's
// sub-treasury. For an identity grant this is the permanent blast radius.
func (p *Pilot) Fund(_ int, rlm realm, path string, amount int64) {
	p.AssertOwner(0, rlm)
	s := p.mustSlot(path)
	p.vault.SendCoins(p.Address(), chain.DerivePkgSubAddr(p.host, s.subpath),
		chain.NewCoins(chain.NewCoin("ugnot", amount)))
}

// Exec drives an installed module. rlm must be the account realm's own live
// cur: an identity grant mints its sub-token from it, which only the account
// realm's namespace can do.
func (p *Pilot) Exec(_ int, rlm realm, path, args string) string {
	p.AssertOwner(0, rlm)
	s := p.mustSlot(path)
	if !s.live {
		panic(ErrRevoked)
	}
	s.runs++
	if s.grant == GrantIdentity {
		return s.mod.Run(0, rlm.Sub(s.subpath), args)
	}
	return s.mod.Run(0, rlm, args)
}

// Register is called BY the module realm, with its own live cur. The account
// reads the path from the runtime and never from an argument.
func (a *Account) Register(_ int, rlm realm, m Module) {
	assertCurrent(0, rlm)
	path := rlm.PkgPath()
	s, ok := a.p.slots.Get(path).(*slot)
	if !ok {
		panic(ErrNotApproved)
	}
	s.mod = m
	s.live = true
}

// PurseFor hands the calling module its revocable purse.
func (a *Account) PurseFor(_ int, rlm realm) *Purse {
	assertCurrent(0, rlm)
	path := rlm.PkgPath()
	if _, ok := a.p.slots.Get(path).(*slot); !ok {
		panic(ErrNotApproved)
	}
	return &Purse{p: a.p, path: path}
}

// Purse is a capability this package declares, so every use of it runs here
// and is re-checked against live state. That is what makes it revocable,
// where a banker minted from a lent realm token is not.
type Purse struct {
	p    *Pilot
	path string
}

// Pay spends from the account's main treasury, against the module's budget.
func (u *Purse) Pay(to address, amount int64) {
	s, ok := u.p.slots.Get(u.path).(*slot)
	if !ok {
		panic(ErrNotInstalled)
	}
	if !s.live {
		panic(ErrRevoked)
	}
	if amount <= 0 || amount > s.budget-s.spent {
		panic(ErrOverBudget)
	}
	s.spent += amount
	u.p.vault.SendCoins(u.p.Address(), to, chain.NewCoins(chain.NewCoin("ugnot", amount)))
}

// Left is what this module may still spend.
func (u *Purse) Left() int64 {
	s, ok := u.p.slots.Get(u.path).(*slot)
	if !ok || !s.live {
		return 0
	}
	return s.budget - s.spent
}

// Render is the account page. The account realm forwards its Render here.
func (p *Pilot) Render(path string) string {
	var sb strings.Builder
	sb.WriteString("# " + p.host + "\n\n")
	sb.WriteString("| | |\n|---|---|\n")
	sb.WriteString("| owner | " + p.owner.String() + " |\n")
	sb.WriteString("| treasury | " + p.Address().String() + " |\n")
	sb.WriteString(ufmt.Sprintf("| balance | %d ugnot |\n\n", p.balance(p.Address())))

	if p.slots.Size() == 0 {
		sb.WriteString("No power installed yet.\n")
		return sb.String()
	}

	sb.WriteString("## powers\n\n")
	sb.WriteString("| path | grant | identity | state | left | runs | sub-treasury |\n")
	sb.WriteString("|---|---|---|---|---|---|---|\n")
	p.slots.Iterate("", "", func(key string, v any) bool {
		s := v.(*slot)
		state := "approved"
		if s.live {
			state = "installed"
		} else if s.mod != nil {
			state = "revoked"
		}
		sub := chain.DerivePkgSubAddr(p.host, s.subpath)
		sb.WriteString(ufmt.Sprintf("| `%s` | %s | `%s#%s` | %s | %d | %d | %d ugnot |\n",
			key, s.grant.String(), p.host, s.subpath, state,
			s.budget-s.spent, s.runs, p.balance(sub)))
		return false
	})
	return sb.String()
}

func (p *Pilot) balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoin(addr, "ugnot")
}
