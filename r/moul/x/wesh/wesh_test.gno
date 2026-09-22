package wesh

import (
	"testing"

	"gno.land/p/moul/x/wesh/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// Signature fixtures. Each was produced with Go's crypto/ed25519 over the exact
// statement wesh.BindStatement / wesh.DeviceStatement builds, for chain-id
// "dev" (what the test VM reports) and the address named in the constant.
// Regenerating them means re-signing: that is the point, since the whole
// scheme rests on the chain being unable to accept anything unsigned.
const (
	// alice, g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh
	aliceAccountPKHex = "2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
	aliceSeed1Hex     = "abababababababababababababababababababababababababababababababab"
	aliceSeed2Hex     = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	aliceCommitHex    = "c9744f547763321102debcf355a5652208604d53dba6c77e978ee8077ceb472a"

	aliceBind1Sig = "1279475fc9f7423d13e3eeea96a1714754f74c77abbb5859ba899bd3f820f59d" +
		"2b0a16f2f6c436cdafd8e20b0d709a5e247a5bbbf4b34df38c1405aba3645905"
	aliceBind2Sig = "e915b181109936b1ef77ea8e31e512b56ac63a7e690c382e3613df3ef50472ba" +
		"23233442d789c22ad9401cb882f57be737a67e24db207a9856186eda61fdc108"
	aliceBind3Sig = "d04f8733f564ee45f141fb71ecb049078a23215b29a14dafeed6c1ced91511ec" +
		"47b8c3de120f0d23c534c7387e3273e86b50787280ff38a7f1bd31c23ab35f03"
	aliceCommitBindSig = "d467d806145c228ff7b784658f06f8f05e7fa19354ae0bad3a69b40a1a4cf518" +
		"ecb3a679674705017c6dfa1bf0bac3e1ec67a4f417c18a80faf77062b8c1e100"
	// signed by alice's key but naming bob's gno address
	aliceBindForBobSig = "7bac691e9da577c6474af269b690a7415f07c4a8e4df486deccf824b41061735" +
		"01cd22af6f1b9654603a866a3a46942ec020714226b01105700eab84cfc08700"

	// bob, g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu
	bobAccountPKHex = "332ebe8d27cb7323b3a401c1c13b5dd64bccc0e10ecda1c2b5d11a03779a85e5"
	bobBind1Sig     = "69653e1bef41150eed026b355d5ee9837455e3432003ca19102075078305fdbe" +
		"b440eedb421056a0e62a182a406cb3394c1225de768dcd114f9d0b9b3501b90f"

	// alice's device sigchain: add dev1, add dev2, revoke dev1
	dev1Hex = "0707070707070707070707070707070707070707070707070707070707070707"
	dev2Hex = "0909090909090909090909090909090909090909090909090909090909090909"

	devAdd1Sig = "259abde508b8880dd1f53b236d93b08aa1c7511c4308c2b16da2520d5f553a50" +
		"67c24876299b6c3e4d9fb88e043dec1978f8d9328f7ac13d80bfdab536893507"
	devAdd1Digest = "bc51799b5d012dc7ce806b4c63474b1e2db515e7d1622ecd5900b23e1d6a9519"

	devAdd2Sig = "4799b276bf9b713d84855670198a86de8d38bc2644349a554fe0d4dab5fbea9b" +
		"7e90aecfe9b7da74345e61f5016361e92e7c0959fe09665a1f20f604015bea00"
	devAdd2Digest = "b0da03f83e5349e92bc524714862daa850750f756ca6fd47264333fbf2175c15"

	devRevoke1Sig = "47433475efd00ed87769e7bb748a5af9be77cde56817ea9a1ddd9288533e2bf9" +
		"b783d85a025a632466ce8dcf637047c932c9d1a15131187213e1ae354e22df02"
	devRevoke1Digest = "ef0c1d0614420c7d660f8416b18651206118e49e8f46ac0360bef61ae6b9100d"

	// signed for sequence 5 while the head is still at sequence 1
	devWrongSeqSig = "c65d9c48c441bf36dcf01c8c0e46fe73a9f7f8d8edffb07bd05f9ca4a8f875bc" +
		"6de7ebe30c1d5ae785fde8bfe7b48705605a6c247a62def9b03d37fb62f6f809"

	genesisDigestHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

// reset clears realm globals: gno subtests do not roll them back.
func reset() {
	byName = avl.Tree{}
	byOwner = avl.Tree{}
	byAccount = avl.Tree{}
}

// Two gno-specific rules shape every test below, and both cost a red run to
// learn:
//
//   - testing.SetRealm is scoped to the frame that calls it, so it has to be
//     called in the test body, not in a setUpAlice() helper.
//   - a helper whose first parameter is `realm` is itself a crossing function,
//     so routing a call through one makes THIS realm the Previous() the
//     callee sees, not the user. Crossing calls stay inline.
//
// Together they mean the two setup lines are repeated rather than factored.
func aliceAddr() address { return testutils.TestAddress("alice") }
func bobAddr() address   { return testutils.TestAddress("bob") }

func TestRegister(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)

	uassert.Equal(t, 1, Count())
	pk, payload, committed, ok := Resolve("alice")
	uassert.True(t, ok, "the name resolves")
	uassert.Equal(t, aliceAccountPKHex, pk)
	uassert.Equal(t, aliceSeed1Hex, payload)
	uassert.False(t, committed, "the seed is published, not committed")
	uassert.Equal(t, "alice", NameOf(aliceAddr()))
}

// TestRegisterEmitsARealBertyLink is the payoff: the realm hands back a link a
// Berty client can actually open.
func TestRegisterEmitsARealBertyLink(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)

	uassert.Equal(t,
		"https://berty.tech/id#contact/oZBLFpzghxrATkepWvDPNX9pHYqi6BWgP45xGWhqxcwmqN2bnMMbU7UcwUuTaCcDyUvMjmWRMDWcP96bXAndcjNiAZ1Vz9X/name=Alice",
		Link("alice"))

	// and the rendezvous point anyone can check against the DHT
	uassert.Equal(t,
		"aad2926c39dacabaabbbde48522d043557c8945b6a2dc7b08499c112c72587da",
		RendezvousPointAt("alice", 1789171200))
}

