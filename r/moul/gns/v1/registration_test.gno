package gns

import (
	"chain"
	"testing"
)

func TestCommitRevealFlow(cur realm, t *testing.T) {
	reset()

	secret := "hunter2"
	dur := int64(1000)
	commit, err := MakeCommitment("alice", alice, dur, secret, "", config.PolicyRevision)
	noErr(t, err, "make commitment")

	testing.SetRealm(testing.NewUserRealm(alice))
	Commit(cross(cur), commit)

	// commitment visible, not yet ready
	cs := CommitmentStatus(commit)
	isTrue(t, cs.Exists, "commitment exists")
	eqStr(t, alice.String(), cs.Committer, "committer")

	testing.SkipHeights(3) // pass MinCommitAge

	testing.SetRealm(testing.NewUserRealm(alice))
	res := Register(cross(cur), RegisterRequest{
		Name:           "alice",
		Owner:          alice,
		Duration:       dur,
		Secret:         secret,
		PolicyRevision: config.PolicyRevision,
	})
	eqStr(t, "alice", res.Canonical, "result canonical")
	eqInt(t, 1, int64(res.Generation), "generation")

	// commitment consumed exactly once (invariant 7)
	isFalse(t, CommitmentStatus(commit).Exists, "commitment consumed")
	// second reveal with same commitment can't find it
	_, ok := getCommitment(commit)
	isFalse(t, ok, "commitment removed")
}

func TestPricingDeterministic(t *testing.T) {
	reset()
	config.BasePricePerSecond = 10

	// 5+ char label -> multiplier 1
	p, err := priceFor("alice", 100)
	noErr(t, err, "price alice")
	eqInt(t, 1000, p, "price 5-char")

	// 1 char -> multiplier 100
	p, err = priceFor("a", 100)
	noErr(t, err, "price a")
	eqInt(t, 100000, p, "price 1-char")

	// 3 char -> multiplier 5
	p, err = priceFor("abc", 100)
	noErr(t, err, "price abc")
	eqInt(t, 5000, p, "price 3-char")

	// invariant 10: overflow-safe
	_, err = priceFor("a", 1<<62)
	isErr(t, err, "overflow rejected")

	// zero/negative duration
	_, err = priceFor("alice", 0)
	errIs(t, err, errDurationTooShort, "zero duration")
}

func TestGenerationRecycle(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 1000)

	// put a record, then let it expire
	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "url", "https://old.example")

	testing.SkipHeights(500) // beyond grace

	// re-register by a different owner
	doRegister(cur, "alice", bob, 1000)

	view, ok := GetName("alice")
	isTrue(t, ok, "exists after recycle")
	eqInt(t, 2, int64(view.Generation), "generation incremented (invariant 20)")
	eqStr(t, bob.String(), view.Owner, "new owner")

	// invariant 19: old records do not leak
	_, ok = Text("alice", "url")
	isFalse(t, ok, "old record cleared on recycle")
}

func TestReservedNames(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(admin))
	ReserveName(cross(cur), "gno", true)

	// invariant 17: reserved names cannot be publicly registered
	isFalse(t, available("gno"), "reserved not available")
	eqStr(t, string(StatusReserved), string(Status("gno")), "status reserved")

	// unreserve
	testing.SetRealm(testing.NewUserRealm(admin))
	ReserveName(cross(cur), "gno", false)
	isTrue(t, available("gno"), "available after unreserve")
}

func TestRegisterWithPayment(cur realm, t *testing.T) {
	reset()
	config.BasePricePerSecond = 1
	config.Treasury = cur.Address() // realm keeps funds; no banker forward needed

	dur := int64(1000) // price = 1000 * 1 * 1 (5+ chars)
	secret := "s"
	commit, _ := MakeCommitment("alice", alice, dur, secret, "", config.PolicyRevision)

	testing.SetRealm(testing.NewUserRealm(alice))
	Commit(cross(cur), commit)
	testing.SkipHeights(3)

	testing.IssueCoins(cur.Address(), chain.Coins{{Denom: "ugnot", Amount: 1000}})
	testing.SetOriginSend(chain.Coins{{Denom: "ugnot", Amount: 1000}})
	testing.SetRealm(testing.NewUserRealm(alice))
	res := Register(cross(cur), RegisterRequest{
		Name:           "alice",
		Owner:          alice,
		Duration:       dur,
		Secret:         secret,
		PolicyRevision: config.PolicyRevision,
	})
	eqInt(t, 1000, res.Paid, "paid exact price")
	eqInt(t, 0, res.Refunded, "no refund")
}

func TestPriceQuote(t *testing.T) {
	reset()
	config.BasePricePerSecond = 2
	q, err := Price("bob", 500) // 3-char -> mult 5; 500*2*5 = 5000
	noErr(t, err, "quote")
	eqInt(t, 5000, q.Amount, "quote amount")
	eqStr(t, "ugnot", q.Denom, "quote denom")
	eqInt(t, int64(config.PolicyRevision), int64(q.Revision), "quote revision")
}
