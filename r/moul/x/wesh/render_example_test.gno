package wesh

import (
	"encoding/hex"

	"gno.land/p/moul/x/wesh/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

// seedDemo puts the realm into a fixed state for the examples below.
//
// It writes the globals directly instead of going through the crossing API:
// realm globals persist for the whole test binary and examples run after every
// Test, so an example that did not reset would pin whatever the last test left
// behind. Heights are literals for the same reason.
func seedDemo() {
	byName = avl.Tree{}
	byOwner = avl.Tree{}
	byAccount = avl.Tree{}

	pk, _ := hex.DecodeString("2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12")
	seed1, _ := hex.DecodeString("abababababababababababababababababababababababababababababababab")
	seed2, _ := hex.DecodeString("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
	dev1, _ := hex.DecodeString("0707070707070707070707070707070707070707070707070707070707070707")
	dev2, _ := hex.DecodeString("0909090909090909090909090909090909090909090909090909090909090909")
	d1, _ := hex.DecodeString("bc51799b5d012dc7ce806b4c63474b1e2db515e7d1622ecd5900b23e1d6a9519")
	d2, _ := hex.DecodeString("b0da03f83e5349e92bc524714862daa850750f756ca6fd47264333fbf2175c15")
	d3, _ := hex.DecodeString("ef0c1d0614420c7d660f8416b18651206118e49e8f46ac0360bef61ae6b9100d")

	alice := &identity{
		name:        "alice",
		owner:       testutils.TestAddress("alice"),
		accountPK:   pk,
		payload:     seed2,
		revision:    2,
		displayName: "Alice, support line",
		history: []rotation{
			{revision: 1, payload: seed1, height: 100},
			{revision: 2, payload: seed2, height: 140},
		},
		devices: []deviceEntry{
			{seq: 0, op: wesh.OpAdd, devicePK: dev1, digest: d1, height: 110},
			{seq: 1, op: wesh.OpAdd, devicePK: dev2, digest: d2, height: 120},
			{seq: 2, op: wesh.OpRevoke, devicePK: dev1, digest: d3, height: 130},
		},
		head: d3,
	}
	byName.Set(alice.name, alice)
	byOwner.Set(alice.owner.String(), alice.name)
	byAccount.Set(hex.EncodeToString(pk), alice.name)
}

// ExampleRender pins the directory index.
func ExampleRender() {
	seedDemo()
	print(Render(""))
	// Output:
	// # Wesh directory
	//
	// Resolvable, self-signed [Wesh protocol](https://berty.tech/docs/protocol/) identities, on top of [`p/moul/x/wesh`](/p/moul/x/wesh/v0).
	//
	// A Berty identity normally travels out of band as a QR code, cannot be looked up, cannot announce a seed rotation, and can never revoke a device. This realm addresses those three, and stores no secret of any kind.
	//
	// | name | owner | rev | mode | devices |
	// |---|---|---|---|---|
	// | [alice](/r/moul/x/wesh/v0:alice) | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | 2 | published | 1 active / 3 entries |
	//
	// 1 identity.
}

// ExampleRender_identity pins one identity card: the Berty link, today's
// rendezvous point, the device sigchain and the rotation history.
func ExampleRender_identity() {
	seedDemo()
	print(Render("alice"))
	// Output:
	// # alice
	//
	// _Alice, support line_
	//
	// | field | value |
	// |---|---|
	// | owner | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` |
	// | account key | `2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12` |
	// | mode | published |
	// | revision | 2 |
	// | registered | block 100 |
	//
	// ## Contact
	//
	// Scan or open this in Berty to send a contact request:
	//
	// ```
	// https://berty.tech/id#contact/oZBLGHCDNRB847rT1zHe1xnon58fpWTUsuNntmAo9TK42aKzt14A1V5W67QoN5YzMouuVcucUiBWjN9d2qzy6gUNM4Jio4M/name=Alice%2C+support+line
	// ```
	//
	// | field | value |
	// |---|---|
	// | rendezvous seed | `eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee` |
	// | rendezvous point, period 1234483200 | `08ab5591fbd91f0251a7efe4856fc736a02d1a2252139483ddc8ca85f4616e07` |
	//
	// The point is `HMAC-SHA256(accountPK || seed, be64(period))`, derived exactly as weshnet derives it, and it rotates every 24h. Anyone can recompute it and check the DHT, so this entry is verifiable rather than merely asserted.
	//
	// ## Devices
	//
	// Every entry below was signed by the account key and verified on chain, and chains to the digest of the one before it.
	//
	// | seq | op | device | block | digest |
	// |---|---|---|---|---|
	// | 0 | add | `07070707…07070707` | 110 | `bc51799b…1d6a9519` |
	// | 1 | add | `09090909…09090909` | 120 | `b0da03f8…f2175c15` |
	// | 2 | revoke | `07070707…07070707` | 130 | `ef0c1d06…e6b9100d` |
	//
	// Head: `ef0c1d0614420c7d660f8416b18651206118e49e8f46ac0360bef61ae6b9100d`
	//
	// ## Rotation history
	//
	// Weshnet has no way to announce that a seed was reset, so every link ever shared dies silently. These are the superseded values, kept so a stale link can be recognised as stale.
	//
	// | rev | value | block |
	// |---|---|---|
	// | 1 | `abababab…abababab` | 100 |
	// | 2 (current) | `eeeeeeee…eeeeeeee` | 140 |
	//
	// [Back to the directory](/r/moul/x/wesh/v0) · chain `dev`
}

// ExampleRender_unknown pins the miss.
func ExampleRender_unknown() {
	seedDemo()
	print(Render("nobody"))
	// Output:
	// # Not found
	//
	// No identity named `nobody`. [Back to the directory](/r/moul/x/wesh/v0).
}
