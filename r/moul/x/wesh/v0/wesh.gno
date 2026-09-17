// Package wesh is an on-chain directory and device sigchain for Wesh protocol
// (weshnet / Berty) identities.
//
// It exists to give weshnet the three things a peer-to-peer network cannot
// give itself, and which a chain is uniquely good at:
//
//  1. Resolution. A Berty identity travels out of band as a QR code or a
//     https://berty.tech/id# link, and there is no way to look one up. Here a
//     name resolves to a contact, and Render emits the real, scannable link.
//  2. Rotation with a paper trail. Resetting the public rendezvous seed
//     silently kills every link ever shared; there is no revocation channel.
//     Here every rotation is a numbered, timestamped, signed entry, and the
//     superseded seeds stay visible, so a stale link resolves to a redirect
//     instead of to nothing.
//  3. Device revocation. The Wesh protocol documentation states plainly that a
//     device, once linked to an account, can never be revoked: the account
//     metadata log is append-only and no authority can void an entry. This
//     realm hosts the log that was missing: a hash-chained, account-signed
//     roster whose every entry the chain verifies with ed25519 before
//     accepting it.
//
// # What this realm does not do, and will not
//
// It never stores a secret. Group secrets, device chain keys, message keys and
// ciphertexts stay off chain, permanently. The library this realm is built on,
// [p/moul/x/wesh](/p/moul/x/wesh/v0), has no type that can hold one.
//
// It also does not pretend to enforce revocation inside weshnet. A revoked
// device's ratchets are already distributed and forward secrecy is a local
// property; no chain can reach into a group and forget them. What revocation
// buys here is that it becomes public, ordered, and attributable to the
// account key, which is strictly more than weshnet has today.
//
// # Publishing is a deliberate act
//
// A published rendezvous seed lets anyone derive the account's rotating
// rendezvous point and watch the DHT for it. That is the same exposure as
// printing your Berty QR code on a billboard, and it is the right trade only
// for an identity that wants to be found: a support line, a shop, a public
// channel.
//
// [RegisterCommitted] is the alternative. It publishes H(seed ‖ salt) instead,
// so the chain attests that a seed handed over out of band really belongs to
// the named account, without broadcasting where that account listens.
//
// # Authentication
//
// Every state-changing call carries an ed25519 signature made with the Wesh
// account private key over a canonical statement that names this chain, the
// caller's gno address, and a monotonic revision or sequence number. Without
// it, anyone could publish anyone else's account key next to a seed of their
// choosing and harvest the contact requests that followed.
package wesh

import (
	"chain/runtime"
	"encoding/hex"
	"strings"
	"time"

	"gno.land/p/moul/x/wesh/v0"
	"gno.land/p/nt/avl/v0"
)

const (
	// MinNameLen and MaxNameLen bound a directory handle.
	MinNameLen = 3
	MaxNameLen = 32

	// MaxDevices bounds one account's sigchain so iteration and Render stay
	// affordable. weshnet accounts hold a handful of devices, not hundreds.
	MaxDevices = 64

	// MaxRotations bounds the retained rotation history. Older entries are
	// dropped from the front: the point of the history is to let a stale link
	// be recognised, not to keep a permanent archive.
	MaxRotations = 32
)

// rotation is one seed (or commitment) an identity has published.
type rotation struct {
	revision int
	payload  []byte
	height   int64
}

// deviceEntry is one verified sigchain statement.
type deviceEntry struct {
	seq      int
	op       string
	devicePK []byte
	digest   []byte
	height   int64
}

// identity is a published Wesh identity bound to one gno address.
//
// payload holds the public rendezvous seed when committed is false, and
// H(seed ‖ salt) when it is true. head is the digest of the last accepted
// sigchain entry, which the next entry must chain to.
type identity struct {
	name        string
	owner       address
	accountPK   []byte
	payload     []byte
	committed   bool
	revision    int
	displayName string
	createdAt   int64
	updatedAt   int64
	history     []rotation
	devices     []deviceEntry
	head        []byte
}

