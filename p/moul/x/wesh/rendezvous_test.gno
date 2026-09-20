package wesh

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Reference vectors produced by running weshnet's own algorithm
// (rendezvous.GenerateRendezvousPointForPeriod) against these inputs:
// topic = accountPK, seed = seed, interval = 24h.
const (
	testAccountPKHex = "2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
	testSeedHex      = "abababababababababababababababababababababababababababababababab"
)

func TestRoundPeriod(t *testing.T) {
	cases := []struct {
		name     string
		unixSec  int64
		interval int64
		want     int64
	}{
		{"epoch", 0, DefaultRotationInterval, 0},
		{"exactly on a boundary", 1789171200, DefaultRotationInterval, 1789171200},
		{"one second before the next", 1789257599, DefaultRotationInterval, 1789171200},
		{"one second after a boundary", 1789171201, DefaultRotationInterval, 1789171200},
		{"a negative interval is taken as positive", 1789257599, -DefaultRotationInterval, 1789171200},
		{"an hourly interval", 1789174800 + 59, 3600, 1789174800},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, RoundPeriod(tc.unixSec, tc.interval), tc.name)
	}
}

func TestNextPeriod(t *testing.T) {
	uassert.Equal(t, int64(1789257600), NextPeriod(1789171200, DefaultRotationInterval))
	uassert.Equal(t, int64(1789257600), NextPeriod(1789257599, DefaultRotationInterval))
}

// TestRendezvousPointMatchesWeshnet pins the derivation against vectors
// computed with weshnet's implementation. A divergence here means a gno-derived
// rendezvous point would not match the one the account actually announces on,
// which makes a published identity unverifiable.
func TestRendezvousPointMatchesWeshnet(t *testing.T) {
	pk := mustHex(t, testAccountPKHex)
	seed := mustHex(t, testSeedHex)

	cases := []struct {
		name        string
		periodStart int64
		want        string
	}{
		{
			"period 0",
			0,
			"04500fdede2a684f4e61cd67968b46ecdbf10d45604041bb7e0350572b8cc9cc",
		},
		{
			"period starting 1789171200",
			1789171200,
			"aad2926c39dacabaabbbde48522d043557c8945b6a2dc7b08499c112c72587da",
		},
	}
	for _, tc := range cases {
		got := hex.EncodeToString(RendezvousPoint(pk, seed, tc.periodStart))
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

// TestRendezvousPointAtIsStableWithinAPeriod is the property that makes
// rotation useful: every instant inside one interval maps to the same point,
// and the next interval maps somewhere unrelated.
func TestRendezvousPointAtIsStableWithinAPeriod(t *testing.T) {
	c := Contact{AccountPK: mustHex(t, testAccountPKHex), Seed: mustHex(t, testSeedHex)}

	start, err := c.RendezvousPointAt(1789171200, DefaultRotationInterval)
	uassert.NoError(t, err)
	end, err := c.RendezvousPointAt(1789257599, DefaultRotationInterval)
	uassert.NoError(t, err)
	next, err := c.RendezvousPointAt(1789257600, DefaultRotationInterval)
	uassert.NoError(t, err)

	uassert.Equal(t, hex.EncodeToString(start), hex.EncodeToString(end),
		"the point is stable for the whole period")
	uassert.False(t, hex.EncodeToString(start) == hex.EncodeToString(next),
		"the point rotates at the period boundary")
}

func TestRendezvousPointAtRejectsAnInvalidContact(t *testing.T) {
	_, err := Contact{AccountPK: repeat(1, 32), Seed: repeat(2, 31)}.RendezvousPointAt(0, DefaultRotationInterval)
	uassert.ErrorIs(t, err, ErrBadSeedLen)
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex fixture: %v", err)
	}
	return b
}
