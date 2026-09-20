// Package capwallet issues narrow, bounded, revocable capabilities to
// agents — instead of handing an agent a wallet key and hoping its prompt
// stays safe.
//
// The demo makes three ideas that are usually conflated stand apart:
//
//   - identity      — "this is agent Percy"
//   - authorization — "Percy may call this function on this realm"
//   - approval      — "Percy may do it at most N times, for ≤ M coins,
//                      before block H, and I can revoke it at any moment"
//
// A capability is the third thing: a least-privilege grant with a ceiling,
// an expiry, a use counter and a kill switch. Other realms consult
// Authorized() before honoring an agent action; the granter revokes with
// one call the instant something looks wrong.
package capwallet

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/nt/ufmt/v0"
)

// Use records one exercise of a capability.
type Use struct {
	By     address
	Coins  int64
	Height int64
}

// Capability is a least-privilege grant from a granter to a principal.
type Capability struct {
	ID            uint64
	Granter       address
	Principal     address // the only address that may exercise it
	TargetRealm   string  // realm the capability is scoped to
	Function      string  // function the capability authorizes
	MaxCoins      int64   // per-exercise ceiling in ugnot (0 = none allowed)
	ValidUntil    int64   // block height after which it expires (0 = never)
	RemainingUses uint32  // exercises left (0 = exhausted)
	ArgsPolicy    string  // human-readable note on allowed arguments
	Revoked       bool
	GrantedAt     int64
	Uses          []Use
}

var caps []*Capability // index 0 => ID 1

// Grant issues a capability. The caller becomes its granter and can revoke
// it later. validUntil is an absolute block height (0 = no expiry).
func Grant(
	cur realm,
	principal address,
	targetRealm, function string,
	maxCoins, validUntil int64,
	uses uint32,
	argsPolicy string,
) uint64 {
	assert(targetRealm != "" && function != "", "target realm and function required")
	assert(uses > 0, "must grant at least one use")

	id := uint64(len(caps)) + 1
	c := &Capability{
		ID:            id,
		Granter:       cur.Previous().Address(),
		Principal:     principal,
		TargetRealm:   targetRealm,
		Function:      function,
		MaxCoins:      maxCoins,
		ValidUntil:    validUntil,
		RemainingUses: uses,
		ArgsPolicy:    argsPolicy,
		GrantedAt:     runtime.ChainHeight(),
	}
	caps = append(caps, c)
	chain.Emit("CapabilityGranted",
		"id", ufmt.Sprintf("%d", id),
		"principal", principal.String(),
		"target", targetRealm+"."+function,
	)
	return id
}

// Exercise consumes one use of a capability. Only the principal may call it,
// and every bound is checked: not revoked, not expired, uses remaining, and
// coins within the ceiling. On success the use is recorded and the counter
// decremented.
func Exercise(cur realm, id uint64, coins int64) {
	c := mustGet(id)
	caller := cur.Previous().Address()
	assert(caller == c.Principal, "caller is not the capability principal")
	assertUsable(c)
	assert(coins <= c.MaxCoins, ufmt.Sprintf("coins %d exceed capability ceiling %d", coins, c.MaxCoins))

	c.RemainingUses--
	c.Uses = append(c.Uses, Use{By: caller, Coins: coins, Height: runtime.ChainHeight()})
	chain.Emit("CapabilityExercised",
		"id", ufmt.Sprintf("%d", id),
		"coins", ufmt.Sprintf("%d", coins),
		"remaining", ufmt.Sprintf("%d", c.RemainingUses),
	)
}

// Revoke disables a capability immediately. Only the granter may revoke.
func Revoke(cur realm, id uint64) {
	c := mustGet(id)
	assert(cur.Previous().Address() == c.Granter, "only the granter may revoke")
	c.Revoked = true
	chain.Emit("CapabilityRevoked", "id", ufmt.Sprintf("%d", id))
}

// ---- read-only API for gating realms ----

// Authorized reports whether principal may exercise capability id for the
// given coin amount right now — the check a target realm runs before acting.
// It never mutates state or consumes a use.
func Authorized(id uint64, principal address, coins int64) bool {
	if id < 1 || id > uint64(len(caps)) {
		return false
	}
	c := caps[id-1]
	if c.Principal != principal || !usable(c) {
		return false
	}
	return coins <= c.MaxCoins
}

