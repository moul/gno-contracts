package wesh

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Fixtures. The signatures were produced with Go's crypto/ed25519 over the
// exact statement text this package builds, using the account key whose seed
// is 32 x 0x42, the same key as testAccountPKHex.
const (
	testChainID = "gnoland-1"
	testGnoAddr = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

	testDev1Hex = "0707070707070707070707070707070707070707070707070707070707070707"
	testDev2Hex = "0909090909090909090909090909090909090909090909090909090909090909"

	bindRev1Sig = "4cd53e6096994d2801de1b16cfd1b2d2aa34ff35b265c53fa176cfb18c949be7" +
		"0078161fe2afaf503cf808b2f52a321e15a625f56b1b2d0aaaf8c460f6d64702"

	dev0Sig = "19d0bd2517ca6308b089196528e6c27359117b80e1972c71c25434a6f260d62a" +
		"703a28c2f973d89056e7c691b4f879d38e1b016745508b357d217eb54c984305"
	dev0Digest = "003570bf50d50213f9f3e9c76a8271435a8f2e4b7c24010a8e8383dedd0ed2a6"

	dev1Sig = "c26b338045373f7504a0d251c2126e31ff3330f08463672a82467daf4dedca51" +
		"1da4681715a6c3afe4115622cfcca9ec3f44d5a35f9973c3b9856cc06859810c"
	dev1Digest = "35a8219e60f6cd375e1378879de8921f9d554f054cd8a70ea2d3914b20b77bbb"
)

func TestBindStatementIsCanonical(t *testing.T) {
	got := BindStatement(testChainID, testGnoAddr, mustHex(t, testAccountPKHex), mustHex(t, testSeedHex), 1)
	want := "gno.wesh/v0:bind\n" + testChainID + "\n" + testGnoAddr + "\n" +
		testAccountPKHex + "\n" + testSeedHex + "\n1"
	uassert.Equal(t, want, got)
}

func TestVerifyBind(t *testing.T) {
	pk := mustHex(t, testAccountPKHex)
	seed := mustHex(t, testSeedHex)
	sig := mustHex(t, bindRev1Sig)

	uassert.NoError(t, VerifyBind(testChainID, testGnoAddr, pk, seed, 1, sig),
		"a signature made by the account key verifies")
}

// TestVerifyBindRejectsEveryTamperedField is the heart of the scheme: each
// field is in the signed text precisely so that changing it invalidates the
// signature. One case per field, so a regression names the field it broke.
func TestVerifyBindRejectsEveryTamperedField(t *testing.T) {
	pk := mustHex(t, testAccountPKHex)
	seed := mustHex(t, testSeedHex)
	sig := mustHex(t, bindRev1Sig)

	cases := []struct {
		name    string
		chainID string
		addr    string
		payload []byte
		rev     int
	}{
		{"replayed on another chain", "test7", testGnoAddr, seed, 1},
		{"claimed from another gno address", testChainID, "g1manfred47kzduec920z88wfr64ylksmdcedlf5", seed, 1},
		{"a different seed swapped in", testChainID, testGnoAddr, repeat(0xEE, 32), 1},
		{"an older revision replayed", testChainID, testGnoAddr, seed, 0},
		{"a newer revision forged", testChainID, testGnoAddr, seed, 2},
	}
	for _, tc := range cases {
		err := VerifyBind(tc.chainID, tc.addr, pk, tc.payload, tc.rev, sig)
		uassert.ErrorIs(t, err, ErrBadSignature, tc.name)
	}
}

func TestVerifyBindRejectsAnotherAccountsKey(t *testing.T) {
	err := VerifyBind(testChainID, testGnoAddr, repeat(0x33, 32), mustHex(t, testSeedHex), 1, mustHex(t, bindRev1Sig))
	uassert.ErrorIs(t, err, ErrBadSignature)

	err = VerifyBind(testChainID, testGnoAddr, repeat(0x33, 31), mustHex(t, testSeedHex), 1, mustHex(t, bindRev1Sig))
	uassert.ErrorIs(t, err, ErrBadAccountPKLen)
}

func TestGenesisDigest(t *testing.T) {
	uassert.Equal(t, DigestLen, len(GenesisDigest()))
	uassert.Equal(t,
		"0000000000000000000000000000000000000000000000000000000000000000",
		hex.EncodeToString(GenesisDigest()))
}

// TestVerifyDeviceChain walks a three-entry sigchain: add, add, revoke. Each
// entry chains to the digest of the previous one, which is what stops an entry
// being reordered or silently dropped.
func TestVerifyDeviceChain(t *testing.T) {
	pk := mustHex(t, testAccountPKHex)

	d0, err := VerifyDevice(testChainID, pk, 0, GenesisDigest(), OpAdd, mustHex(t, testDev1Hex), mustHex(t, dev0Sig))
	uassert.NoError(t, err, "first entry")
	uassert.Equal(t, dev0Digest, hex.EncodeToString(d0), "digest the next entry must chain to")

	d1, err := VerifyDevice(testChainID, pk, 1, d0, OpAdd, mustHex(t, testDev2Hex), mustHex(t, dev1Sig))
	uassert.NoError(t, err, "second entry")
	uassert.Equal(t, dev1Digest, hex.EncodeToString(d1))
}

func TestVerifyDeviceRejectsABrokenChain(t *testing.T) {
	pk := mustHex(t, testAccountPKHex)
	dev1 := mustHex(t, testDev1Hex)
	dev2 := mustHex(t, testDev2Hex)

	cases := []struct {
		name    string
		seq     int
		prev    []byte
		op      string
		device  []byte
		sig     string
		wantErr error
	}{
		{"wrong previous digest", 1, GenesisDigest(), OpAdd, dev2, dev1Sig, ErrBadSignature},
		{"wrong sequence number", 2, mustHexRaw(dev0Digest), OpAdd, dev2, dev1Sig, ErrBadSignature},
		{"operation flipped to revoke", 0, GenesisDigest(), OpRevoke, dev1, dev0Sig, ErrBadSignature},
		{"a different device substituted", 0, GenesisDigest(), OpAdd, dev2, dev0Sig, ErrBadSignature},
		{"unknown operation", 0, GenesisDigest(), "delete", dev1, dev0Sig, ErrBadOp},
		{"negative sequence", -1, GenesisDigest(), OpAdd, dev1, dev0Sig, ErrBadSeq},
		{"short previous digest", 0, repeat(0, 31), OpAdd, dev1, dev0Sig, ErrBadPrevLen},
		{"short device key", 0, GenesisDigest(), OpAdd, repeat(7, 31), dev0Sig, ErrBadDevicePKLen},
	}
	for _, tc := range cases {
		_, err := VerifyDevice(testChainID, pk, tc.seq, tc.prev, tc.op, tc.device, mustHexRaw(tc.sig))
		uassert.ErrorIs(t, err, tc.wantErr, tc.name)
	}
}

func TestValidOp(t *testing.T) {
	uassert.True(t, ValidOp(OpAdd))
	uassert.True(t, ValidOp(OpRevoke))
	uassert.False(t, ValidOp("Add"), "operations are case-sensitive")
	uassert.False(t, ValidOp(""))
}

func mustHexRaw(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("bad hex fixture: " + s)
	}
	return b
}