func TestRegisterIsCaseInsensitive(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "  ALICE  ", aliceAccountPKHex, aliceSeed1Hex, "", aliceBind1Sig)

	_, _, _, ok := Resolve("Alice")
	uassert.True(t, ok, "lookup is case-insensitive")
	uassert.Equal(t, "alice", NameOf(aliceAddr()), "the handle is stored lowercased")
}

// TestRegisterRejectsAnUnsignedClaim is the attack the binding signature
// exists to stop: bob publishing alice's account key next to a seed he
// controls, and harvesting the contact requests that follow.
func TestRegisterRejectsAnotherAccountsKey(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bobAddr()))
	uassert.AbortsContains(t, cur, "signature does not verify", func() {
		Register(cross(cur), "notalice", aliceAccountPKHex, aliceSeed1Hex, "", aliceBind1Sig)
	}, "alice's signature does not authorise bob's address")
}

// TestRegisterRejectsAReplayedBinding: the statement names the gno address, so
// a signature harvested from alice's transaction is useless to anyone else.
func TestRegisterRejectsAReplayedBinding(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	uassert.AbortsContains(t, cur, "signature does not verify", func() {
		// this signature names bob's address, alice is calling
		Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "", aliceBindForBobSig)
	})
}

func TestRegisterRejectsDuplicates(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)

	testing.SetRealm(testing.NewUserRealm(bobAddr()))
	uassert.AbortsContains(t, cur, "name is already taken", func() {
		Register(cross(cur), "alice", bobAccountPKHex, aliceSeed1Hex, "", bobBind1Sig)
	})
	uassert.AbortsContains(t, cur, "already published under another name", func() {
		Register(cross(cur), "alice2", aliceAccountPKHex, aliceSeed1Hex, "", aliceBind1Sig)
	}, "one Wesh account, one directory entry")

	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	uassert.AbortsContains(t, cur, "already owns an identity", func() {
		Register(cross(cur), "alice2", aliceAccountPKHex, aliceSeed1Hex, "", aliceBind1Sig)
	})
}