var (
	// byName is the directory, keyed by handle so avl iteration is alphabetical.
	byName avl.Tree
	// byOwner maps a gno address to its handle: one identity per address.
	byOwner avl.Tree
	// byAccount maps a hex account key to its handle, so two handles can never
	// claim the same Wesh account.
	byAccount avl.Tree
)

// Register publishes an identity whose rendezvous seed is public.
//
// sigHex must be an ed25519 signature by the account private key over
// wesh.BindStatement(chainID, caller, accountPK, seed, 1). Revision 1 is fixed
// at registration so a signature captured from a later rotation cannot be
// replayed to re-register the name after it is released.
func Register(cur realm, name, accountPKHex, seedHex, displayName, sigHex string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	register(cur.Previous().Address(), name, accountPKHex, seedHex, displayName, sigHex, false)
}

// RegisterCommitted publishes an identity that keeps its rendezvous point off
// chain: commitmentHex is wesh.SeedCommitment(seed, salt), and the seed itself
// is shared out of band.
//
// The chain still attests the binding (this account key really did claim this
// commitment from this gno address), so a seed later disclosed privately can
// be checked against it. What it does not do is tell the world where the
// account listens.
func RegisterCommitted(cur realm, name, accountPKHex, commitmentHex, displayName, sigHex string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	register(cur.Previous().Address(), name, accountPKHex, commitmentHex, displayName, sigHex, true)
}

// register is shared by Register and RegisterCommitted. It takes the already
// resolved caller rather than a realm: a helper whose first parameter is
// `realm` would be a second crossing hop, and Previous() inside it would
// resolve to this realm rather than to the user who called in.
func register(caller address, name, accountPKHex, payloadHex, displayName, sigHex string, committed bool) {
	name = normalizeName(name)
	assertNameAvailable(name)
	if byOwner.Has(caller.String()) {
		panic("wesh: this address already owns an identity; release it first")
	}

	accountPK := mustAccountPK(accountPKHex)
	if byAccount.Has(accountPKHex) {
		panic("wesh: this account key is already published under another name")
	}
	payload := mustPayload(payloadHex, committed)
	assertDisplayName(displayName)

	if err := wesh.VerifyBind(runtime.ChainID(), caller.String(), accountPK, payload, 1, mustSig(sigHex)); err != nil {
		panic("wesh: " + err.Error())
	}

	now := time.Now().Unix()
	id := &identity{
		name:        name,
		owner:       caller,
		accountPK:   accountPK,
		payload:     payload,
		committed:   committed,
		revision:    1,
		displayName: displayName,
		createdAt:   now,
		updatedAt:   now,
		history:     []rotation{{revision: 1, payload: payload, height: runtime.ChainHeight()}},
		head:        wesh.GenesisDigest(),
	}
	byName.Set(name, id)
	byOwner.Set(caller.String(), name)
	byAccount.Set(accountPKHex, name)
}

// Rotate publishes a new seed (or commitment) for the caller's identity.
//
// This is the operation weshnet's ContactRequestResetReference has no
// counterpart for. There, resetting the seed silently invalidates every link
// ever shared. Here the new value is numbered and the old one stays in the
// history, so a holder of a stale link can see that it was superseded and when.
//
// The signature must be over revision+1, which is what stops a superseded
// binding being replayed to roll a rotation back.
func Rotate(cur realm, payloadHex, sigHex string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	id := mustOwnIdentity(cur.Previous().Address())

	payload := mustPayload(payloadHex, id.committed)
	if string(payload) == string(id.payload) {
		panic("wesh: the new value is identical to the current one")
	}

	next := id.revision + 1
	if err := wesh.VerifyBind(runtime.ChainID(), id.owner.String(), id.accountPK, payload, next, mustSig(sigHex)); err != nil {
		panic("wesh: " + err.Error())
	}

	id.revision = next
	id.payload = payload
	id.updatedAt = time.Now().Unix()
	id.history = append(id.history, rotation{revision: next, payload: payload, height: runtime.ChainHeight()})
	if len(id.history) > MaxRotations {
		id.history = id.history[len(id.history)-MaxRotations:]
	}
}

