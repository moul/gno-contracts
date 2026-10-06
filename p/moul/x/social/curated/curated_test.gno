package curated

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	deposit = int64(1000)
	window  = int64(100)
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
)

// list returns a registry holding one entry owned by alice, listed at height
// 100, which is the starting point of most cases below.
func list(t *testing.T) *Registry {
	t.Helper()
	r := New(deposit, window)
	urequire.NoError(t, r.Apply("gnoswap", "https://gnoswap.io", "an AMM", alice, deposit, 100))
	return r
}

func TestValidKey(t *testing.T) {
	tests := []struct {
		key  string
		want bool
	}{
		{"gnoswap", true},
		{"a", true},
		{"0", true},
		{"gno-swap_v2.1", true},
		{strings.Repeat("x", MaxKeyLen), true},
		{"", false},
		{strings.Repeat("x", MaxKeyLen+1), false},
		{"GnoSwap", false},
		{"gno swap", false},
		{"gno/swap", false},
		{"gno:swap", false},
		{".", false},
		{"..", false},
		{"-leading", false},
		{"_leading", false},
		{"émoji", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidKey(tt.key), tt.key)
	}
}

func TestValidURL(t *testing.T) {
	tests := []struct {
		name string
		url  string
		want bool
	}{
		{"https", "https://gnoswap.io/pools", true},
		{"an on-chain path, which has no scheme to carry", "/r/moul/home", true},
		{"query and fragment", "https://x.io/a?b=c#d", true},
		{"a pipe is escaped at render time, not refused", "https://x.io/a|b", true},
		{"empty", "", false},
		{"too long", "https://x.io/" + strings.Repeat("x", MaxURLLen), false},
		{"a space", "https://x.io/a b", false},
		{"a newline", "https://x.io/a\nb", false},
		{"a control character", "https://x.io/a\x01b", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidURL(tt.url), tt.name)
	}
}

func TestValidDescription(t *testing.T) {
	tests := []struct {
		name string
		desc string
		want bool
	}{
		{"plain", "an AMM on gno.land", true},
		{"markdown is allowed and escaped later", "[x](y) | z", true},
		{"empty", "", false},
		{"blank", "   ", false},
		{"too long", strings.Repeat("x", MaxDescLen+1), false},
		{"a newline would break its own table cell", "a\nb", false},
		{"a tab, same reason", "a\tb", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidDescription(tt.desc), tt.name)
	}
}

func TestApplyRefusesWhatItCannotStore(t *testing.T) {
	tests := []struct {
		name string
		key  string
		url  string
		desc string
		paid int64
		want error
	}{
		{"bad key", "Gnoswap", "https://x.io", "an AMM", deposit, ErrBadKey},
		{"bad url", "gnoswap", "", "an AMM", deposit, ErrBadURL},
		{"bad description", "gnoswap", "https://x.io", " ", deposit, ErrBadDescription},
		{"underpaid", "gnoswap", "https://x.io", "an AMM", deposit - 1, ErrWrongDeposit},
		{"overpaid", "gnoswap", "https://x.io", "an AMM", deposit + 1, ErrWrongDeposit},
		{"nothing attached", "gnoswap", "https://x.io", "an AMM", 0, ErrWrongDeposit},
	}
	for _, tt := range tests {
		r := New(deposit, window)
		err := r.Apply(tt.key, tt.url, tt.desc, alice, tt.paid, 100)
		uassert.ErrorIs(t, err, tt.want, tt.name)
		uassert.Equal(t, 0, r.Count(), tt.name+": nothing was listed")
		uassert.Equal(t, int64(0), r.Locked(), tt.name+": nothing was locked")
	}
}

func TestApplyListsImmediately(t *testing.T) {
	r := list(t)

	e, ok := r.Get("gnoswap")
	urequire.True(t, ok, "the entry exists")
	uassert.Equal(t, "https://gnoswap.io", e.URL)
	uassert.Equal(t, "an AMM", e.Description)
	uassert.Equal(t, alice.String(), e.Owner.String())
	uassert.Equal(t, deposit, e.Deposit)
	uassert.Equal(t, int64(100), e.At)
	uassert.Equal(t, "listed", e.State.String())

	uassert.True(t, r.IsListed("gnoswap"))
	uassert.False(t, r.IsListed("nothing"))
	uassert.Equal(t, 1, r.Count())
	uassert.Equal(t, 1, r.Records())
	uassert.Equal(t, deposit, r.Locked())
	uassert.Equal(t, int64(0), r.Owed())
}

