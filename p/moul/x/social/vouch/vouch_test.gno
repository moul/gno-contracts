package vouch

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
)

const realmPath = "gno.land/r/moul/x/social/vouch/v0"

func TestValidReason(t *testing.T) {
	tests := []struct {
		name   string
		reason string
		want   bool
	}{
		{"plain", "worked with them for a year", true},
		{"markdown is allowed and escaped later", "[x](y) | z", true},
		{"at the limit", strings.Repeat("x", MaxReasonLen), true},
		{"empty", "", false},
		{"blank", "   ", false},
		{"too long", strings.Repeat("x", MaxReasonLen+1), false},
		{"a reason is one line", "met them\nat a conference", false},
		{"no tabs either", "met them\there", false},
		{"control character", "a\x01b", false},
		{"delete character", "a\x7fb", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidReason(tt.reason), tt.name)
	}
}

func TestRecordRefusesWhatItCannotStore(t *testing.T) {
	g := NewGraph()

	_, err := g.Record(alice, alice, "myself", 0, 100)
	uassert.ErrorIs(t, err, ErrSelfVouch)

	_, err = g.Record(alice, bob, "", 0, 100)
	uassert.ErrorIs(t, err, ErrBadReason)

	_, err = g.Record(alice, bob, "fine", -1, 100)
	uassert.ErrorIs(t, err, ErrBadBond)

	uassert.Equal(t, 0, g.Count())
	uassert.Equal(t, 0, g.People())
	uassert.Equal(t, 0, g.ScoreOf(alice))
}

// A score counts people. This is the property every caller of IsTrusted is
// relying on, so it is the one worth pinning hardest.
func TestScoreCountsPeopleAndNotVouches(t *testing.T) {
	g := NewGraph()

	updated, err := g.Record(bob, alice, "known them for years", 0, 100)
	urequire.NoError(t, err)
	uassert.False(t, updated, "the first vouch is not an update")
	uassert.Equal(t, 1, g.ScoreOf(alice))

	// Saying it again is an edit, not a second voice.
	updated, err = g.Record(bob, alice, "still true", 0, 101)
	urequire.NoError(t, err)
	uassert.True(t, updated, "the second vouch replaced the first")
	uassert.Equal(t, 1, g.ScoreOf(alice), "one person is one point, however often they say it")
	uassert.Equal(t, "still true", g.ReasonFrom(bob, alice), "the reason was updated")
	uassert.Equal(t, 1, g.Count())

	// A different person does move it.
	_, err = g.Record(carol, alice, "we shipped together", 0, 102)
	urequire.NoError(t, err)
	uassert.Equal(t, 2, g.ScoreOf(alice))
	uassert.Equal(t, 2, g.Count())
	uassert.Equal(t, 1, g.People(), "one address has been vouched for")

	// And revoking lowers it.
	_, err = g.Revoke(carol, alice)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, g.ScoreOf(alice))
	uassert.Equal(t, 1, g.Count())
}

func TestIsTrusted(t *testing.T) {
	g := NewGraph()
	g.Record(bob, alice, "one", 0, 100)
	g.Record(carol, alice, "two", 0, 100)

	tests := []struct {
		name string
		addr address
		min  int
		want bool
	}{
		{"below the score", alice, 1, true},
		{"at the score", alice, 2, true},
		{"above the score", alice, 3, false},
		{"zero is read as one", alice, 0, true},
		{"zero does not open the gate for nobody", dave, 0, false},
		{"a negative min is read as one too", dave, -5, false},
		{"nobody vouches for dave", dave, 1, false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, g.IsTrusted(tt.addr, tt.min), tt.name)
	}
}

func TestTheBondFollowsTheVouchInBothDirections(t *testing.T) {
	g := NewGraph()

	_, err := g.Record(bob, alice, "staking 1 GNOT on this", 1_000_000, 100)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1_000_000), g.BondedFor(alice))
	uassert.Equal(t, int64(1_000_000), g.TotalBonded())
	uassert.Equal(t, int64(0), g.Owed(bob), "nothing is owed while the vouch stands")

	// A repeated vouch adds to the bond rather than replacing it.
	_, err = g.Record(bob, alice, "doubling down", 500_000, 101)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1_500_000), g.BondedFor(alice))
	uassert.Equal(t, int64(1_500_000), g.BondFrom(bob, alice))

	// A second voucher's bond piles on top.
	g.Record(carol, alice, "and me", 250_000, 102)
	uassert.Equal(t, int64(1_750_000), g.BondedFor(alice))

	// Revoking returns exactly what that voucher put in, and nothing else.
	refund, err := g.Revoke(bob, alice)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1_500_000), refund)
	uassert.Equal(t, int64(250_000), g.BondedFor(alice), "carol's bond stays")
	uassert.Equal(t, int64(250_000), g.TotalBonded())
	uassert.Equal(t, int64(1_500_000), g.Owed(bob))
	uassert.Equal(t, int64(1_500_000), g.TotalOwed())

	// Withdrawing zeroes the credit before the realm sends anything.
	got, err := g.Withdraw(bob)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1_500_000), got)
	uassert.Equal(t, int64(0), g.Owed(bob))
	uassert.Equal(t, int64(0), g.TotalOwed())

	// A reentrant withdrawal finds nothing.
	_, err = g.Withdraw(bob)
	uassert.ErrorIs(t, err, ErrNothingOwed)
}

