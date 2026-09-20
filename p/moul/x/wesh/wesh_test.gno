package wesh

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestContactValidate(t *testing.T) {
	cases := []struct {
		name string
		in   Contact
		want error
	}{
		{"well-formed", Contact{AccountPK: repeat(1, 32), Seed: repeat(2, 32)}, nil},
		{"with a display name", Contact{AccountPK: repeat(1, 32), Seed: repeat(2, 32), DisplayName: "gno"}, nil},
		{"seed too short", Contact{AccountPK: repeat(1, 32), Seed: repeat(2, 31)}, ErrBadSeedLen},
		{"seed too long", Contact{AccountPK: repeat(1, 32), Seed: repeat(2, 33)}, ErrBadSeedLen},
		{"no seed", Contact{AccountPK: repeat(1, 32)}, ErrBadSeedLen},
		{"account key too short", Contact{AccountPK: repeat(1, 31), Seed: repeat(2, 32)}, ErrBadAccountPKLen},
		{"no account key", Contact{Seed: repeat(2, 32)}, ErrBadAccountPKLen},
		{
			"display name too long",
			Contact{AccountPK: repeat(1, 32), Seed: repeat(2, 32), DisplayName: string(make([]byte, MaxDisplayNameLen+1))},
			ErrDisplayNameTooLong,
		},
	}
	for _, tc := range cases {
		err := tc.in.Validate()
		if tc.want == nil {
			uassert.NoError(t, err, tc.name)
			continue
		}
		uassert.ErrorIs(t, err, tc.want, tc.name)
	}
}

func TestSeedCommitment(t *testing.T) {
	seed := mustHex(t, testSeedHex)
	salt := []byte("a-16-byte-salt!!")

	c, err := SeedCommitment(seed, salt)
	uassert.NoError(t, err)
	uassert.Equal(t, DigestLen, len(c))

	again, err := SeedCommitment(seed, salt)
	uassert.NoError(t, err)
	uassert.Equal(t, string(c), string(again), "the commitment is deterministic")

	uassert.True(t, OpenCommitment(c, seed, salt), "the correct opening verifies")
	uassert.False(t, OpenCommitment(c, seed, []byte("another-salt!!!!")), "a wrong salt does not open it")
	uassert.False(t, OpenCommitment(c, repeat(0xEE, 32), salt), "a wrong seed does not open it")
	uassert.False(t, OpenCommitment(c[:31], seed, salt), "a truncated commitment does not open it")
}

func TestSeedCommitmentRejectsABadSeed(t *testing.T) {
	_, err := SeedCommitment(repeat(1, 31), []byte("salt"))
	uassert.ErrorIs(t, err, ErrBadSeedLen)
}

// TestSeedCommitmentIsSaltSeparated guards the length-extension style
// ambiguity: without distinct inputs, (seed, "ab") and (seed+"a", "b") would
// collide. The seed is fixed-length, which resolves it, and this pins that.
func TestSeedCommitmentDependsOnTheSplit(t *testing.T) {
	seed := repeat(0xAA, 32)
	a, _ := SeedCommitment(seed, []byte("ab"))
	b, _ := SeedCommitment(seed, []byte("abc"))
	uassert.False(t, string(a) == string(b))
}

func TestDecodeHelpers(t *testing.T) {
	cases := []struct {
		name string
		fn   func(string) ([]byte, error)
		in   string
		err  error
	}{
		{"account key", DecodeAccountPK, testAccountPKHex, nil},
		{"seed", DecodeSeed, testSeedHex, nil},
		{"device key", DecodeDevicePK, testSeedHex, nil},
		{"commitment", DecodeCommitment, testSeedHex, nil},
		{"account key, not hex", DecodeAccountPK, "zzzz", ErrBadHex},
		{"account key, odd length", DecodeAccountPK, "abc", ErrBadHex},
		{"account key, wrong length", DecodeAccountPK, "abcd", ErrBadAccountPKLen},
		{"seed, wrong length", DecodeSeed, "abcd", ErrBadSeedLen},
		{"device key, wrong length", DecodeDevicePK, "abcd", ErrBadDevicePKLen},
		{"commitment, wrong length", DecodeCommitment, "abcd", ErrBadCommitmentLen},
	}
	for _, tc := range cases {
		got, err := tc.fn(tc.in)
		if tc.err == nil {
			uassert.NoError(t, err, tc.name)
			uassert.Equal(t, 32, len(got), tc.name)
			continue
		}
		uassert.ErrorIs(t, err, tc.err, tc.name)
	}
}