func TestRegisterValidatesInput(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))

	uassert.AbortsContains(t, cur, "between 3 and 32", func() {
		Register(cross(cur), "ab", aliceAccountPKHex, aliceSeed1Hex, "", aliceBind1Sig)
	})
	uassert.AbortsContains(t, cur, "a-z, 0-9", func() {
		Register(cross(cur), "al!ce", aliceAccountPKHex, aliceSeed1Hex, "", aliceBind1Sig)
	})
	uassert.AbortsContains(t, cur, "account key", func() {
		Register(cross(cur), "alice", "abcd", aliceSeed1Hex, "", aliceBind1Sig)
	})
	uassert.AbortsContains(t, cur, "seed", func() {
		Register(cross(cur), "alice", aliceAccountPKHex, "abcd", "", aliceBind1Sig)
	})
	uassert.AbortsContains(t, cur, "signature must be 64", func() {
		Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "", "00")
	})
}

func TestRegisterCommitted(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	RegisterCommitted(cross(cur), "alice", aliceAccountPKHex, aliceCommitHex, "", aliceCommitBindSig)

	_, payload, committed, ok := Resolve("alice")
	uassert.True(t, ok)
	uassert.True(t, committed)
	uassert.Equal(t, aliceCommitHex, payload)

	uassert.Equal(t, "", Link("alice"), "a committed identity publishes no link")
	uassert.Equal(t, "", RendezvousPointAt("alice", 1789171200),
		"a committed identity does not disclose its rendezvous point")
}

// TestCommitmentOpensWithTheOutOfBandSeed: the chain attests the binding, and
// the seed handed over privately checks against it.
func TestCommitmentOpensWithTheOutOfBandSeed(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	RegisterCommitted(cross(cur), "alice", aliceAccountPKHex, aliceCommitHex, "", aliceCommitBindSig)

	_, payload, _, _ := Resolve("alice")
	commitment, err := wesh.DecodeCommitment(payload)
	uassert.NoError(t, err)
	seed, err := wesh.DecodeSeed(aliceSeed1Hex)
	uassert.NoError(t, err)

	uassert.True(t, wesh.OpenCommitment(commitment, seed, []byte("a-16-byte-salt!!")),
		"the seed shared out of band matches what the chain attested")
	uassert.False(t, wesh.OpenCommitment(commitment, seed, []byte("wrong-salt!!!!!!")))
}

func TestRotate(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)

	Rotate(cross(cur), aliceSeed2Hex, aliceBind2Sig)

	_, payload, _, _ := Resolve("alice")
	uassert.Equal(t, aliceSeed2Hex, payload)

	id := lookup("alice")
	uassert.Equal(t, 2, id.revision)
	uassert.Equal(t, 2, len(id.history), "the superseded seed is kept so a stale link is recognisable")
	uassert.Equal(t, aliceSeed1Hex, hexOf(id.history[0].payload))
}

// TestRotateRejectsAReplayedRevision is what a monotonic revision buys: an old
// binding cannot be replayed to roll a rotation back.
func TestRotateRejectsAReplayedRevision(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)
	Rotate(cross(cur), aliceSeed2Hex, aliceBind2Sig)

	uassert.AbortsContains(t, cur, "signature does not verify", func() {
		Rotate(cross(cur), aliceSeed1Hex, aliceBind1Sig)
	}, "the revision-1 signature is dead once revision 2 exists")

	// the correctly-signed revision 3 does go back to the first seed
	Rotate(cross(cur), aliceSeed1Hex, aliceBind3Sig)
	uassert.Equal(t, 3, lookup("alice").revision)
}

func TestRotateRejectsANoOp(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)
	uassert.AbortsContains(t, cur, "identical to the current one", func() {
		Rotate(cross(cur), aliceSeed1Hex, aliceBind2Sig)
	})
}

func TestRotateRequiresAnIdentity(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bobAddr()))
	uassert.AbortsContains(t, cur, "no identity registered", func() {
		Rotate(cross(cur), aliceSeed2Hex, aliceBind2Sig)
	})
}

