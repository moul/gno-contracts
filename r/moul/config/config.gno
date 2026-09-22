// Package config is the one realm moul's other realms read their settings
// from: a key/value store plus the manager list that decides who may write it.
//
// # Why a realm and not a constant
//
// A value shared by several contracts, hardcoded in each, is changed by
// redeploying each. On mainnet a public realm cannot even be redeployed at its
// own path, so "changing it" means a new version and a new path for every
// consumer. Here it is a transaction.
//
// # Bump rarely, and never for a new setting
//
// This realm IS public and versioned, so its path moves on every bump. That
// makes a bump expensive, which is exactly why the settings API is generic: a
// new setting is a new KEY, and a key costs one transaction. Only a change to
// the shape of this realm (a new function, a changed signature) is worth a
// version.
//
// # When a bump does happen, the state does not move
//
// A later version imports this one and relays to it rather than holding
// anything of its own, so v1, v2 and v3 all read and write the same settings,
// the same pause and the same member list. Delegation only runs backwards in
// time, which is why the root is the oldest version that has the state and not
// the newest. See proxy.gno.
//
// # What lives here
//
// settings.gno  the key/value store, and the mygnoscan accessors over it
// keys.gno      the key grammar: a name, optionally scoped to one realm
// blocks.gno    the notice a realm renders above and below its content
// pause.gno     the switch a realm checks before it acts
// proxy.gno     the relay that lets a later version share this state
// config.gno    the member list, unchanged from v0
//
// # Governance
//
// init seeds the authority with the deploying EOA. Everything that writes goes
// through Authorizer, so transferring authority to a DAO transfers the
// settings with it: there is no address hardcoded on the write path.
package config

import (
	"errors"

	"gno.land/p/moul/authz/v0"
)

var Authorizer *authz.Authorizer

func init(cur realm) {
	if !cur.Previous().IsUserCall() {
		panic("r/moul/config must be initialized by an EOA")
	}
	Authorizer = authz.NewWithMembers(cur.Previous().Address())
}

// AddManager adds a new address to the list of authorized managers.
// This only works if the current authority is a MemberAuthority.
// The caller must be authorized by the current authority.
func AddManager(cur realm, addr address) error {
	memberAuth, ok := Authorizer.Authority().(*authz.MemberAuthority)
	if !ok {
		return errors.New("current authority is not a MemberAuthority, cannot add manager directly")
	}
	return memberAuth.AddMember(0, cur, addr)
}

// RemoveManager removes an address from the list of authorized managers.
// This only works if the current authority is a MemberAuthority.
// The caller must be authorized by the current authority.
func RemoveManager(cur realm, addr address) error {
	memberAuth, ok := Authorizer.Authority().(*authz.MemberAuthority)
	if !ok {
		return errors.New("current authority is not a MemberAuthority, cannot remove manager directly")
	}
	return memberAuth.RemoveMember(0, cur, addr)
}

// TransferManagement transfers the authority to manage keys to a new authority.
// The caller must be authorized by the current authority.
func TransferManagement(cur realm, newAuthority authz.Authority) error {
	if newAuthority == nil {
		return errors.New("new authority cannot be nil")
	}
	return Authorizer.Transfer(0, cur, newAuthority)
}

// ListManagers returns a slice of all managed keys.
func ListManagers(cur realm) []address {
	var keyList []address
	memberAuth, ok := Authorizer.Authority().(*authz.MemberAuthority)
	if !ok {
		return keyList
	}
	tree := memberAuth.Tree()
	if !ok || tree == nil {
		return keyList // Return empty list if tree is not as expected or nil
	}
	tree.Iterate("", "", func(key string, _ any) bool {
		keyList = append(keyList, address(key))
		return false
	})
	return keyList
}

func HasManager(cur realm, addr address) bool {
	memberAuth, ok := Authorizer.Authority().(*authz.MemberAuthority)
	if !ok {
		return false // Return false if not a MemberAuthority or doesn't exist
	}
	// Use the MemberAuthority's specific RemoveMember method,
	// which internally performs the authorization check.
	return memberAuth.Has(addr)
}