// AppendDevice adds one entry to the caller's device sigchain.
//
// prevHex must be the digest of the current head (all zeros for the first
// entry), and the signature must cover the whole statement including the
// sequence number and that digest. Chaining every entry to its predecessor is
// what stops the log being reordered or having an entry quietly dropped: any
// gap changes every digest after it.
//
// op is "add" or "revoke". Adding a device that is already active, or revoking
// one that is not, is refused: an append-only log is only useful if its entries
// are meaningful.
func AppendDevice(cur realm, prevHex, op, devicePKHex, sigHex string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	id := mustOwnIdentity(cur.Previous().Address())

	if len(id.devices) >= MaxDevices {
		panic("wesh: device sigchain is full")
	}
	prev, err := wesh.DecodeCommitment(prevHex)
	if err != nil {
		panic("wesh: previous digest: " + err.Error())
	}
	if string(prev) != string(id.head) {
		panic("wesh: previous digest does not match the sigchain head " + hex.EncodeToString(id.head))
	}
	devicePK, err := wesh.DecodeDevicePK(devicePKHex)
	if err != nil {
		panic("wesh: device key: " + err.Error())
	}

	active := deviceIsActive(id, devicePK)
	switch op {
	case wesh.OpAdd:
		if active {
			panic("wesh: device is already active")
		}
	case wesh.OpRevoke:
		if !active {
			panic("wesh: device is not active, nothing to revoke")
		}
	default:
		panic("wesh: operation must be add or revoke")
	}

	seq := len(id.devices)
	digest, err := wesh.VerifyDevice(runtime.ChainID(), id.accountPK, seq, prev, op, devicePK, mustSig(sigHex))
	if err != nil {
		panic("wesh: " + err.Error())
	}

	id.devices = append(id.devices, deviceEntry{
		seq:      seq,
		op:       op,
		devicePK: devicePK,
		digest:   digest,
		height:   runtime.ChainHeight(),
	})
	id.head = digest
	id.updatedAt = time.Now().Unix()
}

// SetDisplayName updates the identity's free-form label.
//
// It carries no signature because it authenticates nothing: the display name
// is app metadata, and berty's own link format keeps it outside the signed
// payload for the same reason. Only the owning address may change it.
func SetDisplayName(cur realm, displayName string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	assertDisplayName(displayName)
	id := mustOwnIdentity(cur.Previous().Address())
	id.displayName = displayName
	id.updatedAt = time.Now().Unix()
}

// Release removes the caller's identity and frees its name and account key.
//
// The sigchain goes with it. That is the honest behaviour: a directory entry
// is a live claim, not an archive, and keeping a dangling roster for a name
// somebody else can now take would be worse than keeping nothing.
func Release(cur realm) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	caller := cur.Previous().Address()
	id := mustOwnIdentity(caller)

	byName.Remove(id.name)
	byOwner.Remove(caller.String())
	byAccount.Remove(hex.EncodeToString(id.accountPK))
}

// --- read-only API, for gnoweb and for other realms ---

// Resolve returns the account key and current payload of a name, both hex, and
// whether the payload is a commitment rather than a seed. ok is false when the
// name is not registered.
func Resolve(name string) (accountPKHex, payloadHex string, committed, ok bool) {
	id := lookup(name)
	if id == nil {
		return "", "", false, false
	}
	return hex.EncodeToString(id.accountPK), hex.EncodeToString(id.payload), id.committed, true
}

// Link returns the shareable Berty web link for a name, or "" when the name is
// unknown or its rendezvous point is committed rather than published.
func Link(name string) string {
	id := lookup(name)
	if id == nil || id.committed {
		return ""
	}
	link, err := contactOf(id).WebLink()
	if err != nil {
		return ""
	}
	return link
}