func TestRevokeRefusesWhatWasNeverThere(t *testing.T) {
	g := NewGraph()
	_, err := g.Revoke(alice, bob)
	uassert.ErrorIs(t, err, ErrNoVouch)

	g.Record(alice, bob, "fine", 0, 100)
	_, err = g.Revoke(bob, alice)
	uassert.ErrorIs(t, err, ErrNoVouch, "a vouch is directed, so the other way round is not one")
}

func TestTheTwoDirections(t *testing.T) {
	g := NewGraph()
	g.Record(alice, bob, "a to b", 0, 100)
	g.Record(alice, carol, "a to c", 0, 100)
	g.Record(bob, carol, "b to c", 0, 100)

	uassert.Equal(t, 0, len(g.VouchedBy(alice)), "nobody vouches for alice")
	uassert.Equal(t, 2, len(g.VouchesOf(alice)))
	uassert.Equal(t, 2, len(g.VouchedBy(carol)))
	uassert.Equal(t, 0, len(g.VouchesOf(carol)))

	// Sorted by address, so two identical calls render identically.
	in := g.VouchedBy(carol)
	uassert.True(t, in[0].String() < in[1].String(), "inbound is sorted")

	uassert.Equal(t, "a to c", g.ReasonFrom(alice, carol))
	uassert.Equal(t, "", g.ReasonFrom(carol, alice), "no vouch, no reason")
}

func TestMutual(t *testing.T) {
	g := NewGraph()
	g.Record(alice, bob, "a to b", 0, 100)

	uassert.False(t, g.Mutual(alice, bob), "one direction is not mutual")
	uassert.False(t, g.Mutual(alice, alice), "an address is never mutual with itself")

	g.Record(bob, alice, "b to a", 0, 101)
	uassert.True(t, g.Mutual(alice, bob))
	uassert.True(t, g.Mutual(bob, alice), "mutual is symmetric")
	uassert.False(t, g.Mutual(alice, carol))

	// The cheapest sybil shape: two addresses, two transactions, both pass a
	// gate set at one. That is the whole reason Mutual is exported.
	uassert.True(t, g.IsTrusted(alice, 1))
	uassert.True(t, g.IsTrusted(bob, 1))
	uassert.False(t, g.IsTrusted(alice, 2))
}

func TestLeaderboardIsATotalOrder(t *testing.T) {
	g := NewGraph()
	g.Record(alice, carol, "one", 0, 100)
	g.Record(bob, carol, "two", 0, 100)
	g.Record(alice, bob, "three", 100, 100)

	rows := g.Leaderboard(10)
	urequire.Equal(t, 2, len(rows))
	uassert.Equal(t, carol.String(), rows[0].Addr.String(), "highest score first")
	uassert.Equal(t, 2, rows[0].Score)
	uassert.Equal(t, int64(100), rows[1].Bonded)

	uassert.Equal(t, 1, len(g.Leaderboard(1)), "limit truncates")
	uassert.Equal(t, 0, len(g.Leaderboard(0)))
	uassert.Equal(t, 0, len(NewGraph().Leaderboard(10)), "an empty graph ranks nobody")

	// Revoking the last vouch for an address drops it off the board.
	g.Revoke(alice, bob)
	uassert.Equal(t, 1, len(g.Leaderboard(10)))
	uassert.Equal(t, 0, g.ScoreOf(bob))
}

func TestBadge(t *testing.T) {
	g := NewGraph()
	uassert.True(t, strings.Contains(Badge(realmPath, alice, g.ScoreOf(alice), 0), "not vouched for"))

	g.Record(bob, alice, "one", 2_000_000, 100)
	got := Badge(realmPath, alice, g.ScoreOf(alice), g.BondedFor(alice))
	uassert.True(t, strings.Contains(got, "1 voucher]"), "singular: "+got)
	uassert.True(t, strings.Contains(got, "2 GNOT bonded"), got)
	uassert.True(t, strings.Contains(got, AddrURL(realmPath, alice)), got)

	g.Record(carol, alice, "two", 0, 101)
	uassert.True(t, strings.Contains(Badge(realmPath, alice, g.ScoreOf(alice), 0), "2 vouchers]"))
}

func TestURLsStripTheChainDomain(t *testing.T) {
	uassert.Equal(t, "/r/moul/x/social/vouch/v0", RealmURL(realmPath))
	uassert.Equal(t, "/r/a/b:addr/"+alice.String(), AddrURL("gno.land/r/a/b", alice))
}
