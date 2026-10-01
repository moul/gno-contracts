package vault

import (
	"chain"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/nt/avl/v0"
)

// selfPath is this realm's own page. A root-relative link resolves against
// the domain, not the realm, so every link back into it names it in full.
const selfPath = "/r/moul/x/daily/vault/v1"

// vaults maps address string -> *avl.Tree (key string -> value string).
var vaults avl.Tree

// The bounds on what a caller may store. Anyone may open a vault, the root
// page lists every vault, and a vault's page lists every entry.
const (
	MaxVaults   = 1000
	MaxEntries  = 100 // per vault
	MaxKeyLen   = 64
	MaxValueLen = 512
)

// vaultFor returns the caller's namespace tree, creating it if needed.
func vaultFor(owner address) *avl.Tree {
	k := owner.String()
	if v := vaults.Get(k); v != nil {
		return v.(*avl.Tree)
	}
	if vaults.Size() >= MaxVaults {
		panic("vault is full at " + strconv.Itoa(MaxVaults) + " vaults")
	}
	t := &avl.Tree{}
	vaults.Set(k, t)
	return t
}

// Set stores value under key in the caller's own namespace.
func Set(cur realm, key string, value string) {
	who := caller(cur)
	if key == "" {
		panic("key must not be empty")
	}
	if len(key) > MaxKeyLen || len(value) > MaxValueLen {
		panic("key or value too long")
	}
	t := vaultFor(who)
	if !t.Has(key) && t.Size() >= MaxEntries {
		panic("a vault holds at most " + strconv.Itoa(MaxEntries) + " entries")
	}
	t.Set(key, value)
	chain.Emit("VaultSet", "owner", who.String(), "key", key)
}

// Delete removes key from the caller's own namespace.
func Delete(cur realm, key string) {
	who := caller(cur)
	k := who.String()
	v := vaults.Get(k)
	if v == nil {
		panic("no vault for caller")
	}
	t := v.(*avl.Tree)
	if _, removed := t.Remove(key); !removed {
		panic("key not found")
	}
	if t.Size() == 0 {
		vaults.Remove(k)
	}
	chain.Emit("VaultDelete", "owner", who.String(), "key", key)
}

// Render shows all vaults (root) or a single address's entries ("/<address>").
func Render(path string) string {
	p := strings.TrimPrefix(path, "/")
	if p == "" {
		return renderRoot()
	}
	return renderAddress(p)
}

func renderRoot() string {
	var b strings.Builder
	b.WriteString("# Key-Value Vault\n\n")
	b.WriteString("A per-address key-value store. Each caller owns their own namespace; only the owner can mutate their entries.\n\n")
	if vaults.Size() == 0 {
		b.WriteString("_No vaults yet. Call `Set(cur, key, value)` to create one._\n")
		return b.String()
	}
	b.WriteString("## Vaults\n\n")
	b.WriteString("| Address | Entries |\n")
	b.WriteString("|---|---|\n")
	vaults.Iterate("", "", func(k string, v interface{}) bool {
		t := v.(*avl.Tree)
		b.WriteString("| [")
		b.WriteString(k)
		b.WriteString("](" + selfPath + ":")
		// link back into this realm's render for the address subpage
		b.WriteString(k)
		b.WriteString(") | ")
		b.WriteString(strconv.Itoa(t.Size()))
		b.WriteString(" |\n")
		return false
	})
	b.WriteString("\nView an address's entries at path `/<address>`.\n")
	return b.String()
}

func renderAddress(addr string) string {
	var b strings.Builder
	b.WriteString("# Vault: ")
	b.WriteString(ui.Inline(addr))
	b.WriteString("\n\n")
	v := vaults.Get(addr)
	if v == nil {
		b.WriteString("_No vault for this address._\n")
		return b.String()
	}
	t := v.(*avl.Tree)
	b.WriteString("| Key | Value |\n")
	b.WriteString("|---|---|\n")
	t.Iterate("", "", func(k string, val interface{}) bool {
		b.WriteString("| ")
		b.WriteString(ui.Cell(k))
		b.WriteString(" | ")
		b.WriteString(ui.Cell(val.(string)))
		b.WriteString(" |\n")
		return false
	})
	b.WriteString("\nTotal entries: ")
	b.WriteString(strconv.Itoa(t.Size()))
	b.WriteString("\n")
	return b.String()
}

// caller is the address that crossed into this realm, after checking that the
// realm token is this frame's own.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("vault: spoofed realm")
	}
	return cur.Previous().Address()
}