// RendezvousPointAt returns the hex rendezvous point the named account
// announces on during the rotation period containing unixSec, or "" when the
// name is unknown or committed.
//
// This is what makes a directory entry checkable rather than merely claimed:
// anyone can compare it against the DHT without trusting this realm.
func RendezvousPointAt(name string, unixSec int64) string {
	id := lookup(name)
	if id == nil || id.committed {
		return ""
	}
	point, err := contactOf(id).RendezvousPointAt(unixSec, wesh.DefaultRotationInterval)
	if err != nil {
		return ""
	}
	return hex.EncodeToString(point)
}

// DeviceStatus reports "active", "revoked" or "unknown" for a device under a
// name. "unknown" also covers an unregistered name: a caller must not be able
// to tell those apart by status alone.
func DeviceStatus(name, devicePKHex string) string {
	id := lookup(name)
	if id == nil {
		return "unknown"
	}
	devicePK, err := wesh.DecodeDevicePK(devicePKHex)
	if err != nil {
		return "unknown"
	}
	if !deviceSeen(id, devicePK) {
		return "unknown"
	}
	if deviceIsActive(id, devicePK) {
		return "active"
	}
	return "revoked"
}

// SigchainHead returns the hex digest the next sigchain entry must chain to,
// or "" when the name is unknown. A client builds its next statement from this.
func SigchainHead(name string) string {
	id := lookup(name)
	if id == nil {
		return ""
	}
	return hex.EncodeToString(id.head)
}

// NameOf returns the handle owned by an address, or "".
func NameOf(owner address) string {
	v := byOwner.Get(owner.String())
	if v == nil {
		return ""
	}
	return v.(string)
}

// Count returns the number of registered identities.
func Count() int { return byName.Size() }

// --- helpers ---

func lookup(name string) *identity {
	v := byName.Get(normalizeName(name))
	if v == nil {
		return nil
	}
	return v.(*identity)
}

func contactOf(id *identity) wesh.Contact {
	return wesh.Contact{
		AccountPK:   id.accountPK,
		Seed:        id.payload,
		DisplayName: id.displayName,
	}
}

func deviceIsActive(id *identity, devicePK []byte) bool {
	active := false
	for _, e := range id.devices {
		if string(e.devicePK) != string(devicePK) {
			continue
		}
		active = e.op == wesh.OpAdd
	}
	return active
}

func deviceSeen(id *identity, devicePK []byte) bool {
	for _, e := range id.devices {
		if string(e.devicePK) == string(devicePK) {
			return true
		}
	}
	return false
}

func mustOwnIdentity(caller address) *identity {
	v := byOwner.Get(caller.String())
	if v == nil {
		panic("wesh: no identity registered for this address")
	}
	return lookup(v.(string))
}

func mustAccountPK(s string) []byte {
	pk, err := wesh.DecodeAccountPK(s)
	if err != nil {
		panic("wesh: account key: " + err.Error())
	}
	return pk
}

func mustPayload(s string, committed bool) []byte {
	if committed {
		c, err := wesh.DecodeCommitment(s)
		if err != nil {
			panic("wesh: commitment: " + err.Error())
		}
		return c
	}
	seed, err := wesh.DecodeSeed(s)
	if err != nil {
		panic("wesh: seed: " + err.Error())
	}
	return seed
}

func mustSig(s string) []byte {
	sig, err := hex.DecodeString(s)
	if err != nil || len(sig) != 64 {
		panic("wesh: signature must be 64 hex-encoded bytes")
	}
	return sig
}

func assertDisplayName(s string) {
	if len(s) > wesh.MaxDisplayNameLen {
		panic("wesh: display name is too long")
	}
}

func assertNameAvailable(name string) {
	if len(name) < MinNameLen || len(name) > MaxNameLen {
		panic("wesh: name must be between 3 and 32 characters")
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		ok := (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
		if !ok {
			panic("wesh: name may only contain a-z, 0-9, '-' and '_'")
		}
	}
	if byName.Has(name) {
		panic("wesh: name is already taken")
	}
}

// normalizeName lowercases a handle so lookups are case-insensitive and two
// handles cannot differ only by case.
func normalizeName(name string) string {
	return strings.ToLower(strings.TrimSpace(name))
}
