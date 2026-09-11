package gns

import (
	"testing"
)

func TestTypedRecords(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", alice.String())
	SetText(cross(cur), "alice", "com.github", "moul")
	SetCoinAddress(cross(cur), "alice", "60", []byte{0xde, 0xad})
	SetContentHash(cross(cur), "alice", []byte{0x12, 0x20})
	SetPublicKey(cross(cur), "alice", []byte{0x01, 0x02})
	SetABI(cross(cur), "alice", "application/json", []byte("{}"))
	SetInterface(cross(cur), "alice", "0x1", "gno.land/r/demo/foo")
	SetRecord(cross(cur), "alice", "com.example", "game", []byte("hi"))

	addr, ok := Address("alice")
	isTrue(t, ok, "address set")
	eqStr(t, alice.String(), addr, "address value")

	txt, ok := Text("alice", "com.github")
	isTrue(t, ok, "text set")
	eqStr(t, "moul", txt, "text value")

	coin, ok := CoinAddress("alice", "60")
	isTrue(t, ok, "coin set")
	eqInt(t, 2, int64(len(coin)), "coin len")

	_, ok = ContentHash("alice")
	isTrue(t, ok, "contenthash set")
	_, ok = PublicKey("alice")
	isTrue(t, ok, "pubkey set")
	_, ok = ABI("alice", "application/json")
	isTrue(t, ok, "abi set")

	iface, ok := Interface("alice", "0x1")
	isTrue(t, ok, "interface set")
	eqStr(t, "gno.land/r/demo/foo", iface, "interface value")

	rec, ok := Record("alice", "com.example", "game")
	isTrue(t, ok, "record set")
	eqStr(t, "hi", string(rec), "record value")
}

func TestTextDeletePhysical(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "url", "https://example.com")
	_, ok := Text("alice", "url")
	isTrue(t, ok, "url present")

	// empty value physically removes it
	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "url", "")
	_, ok = Text("alice", "url")
	isFalse(t, ok, "url removed")

	n := getRaw("alice")
	eqInt(t, 0, int64(n.Records.Count), "record count back to zero")
}

func TestRevisionBumps(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	r0 := getRaw("alice").Revision

	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "a", "1")
	r1 := getRaw("alice").Revision
	isTrue(t, r1 > r0, "revision increments on record change")
}

func TestResolveExactAndAncestor(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 100000)

	// open subname policy so we can create a child
	testing.SetRealm(testing.NewUserRealm(alice))
	SetRegistrationPolicy(cross(cur), "company", RegistrationPolicy{Mode: ModeOpen})
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateSubname(cross(cur), "company", "api", alice, SubnameOptions{Duration: 100000})

	// text only on the parent
	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "company", "url", "https://company.example")

	// exact on child: not found
	exact := Resolve("api.company", RecordQuery{Kind: "text", Key1: "url"}, Exact)
	isFalse(t, exact.Found, "exact child has no url")

	// nearest ancestor: inherits from company
	inh := Resolve("api.company", RecordQuery{Kind: "text", Key1: "url"}, NearestAncestor)
	isTrue(t, inh.Found, "ancestor url found")
	eqStr(t, "company", inh.SourceName, "source is parent")
	eqStr(t, "https://company.example", string(inh.Value), "inherited value")
}

// Multiple record updates are done by calling the typed setters repeatedly
// (from a client, via a single `gnokey maketx run` that calls a helper N times);
// GNS does not need an in-realm batch entry point.
func TestSetTTLAndMultipleRecords(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "email", "a@b.co")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "url", "https://x.example")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetTTL(cross(cur), "alice", 3600)

	v, ok := Text("alice", "email")
	isTrue(t, ok, "email set")
	eqStr(t, "a@b.co", v, "email value")
	v, ok = Text("alice", "url")
	isTrue(t, ok, "url set")
	eqStr(t, "https://x.example", v, "url value")

	n := getRaw("alice")
	eqInt(t, 3600, int64(n.TTL), "ttl set")
}

func TestReservedNamespaceRejectedPure(t *testing.T) {
	reset()
	// the reserved-namespace guard is a pure lookup used by SetRecord.
	isTrue(t, reservedNamespaces["gno"], "gno reserved")
	isTrue(t, reservedNamespaces["system"], "system reserved")
	isFalse(t, reservedNamespaces["com.example"], "app namespace allowed")
}
