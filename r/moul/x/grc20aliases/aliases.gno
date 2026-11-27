// Package grc20aliases maps curated short names to keys in the permissionless
// GRC20 registry. Consumers can also resolve registered canonical keys directly.
package grc20aliases

import (
	"chain"
	"sort"

	"gno.land/p/moul/authz/v1"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/toolbox/v0"
	"gno.land/r/nt/grc20reg/v0"
)

const (
	maxAliasLen = 32
	maxAliases  = 100
)

var (
	aliases = make(map[string]string) // alias -> canonical registry key
	curator *authz.Authorizer
	pending address
)

func init(cur realm) {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	curator = authz.NewWithMembers(cur.Previous().Address())
}

func validAlias(name string) bool {
	return len(name) <= maxAliasLen && toolbox.ValidSlug(name) && name[0] != '-' && name[len(name)-1] != '-'
}

// Resolve returns a canonical registry key or the empty string if it is
// unknown. The alias alphabet excludes the separators in canonical keys.
func Resolve(nameOrKey string) string {
	key := nameOrKey
	if validAlias(nameOrKey) {
		key = aliases[nameOrKey]
	}
	if key == "" || grc20reg.Get(key) == nil {
		return ""
	}
	return key
}

// SetAlias adds or updates an alias. Supply an empty expectedKey to create
// it, or the exact current key to update it. Only the curator can write.
func SetAlias(cur realm, name, expectedKey, key string) {
	err := curator.DoByPrevious(0, cur, "set_alias", func() error {
		if !validAlias(name) {
			panic("invalid alias")
		}
		if aliases[name] != expectedKey {
			panic("alias changed")
		}
		if key == "" || grc20reg.Get(key) == nil {
			panic("unknown registry key")
		}
		if key == expectedKey {
			return nil
		}
		if expectedKey == "" && len(aliases) >= maxAliases {
			panic("alias limit reached")
		}
		aliases[name] = key
		chain.Emit("TokenAliasSet", "alias", name, "previous", expectedKey, "key", key)
		return nil
	})
	if err != nil {
		panic(err)
	}
}

// RemoveAlias removes an existing alias if it still points to expectedKey.
func RemoveAlias(cur realm, name, expectedKey string) {
	err := curator.DoByPrevious(0, cur, "remove_alias", func() error {
		if expectedKey == "" || aliases[name] != expectedKey {
			panic("alias changed")
		}
		delete(aliases, name)
		chain.Emit("TokenAliasRemoved", "alias", name, "key", expectedKey)
		return nil
	})
	if err != nil {
		panic(err)
	}
}

// ProposeCurator nominates a user or DAO realm address. An empty address
// cancels the nomination. The current curator stays in charge until accepted.
func ProposeCurator(cur realm, next address) {
	err := curator.DoByPrevious(0, cur, "propose_curator", func() error {
		if next != "" && !next.IsValid() {
			panic("invalid curator address")
		}
		pending = next
		chain.Emit("TokenAliasCuratorProposed", "curator", next.String())
		return nil
	})
	if err != nil {
		panic(err)
	}
}

// AcceptCurator transfers curation to the nominated immediate caller.
func AcceptCurator(cur realm) {
	if !cur.IsCurrent() || pending == "" || cur.Previous().Address() != pending {
		panic("not the nominated curator")
	}
	curator = authz.NewWithMembers(pending)
	chain.Emit("TokenAliasCuratorAccepted", "curator", pending.String())
	pending = ""
}

func Render(path string) string {
	if path != "" {
		key := Resolve(path)
		if key == "" {
			return "Unknown token alias or registry key."
		}
		return "# " + ui.Inline(grc20reg.Get(key).GetName()) + "\n\nRegistry key: " + ui.Inline(key) + "\n"
	}

	names := make([]string, 0, len(aliases))
	for name := range aliases {
		names = append(names, name)
	}
	sort.Strings(names)
	table := ui.NewTable("Alias", "Canonical registry key")
	for _, name := range names {
		table.Row(ui.Cell(name), ui.Cell(aliases[name]))
	}
	return "# GRC20 token aliases\n\n" + table.OrEmpty("No aliases have been curated yet.")
}
