package config

import (
	"testing"

	"chain"

	"gno.land/p/nt/uassert/v0"
)

// v2Path is a plausible next version. Nothing is deployed there; the tests
// only need the address the path resolves to, which is what an incoming
// relayed call is actually compared against.
const v2Path = "gno.land/r/moul/config/v2"

func v2Addr() address { return chain.PackageAddress(v2Path) }

func TestAllowAndRevokeProxy(cur realm, t *testing.T) {
	resetSettings()
	uassert.Equal(t, 0, len(ListProxies()))
	uassert.False(t, IsProxy(v2Addr()))

	testing.SetRealm(testing.NewUserRealm(originAddr))
	AllowProxy(cross(cur), v2Path)

	uassert.True(t, IsProxy(v2Addr()))
	uassert.Equal(t, 1, len(ListProxies()))
	uassert.Equal(t, v2Path, ListProxies()[0])

	testing.SetRealm(testing.NewUserRealm(originAddr))
	RevokeProxy(cross(cur), v2Path)
	uassert.False(t, IsProxy(v2Addr()))
	uassert.Equal(t, 0, len(ListProxies()))
}

func TestProxyRegistrationIsManagerOnly(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewUserRealm(nonManagerAddr))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		AllowProxy(cross(cur), v2Path)
	})
	uassert.False(t, IsProxy(v2Addr()), "a rejected registration leaves nothing behind")
}

// TestProxyPathMustBeASiblingVersion keeps a fat-fingered AllowProxy from
// becoming a standing write grant to an unrelated realm.
func TestProxyPathMustBeASiblingVersion(cur realm, t *testing.T) {
	resetSettings()

	bad := []string{
		"gno.land/r/someone/evil",
		"gno.land/r/moul/home",
		"gno.land/r/moul/configuration/v2", // prefix-adjacent, not a sibling
		"gno.land/r/moul/config/v",         // no number
		"gno.land/r/moul/config/vnext",
		"gno.land/r/moul/config/v2/sub",
		"",
	}
	for _, path := range bad {
		testing.SetRealm(testing.NewUserRealm(originAddr))
		uassert.AbortsContains(t, cur, "must be a later version", func() {
			AllowProxy(cross(cur), path)
		})
	}
	uassert.Equal(t, 0, len(ListProxies()))
}

func TestRevokeUnknownProxyAborts(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.AbortsWithMessage(t, cur, "no such proxy: "+v2Path, func() {
		RevokeProxy(cross(cur), v2Path)
	})
}

// TestRelayNeedsRegistration is the first of the relay's two checks: without
// it, any realm could claim to be acting for any principal.
func TestRelayNeedsRegistration(cur realm, t *testing.T) {
	resetSettings()

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "not a registered proxy", func() {
		SetAs(cross(cur), originAddr, "some.key", "value")
	})
	uassert.Equal(t, 0, Size())
}

// TestRelayStillChecksThePrincipal is the second check, and the reason a proxy
// is not simply an unconditional bypass: the member list stays the single
// answer to "who may change config", for every version at once.
func TestRelayStillChecksThePrincipal(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	AllowProxy(cross(cur), v2Path)

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		SetAs(cross(cur), nonManagerAddr, "some.key", "value")
	})
	uassert.Equal(t, 0, Size())

	// An empty principal is not a wildcard.
	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "no principal", func() {
		SetAs(cross(cur), "", "some.key", "value")
	})
}

// TestRelayWritesTheSameState is the property the whole version chain exists
// for: a write arriving through a later version lands in exactly the store
// that a direct write lands in, so v1 and v2 readers never disagree.
func TestRelayWritesTheSameState(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	AllowProxy(cross(cur), v2Path)

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	SetAs(cross(cur), originAddr, KeyMygnoscanURL, "https://scan.example.com")

	uassert.Equal(t, "https://scan.example.com", Get(KeyMygnoscanURL))
	uassert.Equal(t, "https://scan.example.com", MygnoscanURL(),
		"the typed accessor sees the relayed write too")

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	UnsetAs(cross(cur), originAddr, KeyMygnoscanURL)
	uassert.False(t, Has(KeyMygnoscanURL))
}

// TestRelayValidatesLikeTheDirectPath: a relay is a different door, not a
// different set of rules. Key shape and value grammar are checked identically.
func TestRelayValidatesLikeTheDirectPath(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	AllowProxy(cross(cur), v2Path)

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "invalid key", func() {
		SetAs(cross(cur), originAddr, "Bad Key", "value")
	})

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "invalid pause value", func() {
		SetAs(cross(cur), originAddr, KeyPause, "yes")
	})
}

// TestRevokedProxyCannotWrite: revocation is the emergency brake on the relay
// itself, so it has to bite immediately.
func TestRevokedProxyCannotWrite(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	AllowProxy(cross(cur), v2Path)

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	SetAs(cross(cur), originAddr, "some.key", "before")

	testing.SetRealm(testing.NewUserRealm(originAddr))
	RevokeProxy(cross(cur), v2Path)

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "not a registered proxy", func() {
		SetAs(cross(cur), originAddr, "some.key", "after")
	})
	uassert.Equal(t, "before", Get("some.key"))
}

// TestManagerChangesReachTheRelay is what makes one member list serve every
// version: adding a manager here works through v2 with no further deploys.
func TestManagerChangesReachTheRelay(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	AllowProxy(cross(cur), v2Path)

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		SetAs(cross(cur), manager1Addr, "some.key", "value")
	})

	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.NoError(t, AddManager(cross(cur), manager1Addr))

	testing.SetRealm(testing.NewCodeRealm(v2Path))
	SetAs(cross(cur), manager1Addr, "some.key", "value")
	uassert.Equal(t, "value", Get("some.key"))
}

// ExampleRender_proxies pins the section that only exists once a later version
// is registered, which is the state this realm spends most of its life NOT in.
func ExampleRender_proxies() {
	resetSettings()
	proxies.Set(v2Path, chain.PackageAddress(v2Path))
	print(Render(""))
	// Output:
	// # gno.land/r/moul/config
	//
	// moul's settings, read by his other realms. rev 0 · 0 setting(s)
	//
	// ## Settings
	//
	// _none set; every reader is on its built-in default_
	//
	// ## Pause
	//
	// _running; no global pause_
	//
	// ## Authority
	//
	// `member_authority[g1daexjemfde047h6lta047h6lta047h6ld2pug6]`
	//
	// ## Proxies
	//
	// Later versions of this realm that may relay a write:
	//
	// - `gno.land/r/moul/config/v2`
	//
	// ---
	//
	// [explorer](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1) · [source](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1?tab=source) · [calls](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1?tab=calls) · [deps](https://mygnoscan.moul.p2p.team/realm/r/moul/config/v1?tab=deps)
}
