package vault

import (
	"chain"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// vaults maps address string -> *avl.Tree (key string -> value string).
var vaults avl.Tree

// vaultFor returns the caller's namespace tree, creating it if needed.
func vaultFor(owner address) *avl.Tree {
	k := owner.String()
	if v, ok := vaults.Get(k); ok {
		return v.(*avl.Tree)
	}
	t := &avl.Tree{}
	vaults.Set(k, t)
	return t
}

// Set stores value under key in the caller's own namespace.
func Set(cur realm, key string, value string) {
	if key == "" {
		panic("key must not be empty")
	}
	caller := unsafe.PreviousRealm().Address()
	t := vaultFor(caller)
	t.Set(key, value)
	chain.Emit("VaultSet", "owner", caller.String(), "key", key)
}

// Delete removes key from the caller's own namespace.
func Delete(cur realm, key string) {
	caller := unsafe.PreviousRealm().Address()
	k := caller.String()
	v, ok := vaults.Get(k)
	if !ok {
		panic("no vault for caller")
	}
	t := v.(*avl.Tree)
	if _, removed := t.Remove(key); !removed {
		panic("key not found")
	}
	if t.Size() == 0 {
		vaults.Remove(k)
	}
	chain.Emit("VaultDelete", "owner", caller.String(), "key", key)
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
		b.WriteString("](/r:")
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
	b.WriteString(addr)
	b.WriteString("\n\n")
	v, ok := vaults.Get(addr)
	if !ok {
		b.WriteString("_No vault for this address._\n")
		return b.String()
	}
	t := v.(*avl.Tree)
	b.WriteString("| Key | Value |\n")
	b.WriteString("|---|---|\n")
	t.Iterate("", "", func(k string, val interface{}) bool {
		b.WriteString("| ")
		b.WriteString(k)
		b.WriteString(" | ")
		b.WriteString(val.(string))
		b.WriteString(" |\n")
		return false
	})
	b.WriteString("\nTotal entries: ")
	b.WriteString(strconv.Itoa(t.Size()))
	b.WriteString("\n")
	return b.String()
}