// A key is unique while it is on the list, and free again once it is off it: a
// challenge removes an entry, it does not burn the name.
func TestAKeyIsTakenUntilItIsRemoved(t *testing.T) {
	r := list(t)

	uassert.ErrorIs(t, r.Apply("gnoswap", "https://other.io", "mine now", bob, deposit, 101), ErrTaken)
	urequire.NoError(t, r.Unlist("gnoswap", alice))
	uassert.False(t, r.IsListed("gnoswap"))

	urequire.NoError(t, r.Apply("gnoswap", "https://other.io", "mine now", bob, deposit, 102))
	e, _ := r.Get("gnoswap")
	uassert.Equal(t, bob.String(), e.Owner.String())
	uassert.Equal(t, int64(102), e.At, "a re-application is a fresh entry")
	uassert.Equal(t, 1, r.Count())
	uassert.Equal(t, 1, r.Records(), "and it reuses its place in the listing order")
}

func TestListedIsOldestFirstAndSkipsTheRemoved(t *testing.T) {
	r := New(deposit, window)
	urequire.NoError(t, r.Apply("one", "https://1.io", "first", alice, deposit, 100))
	urequire.NoError(t, r.Apply("two", "https://2.io", "second", alice, deposit, 101))
	urequire.NoError(t, r.Apply("three", "https://3.io", "third", alice, deposit, 102))

	got := r.Listed()
	urequire.Equal(t, 3, len(got))
	uassert.Equal(t, "one", got[0].Key)
	uassert.Equal(t, "two", got[1].Key)
	uassert.Equal(t, "three", got[2].Key)

	urequire.NoError(t, r.Unlist("two", alice))
	got = r.Listed()
	urequire.Equal(t, 2, len(got))
	uassert.Equal(t, "one", got[0].Key)
	uassert.Equal(t, "three", got[1].Key)
	uassert.Equal(t, 0, len(r.Challenged()))
}

func TestChallengeRefusals(t *testing.T) {
	tests := []struct {
		name string
		key  string
		who  address
		bond int64
		want error
	}{
		{"no such entry", "nothing", bob, deposit, ErrNoEntry},
		{"the bond must match", "gnoswap", bob, deposit - 1, ErrWrongBond},
		{"and may not exceed it either", "gnoswap", bob, deposit + 1, ErrWrongBond},
		{"an owner cannot shield their own entry", "gnoswap", alice, deposit, ErrSelfChallenge},
	}
	for _, tt := range tests {
		r := list(t)
		uassert.ErrorIs(t, r.Challenge(tt.key, tt.who, tt.bond, 200), tt.want, tt.name)
		uassert.Equal(t, deposit, r.Locked(), tt.name+": no bond was taken")
		_, open := r.ChallengeOf("gnoswap")
		uassert.False(t, open, tt.name+": no challenge was opened")
	}
}

func TestChallengeOpensOnceAndSetsTheDeadline(t *testing.T) {
	r := list(t)

	bond, ok := r.BondFor("gnoswap")
	urequire.True(t, ok, "it is challengeable")
	uassert.Equal(t, deposit, bond, "the bond matches that entry's own deposit")

	urequire.NoError(t, r.Challenge("gnoswap", bob, bond, 200))
	c, open := r.ChallengeOf("gnoswap")
	urequire.True(t, open, "the challenge is readable")
	uassert.Equal(t, bob.String(), c.Challenger.String())
	uassert.Equal(t, int64(200+window), c.Deadline)
	uassert.True(t, c.Open(200+window-1))
	uassert.False(t, c.Open(200+window), "the deadline is exclusive")
	uassert.Equal(t, "challenged", mustGet(t, r, "gnoswap").State.String())
	uassert.True(t, r.IsListed("gnoswap"), "a challenge is an objection, not a verdict")
	uassert.Equal(t, 2*deposit, r.Locked(), "the deposit and the bond")

	// A second challenge would be a second bond on one entry.
	uassert.ErrorIs(t, r.Challenge("gnoswap", carol, deposit, 201), ErrChallenged)
	_, ok = r.BondFor("gnoswap")
	uassert.False(t, ok, "and BondFor says so before any money is read")
}