// TestDeviceSigchain walks the sequence weshnet itself cannot express:
// add a device, add a second, then revoke the first.
func TestDeviceSigchain(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)

	uassert.Equal(t, genesisDigestHex, SigchainHead("alice"), "an empty chain starts at the genesis digest")
	uassert.Equal(t, "unknown", DeviceStatus("alice", dev1Hex))

	AppendDevice(cross(cur), genesisDigestHex, wesh.OpAdd, dev1Hex, devAdd1Sig)
	uassert.Equal(t, devAdd1Digest, SigchainHead("alice"))
	uassert.Equal(t, "active", DeviceStatus("alice", dev1Hex))

	AppendDevice(cross(cur), devAdd1Digest, wesh.OpAdd, dev2Hex, devAdd2Sig)
	uassert.Equal(t, devAdd2Digest, SigchainHead("alice"))

	AppendDevice(cross(cur), devAdd2Digest, wesh.OpRevoke, dev1Hex, devRevoke1Sig)
	uassert.Equal(t, devRevoke1Digest, SigchainHead("alice"))
	uassert.Equal(t, "revoked", DeviceStatus("alice", dev1Hex), "revocation is public, ordered and attributable")
	uassert.Equal(t, "active", DeviceStatus("alice", dev2Hex))
	uassert.Equal(t, 1, activeDevices(lookup("alice")))
}

// TestDeviceSigchainRejectsAForkedChain: every entry chains to the digest of
// the one before it, so the log cannot be reordered or have an entry dropped.
func TestDeviceSigchainRejectsAForkedChain(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)
	AppendDevice(cross(cur), genesisDigestHex, wesh.OpAdd, dev1Hex, devAdd1Sig)

	uassert.AbortsContains(t, cur, "does not match the sigchain head", func() {
		AppendDevice(cross(cur), genesisDigestHex, wesh.OpAdd, dev2Hex, devAdd2Sig)
	}, "the second entry must chain to the first")

	uassert.AbortsContains(t, cur, "signature does not verify", func() {
		AppendDevice(cross(cur), devAdd1Digest, wesh.OpAdd, dev2Hex, devWrongSeqSig)
	}, "a signature made for another sequence number is not accepted at this one")
}

func TestDeviceSigchainRejectsMeaninglessOps(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)
	AppendDevice(cross(cur), genesisDigestHex, wesh.OpAdd, dev1Hex, devAdd1Sig)

	uassert.AbortsContains(t, cur, "already active", func() {
		AppendDevice(cross(cur), devAdd1Digest, wesh.OpAdd, dev1Hex, devAdd1Sig)
	})
	uassert.AbortsContains(t, cur, "not active, nothing to revoke", func() {
		AppendDevice(cross(cur), devAdd1Digest, wesh.OpRevoke, dev2Hex, devAdd2Sig)
	})
	uassert.AbortsContains(t, cur, "add or revoke", func() {
		AppendDevice(cross(cur), devAdd1Digest, "delete", dev2Hex, devAdd2Sig)
	})
	uassert.AbortsContains(t, cur, "device key", func() {
		AppendDevice(cross(cur), devAdd1Digest, wesh.OpAdd, "abcd", devAdd2Sig)
	})
}

func TestSetDisplayName(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)

	SetDisplayName(cross(cur), "Alice, support line")
	uassert.Equal(t, "Alice, support line", lookup("alice").displayName)

	testing.SetRealm(testing.NewUserRealm(bobAddr()))
	uassert.AbortsContains(t, cur, "no identity registered", func() {
		SetDisplayName(cross(cur), "hijacked")
	})
}

func TestRelease(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(aliceAddr()))
	Register(cross(cur), "alice", aliceAccountPKHex, aliceSeed1Hex, "Alice", aliceBind1Sig)
	Release(cross(cur))

	uassert.Equal(t, 0, Count())
	_, _, _, ok := Resolve("alice")
	uassert.False(t, ok)
	uassert.Equal(t, "", NameOf(aliceAddr()))

	// the name and the account key are both free again
	testing.SetRealm(testing.NewUserRealm(bobAddr()))
	Register(cross(cur), "alice", bobAccountPKHex, aliceSeed1Hex, "", bobBind1Sig)
	uassert.Equal(t, 1, Count())
}

func TestReadersOnUnknownNames(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, "", Link("nope"))
	uassert.Equal(t, "", RendezvousPointAt("nope", 0))
	uassert.Equal(t, "", SigchainHead("nope"))
	uassert.Equal(t, "unknown", DeviceStatus("nope", dev1Hex))
	uassert.Equal(t, "unknown", DeviceStatus("nope", "not-hex"))
	_, _, _, ok := Resolve("nope")
	uassert.False(t, ok)
}

func hexOf(b []byte) string {
	const digits = "0123456789abcdef"
	out := make([]byte, 0, len(b)*2)
	for _, c := range b {
		out = append(out, digits[c>>4], digits[c&0x0f])
	}
	return string(out)
}