// Get returns a copy of a capability.
func Get(id uint64) Capability { return *mustGet(id) }

// Count returns the number of capabilities issued.
func Count() int { return len(caps) }

// ---- internal ----

func usable(c *Capability) bool {
	if c.Revoked || c.RemainingUses == 0 {
		return false
	}
	if c.ValidUntil != 0 && runtime.ChainHeight() > c.ValidUntil {
		return false
	}
	return true
}

func assertUsable(c *Capability) {
	assert(!c.Revoked, "capability revoked")
	assert(c.RemainingUses > 0, "capability exhausted")
	assert(c.ValidUntil == 0 || runtime.ChainHeight() <= c.ValidUntil, "capability expired")
}

func mustGet(id uint64) *Capability {
	assert(id >= 1 && id <= uint64(len(caps)), "unknown capability")
	return caps[id-1]
}

func assert(cond bool, msg string) {
	if !cond {
		panic(msg)
	}
}

// Render shows all capabilities, or one capability's detail + usage at :<id>.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderCap(parseID(path))
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# Capability Wallet\n\n")
	sb.WriteString("_Don't give an agent a wallet. Give it a capability._\n\n")
	if len(caps) == 0 {
		sb.WriteString("_No capabilities granted yet._\n")
		return sb.String()
	}
	sb.WriteString("| # | Principal | Scope | Ceiling | Uses left | State |\n")
	sb.WriteString("|---|---|---|---|---|---|\n")
	for _, c := range caps {
		sb.WriteString(ufmt.Sprintf("| [%d](/r/moul/agents/capwallet/v0:%d) | %s | `%s.%s` | %d ugnot | %d | %s |\n",
			c.ID, c.ID, short(c.Principal), c.TargetRealm, c.Function, c.MaxCoins, c.RemainingUses, state(c)))
	}
	return sb.String()
}

func renderCap(id uint64) string {
	c := mustGet(id)
	var sb strings.Builder
	sb.WriteString(ufmt.Sprintf("# Capability #%d\n\n", c.ID))
	sb.WriteString(ufmt.Sprintf("- **State:** %s\n", state(c)))
	sb.WriteString(ufmt.Sprintf("- **Granter:** %s\n", c.Granter.String()))
	sb.WriteString(ufmt.Sprintf("- **Principal:** %s\n", c.Principal.String()))
	sb.WriteString(ufmt.Sprintf("- **Scope:** `%s.%s`\n", c.TargetRealm, c.Function))
	sb.WriteString(ufmt.Sprintf("- **Per-use ceiling:** %d ugnot\n", c.MaxCoins))
	if c.ValidUntil == 0 {
		sb.WriteString("- **Expires:** never\n")
	} else {
		sb.WriteString(ufmt.Sprintf("- **Expires at height:** %d (now %d)\n", c.ValidUntil, runtime.ChainHeight()))
	}
	sb.WriteString(ufmt.Sprintf("- **Uses remaining:** %d\n", c.RemainingUses))
	sb.WriteString(ufmt.Sprintf("- **Args policy:** %s\n\n", c.ArgsPolicy))

	sb.WriteString(ufmt.Sprintf("## Exercise log (%d)\n\n", len(c.Uses)))
	if len(c.Uses) == 0 {
		sb.WriteString("_Never exercised._\n")
		return sb.String()
	}
	sb.WriteString("| By | Coins | Height |\n|---|---|---|\n")
	for _, u := range c.Uses {
		sb.WriteString(ufmt.Sprintf("| %s | %d | %d |\n", short(u.By), u.Coins, u.Height))
	}
	return sb.String()
}

func state(c *Capability) string {
	if c.Revoked {
		return "🚫 revoked"
	}
	if c.RemainingUses == 0 {
		return "· exhausted"
	}
	if c.ValidUntil != 0 && runtime.ChainHeight() > c.ValidUntil {
		return "⏳ expired"
	}
	return "✅ live"
}

func parseID(s string) uint64 {
	var n uint64
	for i := 0; i < len(s); i++ {
		ch := s[i]
		assert(ch >= '0' && ch <= '9', "invalid capability path: "+s)
		n = n*10 + uint64(ch-'0')
	}
	return n
}

func short(a address) string {
	s := a.String()
	if len(s) <= 12 {
		return s
	}
	return s[:8] + "…" + s[len(s)-4:]
}