func TestVoteIsOneAddressOneVoteWhileTheChallengeIsOpen(t *testing.T) {
	r := list(t)
	uassert.ErrorIs(t, r.Vote("gnoswap", carol, true, 200), ErrNoChallenge)
	uassert.ErrorIs(t, r.Vote("nothing", carol, true, 200), ErrNoEntry)

	urequire.NoError(t, r.Challenge("gnoswap", bob, deposit, 200))
	urequire.NoError(t, r.Vote("gnoswap", carol, true, 210))
	uassert.ErrorIs(t, r.Vote("gnoswap", carol, false, 211), ErrAlreadyVoted)
	uassert.ErrorIs(t, r.Vote("gnoswap", carol, true, 212), ErrAlreadyVoted)
	urequire.NoError(t, r.Vote("gnoswap", dave, false, 213))

	c, _ := r.ChallengeOf("gnoswap")
	uassert.Equal(t, int64(1), c.Keep)
	uassert.Equal(t, int64(1), c.Remove)
	uassert.Equal(t, 2, c.Voters())
	uassert.True(t, c.HasVoted(carol))
	uassert.False(t, c.HasVoted(alice))

	// Past the deadline the poll is shut, and so is the deadline itself.
	uassert.ErrorIs(t, r.Vote("gnoswap", alice, true, 200+window), ErrVotingClosed)
	uassert.Equal(t, 2, c.Voters())
}

// The outcome table: who wins, and what the loser pays. A tie keeps the entry.
func TestResolvePaysTheWinnerAndTiesKeep(t *testing.T) {
	tests := []struct {
		name       string
		keep       []address
		remove     []address
		wantKept   bool
		wantWinner address
		wantAmount int64
	}{
		{"nobody voted, the incumbent keeps it", nil, nil, true, alice, deposit},
		{"a tie keeps it", []address{carol}, []address{dave}, true, alice, deposit},
		{"a majority to keep", []address{carol, dave}, nil, true, alice, deposit},
		{"a majority to remove", nil, []address{carol, dave}, false, bob, 2 * deposit},
	}
	for _, tt := range tests {
		r := list(t)
		urequire.NoError(t, r.Challenge("gnoswap", bob, deposit, 200))
		for _, who := range tt.keep {
			urequire.NoError(t, r.Vote("gnoswap", who, true, 210))
		}
		for _, who := range tt.remove {
			urequire.NoError(t, r.Vote("gnoswap", who, false, 210))
		}

		out, err := r.Resolve("gnoswap", 200+window)
		urequire.NoError(t, err, tt.name)
		uassert.Equal(t, tt.wantKept, out.Kept, tt.name)
		uassert.Equal(t, tt.wantWinner.String(), out.Winner.String(), tt.name)
		uassert.Equal(t, tt.wantAmount, out.Amount, tt.name)
		uassert.Equal(t, tt.wantAmount, r.CreditOf(tt.wantWinner), tt.name+": credited, not sent")
		uassert.Equal(t, tt.wantKept, r.IsListed("gnoswap"), tt.name)

		// Whatever happened, every ugnot is either still backing the entry or
		// assigned to somebody.
		uassert.Equal(t, 2*deposit, r.Locked()+r.Owed(), tt.name+": the books balance")

		// The challenge is gone either way, so nothing resolves twice.
		_, open := r.ChallengeOf("gnoswap")
		uassert.False(t, open, tt.name)
		_, err = r.Resolve("gnoswap", 200+window)
		uassert.ErrorIs(t, err, ErrNoChallenge, tt.name)
	}
}

func TestResolveRefusesBeforeTheDeadline(t *testing.T) {
	r := list(t)
	_, err := r.Resolve("gnoswap", 200)
	uassert.ErrorIs(t, err, ErrNoChallenge, "an unchallenged entry has nothing to resolve")
	_, err = r.Resolve("nothing", 200)
	uassert.ErrorIs(t, err, ErrNoEntry)

	urequire.NoError(t, r.Challenge("gnoswap", bob, deposit, 200))
	_, err = r.Resolve("gnoswap", 200+window-1)
	uassert.ErrorIs(t, err, ErrTooEarly)
	uassert.Equal(t, int64(0), r.Owed(), "nothing was paid out early")
	uassert.Equal(t, "challenged", mustGet(t, r, "gnoswap").State.String())
}

