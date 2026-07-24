// Package handles is a tiny on-chain nickname registry.
//
// Any address may claim one unique handle (3-20 lowercase letters/digits,
// starting with a letter), attach a short bio, transfer the handle to
// another address, or release it back to the pool. It is deliberately
// small: two AVL indexes (handle -> record, address -> record) and a
// handful of guarded mutators.
package handles

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

const maxBioLen = 140

// record is the persisted state for one claimed handle.
type record struct {
	handle   string
	owner    address
	bio      string
	sinceBlk int64
}

var (
	byHandle avl.Tree // handle (string)      -> *record
	byOwner  avl.Tree // owner address.String() -> *record
)

// validHandle reports whether h is 3-20 chars, starts with a lowercase
// letter, and contains only lowercase letters and digits thereafter.
func validHandle(h string) bool {
	if len(h) < 3 || len(h) > 20 {
		return false
	}
	for i := 0; i < len(h); i++ {
		c := h[i]
		switch {
		case c >= 'a' && c <= 'z':
		case c >= '0' && c <= '9' && i > 0:
		default:
			return false
		}
	}
	return true
}

// Register claims handle for the caller. Aborts if the handle is invalid,
// already taken, or the caller already owns a handle (release it first).
func Register(cur realm, handle string) {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	if !cur.Previous().IsUserCall() {
		panic("only a direct user call can register a handle")
	}
	if !validHandle(handle) {
		panic("handle must be 3-20 lowercase letters/digits, starting with a letter")
	}
	caller := cur.Previous().Address()
	if byOwner.Has(caller.String()) {
		panic("this address already owns a handle; release it first")
	}
	if byHandle.Has(handle) {
		panic("handle already taken")
	}

	r := &record{
		handle:   handle,
		owner:    caller,
		sinceBlk: runtime.ChainHeight(),
	}
	byHandle.Set(handle, r)
	byOwner.Set(caller.String(), r)
	chain.Emit("HandleRegistered", "handle", handle, "owner", caller.String())
}

// SetBio updates the bio of the handle owned by the caller.
func SetBio(cur realm, bio string) {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	if len(bio) > maxBioLen {
		panic("bio too long (max " + strconv.Itoa(maxBioLen) + " chars)")
	}
	r := ownRecord(cur)
	r.bio = bio
	chain.Emit("BioUpdated", "handle", r.handle)
}

// Release frees the handle owned by the caller, making it claimable again.
func Release(cur realm) {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	r := ownRecord(cur)
	byHandle.Remove(r.handle)
	byOwner.Remove(r.owner.String())
	chain.Emit("HandleReleased", "handle", r.handle)
}

// Transfer moves the caller's handle to another address that does not
// already own one.
func Transfer(cur realm, to address) {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	if !to.IsValid() {
		panic("invalid recipient address")
	}
	r := ownRecord(cur)
	if byOwner.Has(to.String()) {
		panic("recipient already owns a handle")
	}
	byOwner.Remove(r.owner.String())
	r.owner = to
	byOwner.Set(to.String(), r)
	chain.Emit("HandleTransferred", "handle", r.handle, "to", to.String())
}

// ownRecord resolves the record for the current caller, panicking if the
// caller does not own a handle.
func ownRecord(cur realm) *record {
	caller := cur.Previous().Address()
	v, ok := byOwner.Get(caller.String())
	if !ok {
		panic("this address does not own a handle")
	}
	return v.(*record)
}

// OwnerOf returns the owner of handle and whether it exists.
func OwnerOf(handle string) (address, bool) {
	v, ok := byHandle.Get(handle)
	if !ok {
		return address(""), false
	}
	return v.(*record).owner, true
}

// HandleOf returns the handle owned by addr, if any.
func HandleOf(addr address) (string, bool) {
	v, ok := byOwner.Get(addr.String())
	if !ok {
		return "", false
	}
	return v.(*record).handle, true
}

// Count returns the number of currently registered handles.
func Count() int {
	return byHandle.Size()
}

// Render renders Markdown. "/" lists every handle; "/<handle>" shows a
// single record's detail.
func Render(path string) string {
	path = strings.TrimPrefix(path, "/")
	if path == "" {
		return renderIndex()
	}
	return renderHandle(path)
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# 🪪 Handles\n\n")
	b.WriteString("A tiny on-chain nickname registry. Claim a short handle, ")
	b.WriteString("attach a bio, transfer it, or release it.\n\n")

	if byHandle.Size() == 0 {
		b.WriteString("_No handles registered yet._\n\n")
		b.WriteString("Call `Register(handle)` to claim the first one.\n")
		return b.String()
	}

	b.WriteString("| Handle | Owner | Since block |\n")
	b.WriteString("|--------|-------|-------------|\n")
	byHandle.Iterate("", "", func(key string, value interface{}) bool {
		r := value.(*record)
		b.WriteString("| [" + key + "](/" + key + ") | " + short(r.owner.String()) +
			" | " + strconv.Itoa(int(r.sinceBlk)) + " |\n")
		return false
	})
	b.WriteString("\nTotal handles: " + strconv.Itoa(byHandle.Size()) + "\n")
	return b.String()
}

func renderHandle(handle string) string {
	v, ok := byHandle.Get(handle)
	if !ok {
		return "# Handles\n\nNo handle named `" + handle + "`.\n\n[← all handles](/)\n"
	}
	r := v.(*record)

	var b strings.Builder
	b.WriteString("# 🪪 @" + r.handle + "\n\n")
	b.WriteString("**Owner:** " + r.owner.String() + "\n\n")
	if r.bio != "" {
		b.WriteString("**Bio:** " + r.bio + "\n\n")
	}
	b.WriteString("**Registered at block:** " + strconv.Itoa(int(r.sinceBlk)) + "\n\n")
	b.WriteString("[← all handles](/)\n")
	return b.String()
}

// short truncates a long address for the index table.
func short(s string) string {
	if len(s) <= 12 {
		return s
	}
	return s[:6] + "…" + s[len(s)-4:]
}