// Losing a challenge frees the key, and the deposit that backed it has already
// gone to the challenger, so re-listing it costs a fresh deposit.
func TestAnEntryThatLosesIsRemovedAndItsDepositIsGone(t *testing.T) {
	r := list(t)
	urequire.NoError(t, r.Challenge("gnoswap", bob, deposit, 200))
	urequire.NoError(t, r.Vote("gnoswap", carol, false, 210))
	_, err := r.Resolve("gnoswap", 200+window)
	urequire.NoError(t, err)

	uassert.Equal(t, "removed", mustGet(t, r, "gnoswap").State.String())
	uassert.Equal(t, 0, r.Count())
	uassert.Equal(t, int64(0), r.Locked())
	uassert.Equal(t, 2*deposit, r.Owed())
	uassert.Equal(t, int64(0), r.CreditOf(alice), "the owner lost the deposit")
	uassert.ErrorIs(t, r.Unlist("gnoswap", alice), ErrNoEntry, "there is nothing left to take down")
}

func TestUnlistIsTheOwnersAndNotWhileChallenged(t *testing.T) {
	r := list(t)
	uassert.ErrorIs(t, r.Unlist("nothing", alice), ErrNoEntry)
	uassert.ErrorIs(t, r.Unlist("gnoswap", bob), ErrNotOwner)

	urequire.NoError(t, r.Challenge("gnoswap", bob, deposit, 200))
	uassert.ErrorIs(t, r.Unlist("gnoswap", alice), ErrChallenged,
		"an owner who could walk away mid-challenge would be risking nothing")
	uassert.Equal(t, int64(0), r.CreditOf(alice))

	// Once the challenge is behind it, the entry is the owner's to take down.
	urequire.NoError(t, r.Vote("gnoswap", carol, true, 210))
	_, err := r.Resolve("gnoswap", 200+window)
	urequire.NoError(t, err)
	urequire.NoError(t, r.Unlist("gnoswap", alice))
	uassert.Equal(t, 2*deposit, r.CreditOf(alice), "the bond she won, plus her own deposit back")
	uassert.Equal(t, int64(0), r.Locked())
}

func TestWithdrawZeroesTheCreditBeforeItIsPaid(t *testing.T) {
	r := list(t)
	urequire.NoError(t, r.Unlist("gnoswap", alice))
	uassert.Equal(t, deposit, r.Owed())

	_, err := r.Withdraw(bob)
	uassert.ErrorIs(t, err, ErrNothingOwed, "bob is owed nothing")

	got, err := r.Withdraw(alice)
	urequire.NoError(t, err)
	uassert.Equal(t, deposit, got)
	uassert.Equal(t, int64(0), r.CreditOf(alice))
	uassert.Equal(t, int64(0), r.Owed())

	// A second call, which is what a reentrant one would be, finds nothing.
	_, err = r.Withdraw(alice)
	uassert.ErrorIs(t, err, ErrNothingOwed)
}

func TestCreditsAccumulateAcrossEntries(t *testing.T) {
	r := list(t)
	urequire.NoError(t, r.Apply("gnoscan", "https://gnoscan.io", "an explorer", alice, deposit, 101))
	urequire.NoError(t, r.Unlist("gnoswap", alice))
	urequire.NoError(t, r.Unlist("gnoscan", alice))

	uassert.Equal(t, 2*deposit, r.CreditOf(alice), "crediting twice owes the sum")
	got, err := r.Withdraw(alice)
	urequire.NoError(t, err)
	uassert.Equal(t, 2*deposit, got, "and one withdrawal collects both")
}

// Everything the registry ever took in is either locked behind something live
// or owed to somebody, at every step of a full round.
func TestTheBooksBalanceAtEveryStep(t *testing.T) {
	r := New(deposit, window)
	paidIn := int64(0)

	check := func(step string) {
		t.Helper()
		uassert.Equal(t, paidIn, r.Locked()+r.Owed(), step)
	}
	check("empty")

	urequire.NoError(t, r.Apply("one", "https://1.io", "first", alice, deposit, 100))
	paidIn += deposit
	check("after a listing")

	urequire.NoError(t, r.Challenge("one", bob, deposit, 200))
	paidIn += deposit
	check("after a challenge")

	urequire.NoError(t, r.Vote("one", carol, false, 210))
	check("after a vote")

	_, err := r.Resolve("one", 200+window)
	urequire.NoError(t, err)
	check("after a resolution")

	_, err = r.Withdraw(bob)
	urequire.NoError(t, err)
	paidIn -= 2 * deposit
	check("after the winner collected")
	uassert.Equal(t, int64(0), r.Locked()+r.Owed(), "and the realm owes nothing")
}

func mustGet(t *testing.T, r *Registry, key string) *Entry {
	t.Helper()
	e, ok := r.Get(key)
	urequire.True(t, ok, "entry "+key+" exists")
	return e
}
